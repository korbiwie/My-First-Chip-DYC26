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

import itertools
import numpy

os.environ['COCOTB_ANSI_OUTPUT'] = '1'

class MacroArrayTester:
    """Helper class for sand cell testing."""

    def __init__(self, dut):
        self.dut = dut
        self.clk = dut.clk
        self.rst_n = dut.rst_n
        self.new_frame_i = dut.new_frame_i
        self.drop_i = dut.drop_i
        self.drop_x = dut.drop_x
        self.drop_y = dut.drop_y
        self.resolution = dut.resolution
        self.stack_addr_x = dut.stack_addr_x
        self.stack_addr_y = dut.stack_addr_y
        
        self.stack_data = dut.stack_data
        self.new_data = dut.new_data

        # reference parameters
        self.ROWS = int(self.dut.ROWS.value)
        self.COLS = int(self.dut.COLS.value)
        self.ROWS_SMALL = int(self.dut.ROWS_SMALL.value)
        self.COLS_SMALL = int(self.dut.COLS_SMALL.value)

        #initialise
        self.resolution.value = 15
        self.new_frame_i.value = 0
        self.drop_x.value = 0
        self.drop_y.value = 0
        self.drop_i.value = 0

    async def reset(self):
        self.rst_n.value = False
        await RisingEdge(self.clk)
        await FallingEdge(self.clk)
        self.rst_n.value = True
        # Wait until SRAM was cleared
        for i in range(int(self.dut.TILES_TOTAL.value)*2+10):
            await RisingEdge(self.clk)

    async def drop_sand(self, x, y):
        self.drop_x.value = x
        self.drop_y.value = y
        self.drop_i.value = 1
        await RisingEdge(self.clk) # next drop pos gets only updated on rising clock edge
        await FallingEdge(self.clk) # needed to be sure that new_frame_i is 1 during only one rising edge
        self.new_frame_i.value = 1
        await RisingEdge(self.clk)
        self.new_frame_i.value = 0
        await RisingEdge(self.new_data) # stack gets only updated on rising clock edge
        await FallingEdge(self.clk)
        assert self.new_data.value == True

    # async def check_stack(self, expected_grid):
    #     if self.dut.read_stack_a.value == 1:
    #         stack_o = self.dut.stack_a.value
    #     else:
    #         stack_o = self.dut.stack_b.value

    #     for y in range(int(self.dut.resolution.value)):
    #         for x in range(int(self.dut.resolution.value)):
    #             # simulator treats 3D-array [2:0][rows][cols] as 2D array[rows*cols][2:0]
    #             index = (int(y/self.ROWS_SMALL) * int(int(self.dut.resolution.value)/self.COLS_SMALL) + int(x/self.COLS_SMALL)) * self.ROWS_SMALL * self.COLS_SMALL
    #             index += (x % self.COLS_SMALL) + (y % self.ROWS_SMALL)*self.COLS_SMALL
    #             stack_o_cell = int(stack_o[index])
    #             expected_value = expected_grid[x][y]
    #             assert stack_o_cell == expected_value, f"Mismatch at ({x},{y}) got {stack_o_cell} expected {expected_value}"

    async def check_next_topple(self, topple):
        assert self.dut.toppled.value == topple, f"Mismatch got {self.dut.toppled.value} expected {topple}"
        # update frame without dropping
        self.drop_i.value = 0
        await RisingEdge(self.clk) # next drop pos gets only updated on rising clock edge
        await FallingEdge(self.clk) # needed to be sure that new_frame_i is 1 during only one rising edge
        self.new_frame_i.value = 1
        await RisingEdge(self.clk)
        self.new_frame_i.value = 0
        await RisingEdge(self.new_data) # stack gets only updated on rising clock edge
        await FallingEdge(self.clk)
        assert self.new_data.value == True

    async def check_adressing(self, expected_grid, topple):
        assert self.dut.toppled.value == topple, f"Mismatch got {self.dut.toppled.value} expected {topple}"
        # only read stack, no update
        self.drop_i.value = 0
        self.new_frame_i.value = 0
        self.stack_addr_x.value = 0
        self.stack_addr_y.value = 0
        await RisingEdge(self.clk)
        print("Check adressing", int(self.dut.resolution.value), int(self.dut.resolution.value))

        for y in range(int(self.dut.resolution.value)):
            for x in range(int(self.dut.resolution.value)):
                # simulator treats 3D-array [2:0][rows][cols] as 2D array[rows*cols][2:0]
                self.stack_addr_x.value = x
                self.stack_addr_y.value = y
                await RisingEdge(self.clk)  # update of stack_data takes 1 cycle
                await RisingEdge(self.clk)
                await RisingEdge(self.clk)
                stack_o_cell = self.stack_data.value
                expected_value = expected_grid[x][y]
                assert stack_o_cell == expected_value, f"Mismatch at ({x},{y}) got {stack_o_cell} expected {expected_value}"

    async def fill_stack(self, value):
        stack_o = self.dut.stack_a.value
        for i in range(int(self.dut.resolution.value)*int(self.dut.resolution.value)):
            stack_o[i] = value          # simulator treats 3D-array [2:0][rows][cols] as 2D array[rows*cols][2:0]

        if self.dut.read_stack_a.value == 1:
            self.dut.stack_a.value = stack_o  #write stack_a, as read_stack_a does not get updated
        else:
            self.dut.stack_b.value = stack_o         


