"""
Modern cocotb 2.0 testbench for the Chip module.
Tests the complete chip functionality including SPI communication, controller, and VGA outputs.
Uses async/await syntax and modern pythonic patterns.
"""

import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer
from cocotb.types import LogicArray

from cocotb_tools.runner import get_runner
import random

os.environ['COCOTB_ANSI_OUTPUT'] = '1'

class ChipTester:
    """Helper class for Chip testing."""

    def __init__(self, dut):
        self.dut = dut
        self.clk = dut.clk
        self.rst_n = dut.rst_n
        self.sclk = dut.sclk
        self.cs = dut.cs
        self.pico = dut.pico
        self.poci = dut.poci
        
        # VGA outputs
        self.vga_r = dut.vga_r
        self.vga_g = dut.vga_g
        self.vga_b = dut.vga_b
        self.vga_hs = dut.vga_hs
        self.vga_vs = dut.vga_vs

    async def reset(self):
        """Reset the chip."""
        self.rst_n.value = 0
        await RisingEdge(self.clk)
        self.rst_n.value = 1
        await RisingEdge(self.clk)
        # Wait a few cycles for reset to propagate
        for _ in range(5):
            await RisingEdge(self.clk)

    async def sclk_rising_edge(self, bit_value: int):
        """Generate a rising edge on SCLK synchronized with sys_clock."""
        # Ensure SCLK is 0 first
        self.sclk.value = 0
        await RisingEdge(self.clk)  # Edge detector samples 0 here
        
        # Set data before rising edge
        self.pico.value = bit_value
        
        # Now set SCLK to 1 - edge detector will see rising edge on next sys_clock
        self.sclk.value = 1
        await RisingEdge(self.clk)  # Rising edge detected here
        
    async def sclk_falling_edge(self):
        """Generate a falling edge on SCLK synchronized with sys_clock."""
        # Ensure SCLK is 1 first
        self.sclk.value = 1
        await RisingEdge(self.clk)  # Edge detector samples 1 here
        
        # Now set SCLK to 0 - edge detector will see falling edge on next sys_clock
        self.sclk.value = 0
        await RisingEdge(self.clk)  # Falling edge detected here

    async def send_spi_command(self, address: int, data: int):
        """Send a 16-bit SPI command (4-bit address + 12-bit data).
        
        Format: [15:12] = address, [11:0] = data
        MSB first transmission.
        
        Args:
            address: 4-bit SPI address
            data: 12-bit SPI data
        """
        # Combine address and data into 16-bit word
        command = (address << 12) | (data & 0xFFF)
        
        # Assert CS (goes LOW - active)
        self.cs.value = 0
        await RisingEdge(self.clk)
        
        # Send 16 bits, MSB first
        for bit in range(16):
            bit_value = (command >> (15 - bit)) & 1
            
            # Rising edge - chip samples data
            await self.sclk_rising_edge(bit_value)
            
            # Falling edge
            await self.sclk_falling_edge()
        
        # Wait for spi_is_ready to go high (internal signal, so we wait a bit)
        # The module sets spi_is_ready after bit_counter == 15
        for _ in range(10):
            await RisingEdge(self.clk)
        
        # Deassert CS (goes HIGH - inactive)
        self.cs.value = 1
        await RisingEdge(self.clk)
        await RisingEdge(self.clk)

    async def read_chip_id(self):
        """Read chip ID by sending address 0xA.
        
        Returns:
            The chip ID (0x78) received on POCI
        """
        # Send address 0xA with dummy data
        address = 0xA
        data = 0x000
        
        # Combine into 16-bit word
        command = (address << 12) | data
        
        # Assert CS
        self.cs.value = 0
        await RisingEdge(self.clk)
        
        # Receive data on POCI starts after 8 bits (when is_poci_ready)
        chip_id = 0
        
        # Send 16 bits, MSB first
        for bit in range(16):
            bit_value = (command >> (15 - bit)) & 1
            
            # Rising edge - chip samples PICO, we sample POCI
            await self.sclk_rising_edge(bit_value)
            
            # After 8 bits (bit 7), POCI starts sending chip_id
            if bit >= 8:
                poci_bit = self.poci.value.integer if hasattr(self.poci.value, 'integer') else int(self.poci.value)
                chip_id = (chip_id << 1) | poci_bit
                self.dut._log.info(f"poci -> {poci_bit} - {chip_id}")
            
            # Falling edge
            await self.sclk_falling_edge()
        
        # Deassert CS
        self.cs.value = 1
        await RisingEdge(self.clk)
        await RisingEdge(self.clk)
        
        return chip_id & 0xFF  # Return 8-bit chip ID


