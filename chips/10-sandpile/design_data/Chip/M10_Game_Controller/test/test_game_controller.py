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
        self.drop_mode = dut.drop_mode
        self.rng = dut.rng

        self.drop_x = dut.drop_x
        self.drop_y = dut.drop_y

    async def reset(self):
        self.rst_n.value = False
        await RisingEdge(self.clk)
        self.rst_n.value = True
        await FallingEdge(self.clk)

@cocotb.test()
async def test_drop_center(dut):
    """Test: Check the software reset functionality"""
    tester = ControllerTester(dut)

    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    # Test hardware reset
    await tester.reset()

    x = int(tester.dut.COLS.value) / 2
    y = int(tester.dut.ROWS.value) / 2

    tester.drop_mode.value = 1
    await RisingEdge(tester.clk)
    await FallingEdge(tester.clk)
    assert int(tester.drop_x.value) == x, f'Expected {x}, got {int(tester.drop_x.value)}'
    assert int(tester.drop_y.value) == y, f'Expected {y}, got {int(tester.drop_y.value)}'

    # check not changed
    await RisingEdge(tester.clk)
    await FallingEdge(tester.clk)
    assert int(tester.drop_x.value) == x, f'Expected {x}, got {int(tester.drop_x.value)}'
    assert int(tester.drop_y.value) == y, f'Expected {y}, got {int(tester.drop_y.value)}'

    dut._log.info("Drop center test passed")


@cocotb.test()
async def test_drop_random(dut):
    """Test: Check the software reset functionality"""
    tester = ControllerTester(dut)

    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    # Test hardware reset
    await tester.reset()

    tester.drop_mode.value = 0

    for i in range(50):
        x = random.randint(0,479)
        y = random.randint(0,479)
        tester.rng.value = x
        await RisingEdge(tester.clk)
        tester.rng.value = y
        await RisingEdge(tester.clk)
        await FallingEdge(tester.clk)
        assert int(tester.drop_x.value) == x, f'Expected {x}, got {int(tester.drop_x.value)}'
        assert int(tester.drop_y.value) == y, f'Expected {y}, got {int(tester.drop_y.value)}'

    dut._log.info("Drop random test passed")


def test_controller_runner():
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent.parent

    sources = [proj_path / "src" / "game_controller.sv"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="game_controller",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )

    runner.test(hdl_toplevel="game_controller", test_module="test_game_controller", waves=True)

if __name__ == "__main__":
    test_controller_runner()