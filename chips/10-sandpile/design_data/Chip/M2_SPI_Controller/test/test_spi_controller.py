"""
Modern cocotb 2.0 testbench for the Controller module.
Uses async/await syntax and modern pythonic patterns.
"""

import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge
from cocotb.types import LogicArray

from cocotb_tools.runner import get_runner
import random

os.environ['COCOTB_ANSI_OUTPUT'] = '1'

class SpiControllerTester:
    """Helper class for SPI controller testing."""

    def __init__(self, dut):
        self.dut = dut
        self.clk = dut.clk
        self.rst_n = dut.rst_n
        self.spi_address = dut.spi_address
        self.spi_data = dut.spi_data
        self.is_ready = dut.is_ready

        self.start_o = dut.start_o
        self.reset_software_o = dut.reset_software_o
        self.grid_size_o = dut.grid_size_o
        self.drop_mode_o = dut.drop_mode_o
        self.speed_o = dut.speed_o
        self.random_seed_o = dut.random_seed_o

    async def reset(self):
        self.rst_n.value = False
        await RisingEdge(self.clk)
        self.rst_n.value = True
        await FallingEdge(self.clk)

    async def send_spi_command(self, address: int, data: int):
        self.spi_address.value = address
        self.spi_data.value = data
        self.is_ready.value = True
        await RisingEdge(self.clk)
        await FallingEdge(self.clk)
        self.is_ready.value = False

    async def check_default_values(self, is_software_reset=False):
        await RisingEdge(self.clk)
        assert self.start_o.value == 0, f'Expected start_o to be 0, got {self.start_o.value}'
        assert self.grid_size_o.value == 8, f'Expected grid_size_o to be 8, got {self.grid_size_o.value}'
        assert self.drop_mode_o.value == 0, f'Expected drop_mode_o to be 0, got {self.drop_mode_o.value}'
        assert self.speed_o.value == 50, f'Expected speed_o to be 50, got {self.speed_o.value}'
        assert self.random_seed_o.value == 0, f'Expected random_seed_o to be 0, got {self.random_seed_o.value}'
        if is_software_reset:
            assert self.reset_software_o.value == 1, f'Expected reset_software_o to be 1, got {self.reset_software_o.value}'
        else:
            assert self.reset_software_o.value == 0, f'Expected reset_software_o to be 0, got {self.reset_software_o.value}'

@cocotb.test()
async def test_hardware_reset(dut):
    """Test: Check the hardware reset functionality"""
    tester = SpiControllerTester(dut)

    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    await tester.reset()
    await tester.check_default_values()

    dut._log.info("Hardware reset test passed")

@cocotb.test()
async def test_software_reset(dut):
    """Test: Check the software reset functionality"""
    tester = SpiControllerTester(dut)

    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    await tester.send_spi_command(1, 0b10)
    await tester.check_default_values(is_software_reset=True)

    dut._log.info("Software reset test passed")

@cocotb.test()
async def test_spi_commands(dut):
    """Test: Check SPI command handling for all parameters"""
    tester = SpiControllerTester(dut)

    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    # Test grid size command
    await tester.send_spi_command(12, 16)
    await RisingEdge(tester.clk)
    assert tester.grid_size_o.value == 16, f'Expected grid_size_o to be 16, got {tester.grid_size_o.value}'

    # Test drop mode command
    await tester.send_spi_command(13, 1)
    await RisingEdge(tester.clk)
    assert tester.drop_mode_o.value == 1, f'Expected drop_mode_o to be 1, got {tester.drop_mode_o.value}'

    # Test speed command
    await tester.send_spi_command(14, 100)
    await RisingEdge(tester.clk)
    assert tester.speed_o.value == 100, f'Expected speed_o to be 100, got {tester.speed_o.value}'

    # Test random seed command
    random_seed = random.randint(0, 1023)  # Generate a random seed within the 10-bit range
    await tester.send_spi_command(15, random_seed)
    assert tester.random_seed_o.value == random_seed, f'Expected random_seed_o to be {random_seed}, got {tester.random_seed_o.value}'

    dut._log.info("SPI commands test passed")


def test_spi_controller_runner():
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent.parent

    sources = [proj_path / "src" / "spi_controller.sv"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="spi_controller",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )

    runner.test(hdl_toplevel="spi_controller", test_module="test_spi_controller", waves=True)

if __name__ == "__main__":
    test_spi_controller_runner()