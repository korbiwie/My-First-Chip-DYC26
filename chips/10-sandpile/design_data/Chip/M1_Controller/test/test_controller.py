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

class ControllerTester:
    """Helper class for  controller testing."""

    def __init__(self, dut):
        self.dut = dut
        self.clk = dut.clk
        self.rst_n = dut.rst_n
        self.start = dut.start
        self.reset_software = dut.reset_software
        self.grid_size = dut.grid_size
        self.drop_mode = dut.drop_mode
        self.speed = dut.speed

        self.reset_n = dut.reset_n
        self. game_active_o = dut.game_active_o
        self.resolution_o = dut.resolution_o
        self.speed_o = dut.speed_o

    async def reset(self):
        self.rst_n.value = False
        await RisingEdge(self.clk)
        self.rst_n.value = True
        await FallingEdge(self.clk)

@cocotb.test()
async def test_reset_state(dut):
    """Test: Check the software reset functionality"""
    tester = ControllerTester(dut)

    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    # Test hardware reset
    await tester.reset()
    assert dut.state.value == 0, f'Expected state to be 0 (RESET), got {dut.state.value}'

    # Test gaming from reset state
    tester.start.value = True
    await RisingEdge(tester.clk)
    await FallingEdge(tester.clk)
    assert dut.state.value == 2, f'Expected state to be 2 (GAMING), got {dut.state.value}'

    # Test software reset
    tester.reset_software.value = True
    await RisingEdge(tester.clk)
    await FallingEdge(tester.clk)
    assert dut.state.value == 0, f'Expected state to be 0 (RESET), got {dut.state.value}'

    dut._log.info("Software reset test passed")

@cocotb.test()
async def test_gaming_state(dut):
    """Test: Check the start game functionality"""
    tester = ControllerTester(dut)

    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    await tester.reset()
    assert dut.reset_n.value == False, f'Expected reset_n to be False, got {tester.reset_n.value}'
    tester.start.value = True
    await RisingEdge(tester.clk)
    await FallingEdge(tester.clk)
    assert dut.state.value == 2, f'Expected state to be 2 (GAMING), got {dut.state.value}'

    # Reset from gaming state
    tester.reset_software.value = True
    await RisingEdge(tester.clk)
    await FallingEdge(tester.clk)
    assert dut.reset_n.value == False, f'Expected reset_n to be False, got {tester.reset_n.value}'
    assert dut.state.value == 0, f'Expected state to be 0 (RESET), got {dut.state.value}'
    tester.reset_software.value = False

    await RisingEdge(tester.clk)
    await FallingEdge(tester.clk)
    assert dut.state.value == 2, f'Expected state to be 2 (GAMING), got {dut.state.value}'

    # Stopped from gaming state
    tester.start.value = False
    await RisingEdge(tester.clk)
    await FallingEdge(tester.clk)
    assert dut.state.value == 1, f'Expected state to be 1 (STOPPED), got {dut.state.value}'

    dut._log.info("Test gaming state passed")

@cocotb.test()
async def test_stopped_state(dut):
    """Test: Check stopped game functionality"""
    tester = ControllerTester(dut)

    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    await tester.reset()
    tester.start.value = True
    await RisingEdge(tester.clk)
    await FallingEdge(tester.clk)
    assert dut.state.value == 2, f'Expected state to be 2 (GAMING), got {dut.state.value}'

    tester.start.value = False
    await RisingEdge(tester.clk)
    await FallingEdge(tester.clk)
    assert dut.state.value == 1, f'Expected state to be 1 (STOPPED), got {dut.state.value}'
    
    # Gaming from stopped state
    tester.start.value = True
    await RisingEdge(tester.clk)
    await FallingEdge(tester.clk)
    assert dut.state.value == 2, f'Expected state to be 2 (GAMING), got {dut.state.value}'

    tester.start.value = False
    await RisingEdge(tester.clk)
    await FallingEdge(tester.clk)
    assert dut.state.value == 1, f'Expected state to be 1 (STOPPED), got {dut.state.value}'

    # Reset from stopped state
    tester.reset_software.value = True
    await RisingEdge(tester.clk)
    await FallingEdge(tester.clk)
    assert dut.reset_n.value == False, f'Expected reset_n to be False, got {tester.reset_n.value}'
    assert dut.state.value == 0, f'Expected state to be 0 (RESET), got {dut.state.value}'
    tester.reset_software.value = False

    dut._log.info("All states test passed")

@cocotb.test()
async def test_parameter_update(dut):
    """Test: Check parameter update functionality"""
    tester = ControllerTester(dut)

    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    await tester.reset()

    # Update parameters
    tester.grid_size.value = 16
    tester.drop_mode.value = 1
    tester.speed.value = 100

    await RisingEdge(tester.clk)
    await FallingEdge(tester.clk)

    assert dut.grid_size.value == 16, f'Expected grid_size to be 16, got {dut.grid_size.value}'
    assert dut.drop_mode.value == 1, f'Expected drop_mode to be 1, got {dut.drop_mode.value}'
    assert dut.speed.value == 100, f'Expected speed to be 100, got {dut.speed.value}'

    dut._log.info("Parameter update test passed")

def test_controller_runner():
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent.parent

    sources = [proj_path / "src" / "controller.sv"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="controller",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )

    runner.test(hdl_toplevel="controller", test_module="test_controller", waves=True)

if __name__ == "__main__":
    test_controller_runner()