# sand pile implementation in python
class Sandpile:
    def __init__(self, rows, columns, threshold=4):
        self.rows = rows
        self.columns = columns
        self.threshold = threshold
        self.grid = numpy.zeros((rows, columns), dtype=int)

    def drop_sand(self, x, y):
        # self.topple_cycle() # before add, as there should be a cycle between threshold reached and topple
        self.grid[x][y] += 1

        #Get if sand pile topples next frame
        topple = False
        for x in range(self.rows):
            for y in range(self.columns):
                if self.grid[x][y] >= self.threshold:
                    topple = True


        return topple

    def topple_cycle(self):

        new_grid = self.grid.copy()
        topple = False

        for x in range(self.rows):
            for y in range(self.columns):
                if self.grid[x][y] >= self.threshold:
                    print("Topple in cell", x, y)
                    topple = True
                    new_grid[x][y] -= self.threshold

                    # Nachbarn
                    neighbors = [(x - 1, y),(x + 1, y),(x, y - 1),(x, y + 1)]
                    for nx, ny in neighbors:
                        if 0 <= nx < self.rows and 0 <= ny < self.columns:
                            new_grid[nx][ny] += 1                                

        self.grid = new_grid
        return topple
    
    def check_topple(self):
        topple = False
        for x in range(self.rows):
            for y in range(self.columns):
                if self.grid[x][y] >= self.threshold:
                    topple = True
        return topple

    def fill_stack(self, value):
        for x in range(self.rows):
            for y in range(self.columns):
                self.grid[x][y] = value

@cocotb.test()
async def test_topple(dut):
    """Test: Check dropping and topple functionality"""
    resolution = 64
    tester = MacroArrayTester(dut)
    tester.resolution.value = resolution
    rows = resolution
    cols = resolution
    print("Grid size:", rows, "x", cols)
    simulator = Sandpile(rows, cols)    

    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    await tester.reset()
    await tester.check_adressing(simulator.grid.tolist(), simulator.check_topple())

    # first drop
    x = 16
    y = 16
    print("Drop at", x, y)
    await tester.drop_sand(x,y)
    topple = simulator.drop_sand(x,y)
    await tester.check_adressing(simulator.grid.tolist(), simulator.check_topple())

    # topple on cell
    for i in range(3):
        print("Drop at", x, y)
        await tester.drop_sand(x,y)
        topple = simulator.drop_sand(x,y)
    await tester.check_adressing(simulator.grid.tolist(), simulator.check_topple())

    if(topple):
        topple = simulator.topple_cycle()
        await tester.check_next_topple(topple)
    await tester.check_adressing(simulator.grid.tolist(), simulator.check_topple())

    # topple on cell
    for x in range(-1, resolution, int(resolution/4)):
        for y in range(-1, resolution, int(resolution/4)):
            if x < 0:
                x = 0
            if y < 0:
                y = 0

            for i in range(4):
                print("Drop at", x, y)
                await tester.drop_sand(x,y)
                topple = simulator.drop_sand(x,y)

            if(topple):
                topple = simulator.topple_cycle()
                await tester.check_next_topple(topple)
                topple = simulator.check_topple()

            await tester.check_adressing(simulator.grid.tolist(), topple)

    await tester.reset()
    await tester.check_adressing(numpy.zeros((rows, cols), dtype=int).tolist(), False)

    dut._log.info("✓ Topple test passed")