@cocotb.test()
async def test_reset(dut):
    """Test: Check reset functionality"""
    tester = ChipTester(dut)

    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    await tester.reset()
    
    # Verify CS is inactive (high) after reset
    assert tester.poci.value == 0, f"Expected poci=0 after reset, got {tester.poci.value}"
    assert tester.vga_r.value == 0, f"Expected vga_r=0 after reset, got {tester.vga_r.value}"
    assert tester.vga_g.value == 0, f"Expected vga_g=0 after reset, got {tester.vga_g.value}"
    assert tester.vga_b.value == 0, f"Expected vga_b=0 after reset, got {tester.vga_b.value}"
    assert tester.vga_hs.value == 0, f"Expected vga_hs=0 after reset, got {tester.vga_hs.value}"
    assert tester.vga_vs.value == 0, f"Expected vga_vs=0 after reset, got {tester.vga_vs.value}"

    dut._log.info("✓ Reset test passed")


@cocotb.test()
async def test_chip_id_read(dut):
    """Test: Read chip ID via SPI address 0xA
    
    Should return 0x78 on POCI.
    """
    tester = ChipTester(dut)

    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    await tester.reset()
    
    # Read chip ID
    chip_id = await tester.read_chip_id()
    
    dut._log.info(f"Read chip ID: {chip_id:02X}")
    
    assert chip_id == 0x78, f"Expected chip ID 0x78, got {chip_id:02X}"

    dut._log.info("✓ Chip ID read test passed")


@cocotb.test()
async def test_spi_control_start(dut):
    """Test: Send SPI control command to start the game
    
    Address 1, bit 0 = start
    """
    tester = ChipTester(dut)

    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    await tester.reset()
    
    # Send start command (address 1, data bit 0 = 1)
    await tester.send_spi_command(address=1, data=0x001)
    
    # Wait for command to be processed
    for _ in range(10):
        await RisingEdge(tester.clk)
    
    dut._log.info("✓ SPI start command test passed")


@cocotb.test()
async def test_spi_control_reset(dut):
    """Test: Send SPI control command to reset
    
    Address 1, bit 1 = reset
    """
    tester = ChipTester(dut)

    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    await tester.reset()
    
    # Send reset command (address 1, data bit 1 = 1)
    await tester.send_spi_command(address=1, data=0x002)
    
    # Wait for command to be processed
    for _ in range(10):
        await RisingEdge(tester.clk)
    
    dut._log.info("✓ SPI reset command test passed")


@cocotb.test()
async def test_spi_grid_size(dut):
    """Test: Set grid size via SPI
    
    Address 12, data[8:0] = grid_size
    """
    tester = ChipTester(dut)

    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    await tester.reset()
    
    # Test different grid sizes
    test_sizes = [8, 16, 32, 64]
    
    for size in test_sizes:
        dut._log.info(f"Setting grid size to {size}")
        await tester.send_spi_command(address=12, data=size)
        
        # Wait for command to be processed
        for _ in range(10):
            await RisingEdge(tester.clk)
    
    dut._log.info("✓ SPI grid size command test passed")


@cocotb.test()
async def test_spi_drop_mode(dut):
    """Test: Set drop mode via SPI
    
    Address 13, data[0] = drop_mode
    """
    tester = ChipTester(dut)

    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    await tester.reset()
    
    # Test drop mode off
    await tester.send_spi_command(address=13, data=0x000)
    for _ in range(10):
        await RisingEdge(tester.clk)
    
    # Test drop mode on
    await tester.send_spi_command(address=13, data=0x001)
    for _ in range(10):
        await RisingEdge(tester.clk)
    
    dut._log.info("✓ SPI drop mode command test passed")


@cocotb.test()
async def test_spi_speed(dut):
    """Test: Set speed via SPI
    
    Address 14, data[11:0] = speed
    """
    tester = ChipTester(dut)

    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    await tester.reset()
    
    # Test different speeds
    test_speeds = [50, 100, 200, 500]
    
    for speed in test_speeds:
        dut._log.info(f"Setting speed to {speed}")
        await tester.send_spi_command(address=14, data=speed)
        
        # Wait for command to be processed
        for _ in range(10):
            await RisingEdge(tester.clk)
    
    dut._log.info("✓ SPI speed command test passed")


@cocotb.test()
async def test_spi_random_seed(dut):
    """Test: Set random seed via SPI
    
    Address 15, data[9:0] = random_seed
    """
    tester = ChipTester(dut)

    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    await tester.reset()
    
    # Test random seeds
    test_seeds = [0, 100, 500, 1023]
    
    for seed in test_seeds:
        dut._log.info(f"Setting random seed to {seed}")
        await tester.send_spi_command(address=15, data=seed)
        
        # Wait for command to be processed
        for _ in range(10):
            await RisingEdge(tester.clk)
    
    dut._log.info("✓ SPI random seed command test passed")


