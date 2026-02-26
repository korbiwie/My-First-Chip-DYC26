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
from cocotb.utils import get_sim_time

from cocotb_tools.runner import get_runner
import random

os.environ['COCOTB_ANSI_OUTPUT'] = '1'

INPUT_FREQ = 25_000_000  # 25 MHz
CLK_PERIOD_NS = 40        # 10 ns

class ClockDividerTester:
    """Helper class for clock divider testing."""

    def __init__(self, dut):
        self.dut = dut
        self.clk = dut.clk
        self.rst_n = dut.rst_n
        self.target_x_hz = dut.target_x_hz

        #self.vga_clk = dut.vga_clk
        self.sim_ce = dut.sim_ce

    async def reset(self):
        self.rst_n.value = False
        await RisingEdge(self.clk)
        self.rst_n.value = True
        await FallingEdge(self.clk)

    async def wait_for_signal_high(self, signal):
        """Wait until signal becomes 1, sampling on every clk rising edge."""
        while signal.value != 1:
            await RisingEdge(self.clk)

    async def measure_signal_period(self, signal, cycles=1):
        """Measure approximate period of signal by polling each clk edge."""
        # wait for first rising edge
        await self.wait_for_signal_high(signal)
        t1 = get_sim_time(units="ns")

        for _ in range(cycles):
            # wait for signal to go low then high again
            while signal.value != 0:
                await RisingEdge(self.clk)
            while signal.value != 1:
                await RisingEdge(self.clk)

        t2 = get_sim_time(units="ns")
        return (t2 - t1) / cycles

# @cocotb.test()
# async def test_vga_clock(dut):
#     """Test: Check the VGA clock functionality"""
#     tester = ClockDividerTester(dut)

#     clock = Clock(dut.clk, CLK_PERIOD_NS, unit="ns")
#     cocotb.start_soon(clock.start())

#     await tester.reset()

#     measured_period = await tester.measure_signal_period(dut.vga_clk)
#     expected_period = 4 * CLK_PERIOD_NS
#     assert abs(measured_period - expected_period) <= 1, f"VGA period wrong: {measured_period} ns, expected {expected_period} ns"

#     for _ in range(10):
#         await RisingEdge(tester.clk)

#     dut._log.info("VGA clock test passed")

@cocotb.test()
async def test_target_x_hz(dut):
    """Test: Check the target x Hz functionality"""
    tester = ClockDividerTester(dut)

    clock = Clock(dut.clk, CLK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    await tester.reset()

    target_hz = 50  # 255 Hz

    dut.target_x_hz.value = target_hz

    measured_period_ns = await tester.measure_signal_period(dut.sim_ce)
    expected_period_ns = 1_000_000_000 / target_hz  # ns
    tolerance = expected_period_ns * 0.05  # 5% tolerance

    assert abs(measured_period_ns - expected_period_ns) <= tolerance, f"sim_ce period wrong: {measured_period_ns} ns, expected {expected_period_ns} ns"

    dut._log.info("Target x Hz test passed")

def test_clock_divider_runner():
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent.parent

    sources = [proj_path / "src" / "clock_divider.sv"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="clock_divider",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )

    runner.test(hdl_toplevel="clock_divider", test_module="test_clock_divider", waves=True)

if __name__ == "__main__":
    test_clock_divider_runner()