@cocotb.test()
async def test_random(dut):
    """Test: Check random dropping and topple functionality"""
    resolution = 48
    tester = MacroArrayTester(dut)
    tester.resolution.value = resolution
    rows = resolution
    cols = resolution
    print("Grid size:", rows, "x", cols)
    simulator = Sandpile(rows, cols)    

    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    await tester.reset()
    await tester.check_adressing(simulator.grid.tolist(), simulator.check_topple())

    # first drop
    x = 2
    y = 2
    print("Drop at", x, y)
    await tester.drop_sand(x,y)
    topple = simulator.drop_sand(x,y)
    await tester.check_adressing(simulator.grid.tolist(), simulator.check_topple())

    # topple on cell
    for i in range(3):
        print("Drop at", x, y)
        await tester.drop_sand(x,y)
        topple = simulator.drop_sand(x,y)
    await tester.check_adressing(simulator.grid.tolist(), simulator.check_topple())

    if(topple):
        topple = simulator.topple_cycle()
        await tester.check_next_topple(topple)
    await tester.check_adressing(simulator.grid.tolist(), simulator.check_topple())

    for i in range(1000):
        x = random.randint(0,rows-1)
        y = random.randint(0,cols-1)

        print("Drop at", x, y)
        await tester.drop_sand(x,y)
        topple = simulator.drop_sand(x,y)

        if (i%50) == 0:
            await tester.check_adressing(simulator.grid.tolist(), simulator.check_topple())
        
        while(topple):
            topple = simulator.topple_cycle()
            await tester.check_next_topple(topple)
            topple = simulator.check_topple()
            if i%20 == 0:
                await tester.check_adressing(simulator.grid.tolist(), simulator.check_topple())

    await tester.check_adressing(simulator.grid.tolist(), topple)

    await tester.reset()
    await tester.check_adressing(numpy.zeros((rows, cols), dtype=int).tolist(), False)

    dut._log.info("✓ Full test passed")

def test_sand_cell_runner():
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent.parent

    sources = [ proj_path / "src" / "sand_cell_forMacro.sv",
                proj_path / "src" / "sand_array_forMacro.sv",
                proj_path / "src" / "macro_sand_array.sv",
                proj_path / "src" / "sand_grid_RAM.sv",
                proj_path / "src" / "ram_FPGA_2P.sv",
                proj_path / "src" / "ram_collapse.sv",
                proj_path.parent.parent.parent.parent.parent / "pdk/ihp-sg13cmos5l/libs.ref/sg13cmos5l_sram/verilog/RM_IHPSG13_2P_256x16_c2_bm_bist.v",
                proj_path.parent.parent.parent.parent.parent / "pdk/ihp-sg13cmos5l/libs.ref/sg13cmos5l_sram/verilog/RM_IHPSG13_2P_256x32_c2_bm_bist.v",
                proj_path.parent.parent.parent.parent.parent / "pdk/ihp-sg13cmos5l/libs.ref/sg13cmos5l_sram/verilog/RM_IHPSG13_2P_core_behavioral_bm_bist_ideal.v",]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="macro_sand_array",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
        build_args=["-DASIC"],      # define ASIC keyword to use ASIC version of RAM
    )

    runner.test(hdl_toplevel="macro_sand_array", test_module="test_macro_sand_array", waves=True)

if __name__ == "__main__":
    test_sand_cell_runner()