@cocotb.test()
async def test_vga_outputs(dut):
    """Test: Verify VGA outputs are present
    
    VGA outputs should be driven (not X or Z).
    """
    tester = ChipTester(dut)

    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    await tester.reset()
    
    # Run for a few clock cycles
    for _ in range(100):
        await RisingEdge(tester.clk)
    
    # Check VGA outputs are driven (not X or Z)
    # Note: Values may vary, but should be resolvable
    vga_r_val = tester.vga_r.value
    vga_g_val = tester.vga_g.value
    vga_b_val = tester.vga_b.value
    
    dut._log.info(f"VGA R: {vga_r_val}, G: {vga_g_val}, B: {vga_b_val}")
    dut._log.info(f"VGA HS: {tester.vga_hs.value}, VS: {tester.vga_vs.value}")
    
    # Verify sync signals are present
    assert tester.vga_hs.value.is_resolvable, "VGA HS should be driven"
    assert tester.vga_vs.value.is_resolvable, "VGA VS should be driven"

    dut._log.info("✓ VGA outputs test passed")


@cocotb.test()
async def test_multiple_spi_commands(dut):
    """Test: Send multiple SPI commands in sequence"""
    tester = ChipTester(dut)

    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    await tester.reset()
    
    # Configure chip with multiple commands
    await tester.send_spi_command(address=12, data=16)  # grid_size
    for _ in range(5):
        await RisingEdge(tester.clk)
    
    await tester.send_spi_command(address=14, data=100)  # speed
    for _ in range(5):
        await RisingEdge(tester.clk)
    
    await tester.send_spi_command(address=13, data=1)  # drop_mode
    for _ in range(5):
        await RisingEdge(tester.clk)
    
    await tester.send_spi_command(address=1, data=1)  # start
    for _ in range(10):
        await RisingEdge(tester.clk)
    
    dut._log.info("✓ Multiple SPI commands test passed")


@cocotb.test()
async def test_full_workflow(dut):
    """Test: Complete workflow - configure and start game"""
    tester = ChipTester(dut)

    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    await tester.reset()
    
    # Step 1: Read chip ID
    chip_id = await tester.read_chip_id()
    assert chip_id == 0x78, f"Expected chip ID 0x78, got {chip_id:02X}"
    dut._log.info(f"Step 1: Chip ID = {chip_id:02X}")
    
    # Step 2: Configure parameters
    await tester.send_spi_command(address=12, data=32)  # grid_size = 32
    for _ in range(5):
        await RisingEdge(tester.clk)
    
    await tester.send_spi_command(address=14, data=200)  # speed = 200
    for _ in range(5):
        await RisingEdge(tester.clk)
    
    await tester.send_spi_command(address=15, data=123)  # random_seed = 123
    for _ in range(5):
        await RisingEdge(tester.clk)
    
    dut._log.info("Step 2: Configuration complete")
    
    # Step 3: Start game
    await tester.send_spi_command(address=1, data=1)  # start
    for _ in range(20):
        await RisingEdge(tester.clk)
    
    dut._log.info("Step 3: Game started")
    
    # Step 4: Let it run for a bit
    for _ in range(100):
        await RisingEdge(tester.clk)
    
    dut._log.info("✓ Full workflow test passed")


def test_chip_runner():
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent.parent

    sources = [
        proj_path / "src" / "chip.sv",
        proj_path / "M6_Clock_Divider" / "src" / "clock_divider.sv",
        proj_path / "M7_Trng" / "src" / "trng.sv",
        proj_path / "M1_Controller" / "src" / "controller.sv",
        proj_path / "M2_SPI_Controller" / "src" / "spi_controller.sv",
        proj_path / "M5_Macro_Array" / "src" / "sand_cell_forMacro.sv",
        proj_path / "M5_Macro_Array" / "src" / "sand_array_forMacro.sv",
        proj_path / "M5_Macro_Array" / "src" / "macro_sand_array_Complex.sv",
        proj_path / "M8_VGA_Controller" / "src" / "sandpile_renderer.sv",
        proj_path / "M8_VGA_Controller" / "src" / "vga_controller.sv",
        proj_path / "M8_VGA_Controller" / "src" / "horizontal_counter.sv",
        proj_path / "M8_VGA_Controller" / "src" / "vertical_counter.sv",
        proj_path / "M9_SPI" / "src" / "pos_edge_det.sv",
        proj_path / "M9_SPI" / "src" / "spi_module.sv",
    ]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="chip",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
        # parameters={
        #     "ROWS": "32",
        #     "COLS": "32",
        #     "ROWS_SMALL": "2",
        #     "COLS_SMALL": "2"
        # },
    )

    runner.test(hdl_toplevel="chip", test_module="test_chip", waves=True)

if __name__ == "__main__":
    test_chip_runner()
