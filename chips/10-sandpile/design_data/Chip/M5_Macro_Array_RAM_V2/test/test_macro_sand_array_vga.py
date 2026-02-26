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

from PIL import Image
from pathlib import Path

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
        
        self.vga_r = dut.vga_r
        self.vga_g = dut.vga_g
        self.vga_b = dut.vga_b
        self.vga_hs = dut.vga_hs
        self.vga_vs = dut.vga_vs
        
        self.pixel_data = dut.pixel_data
        self.new_data = dut.new_data

        # reference parameters
        self.ROWS = int(self.dut.MAX_SIZE.value)
        self.COLS = int(self.dut.MAX_SIZE.value)
        self.ROWS_SMALL = int(self.dut.COLS_SMALL.value)
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
        for i in range(int(self.dut.array_unit.TILES_TOTAL.value)*2+10):
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

    async def check_next_topple(self, topple):
        # update frame without dropping
        self.drop_i.value = 0
        await RisingEdge(self.clk) # next drop pos gets only updated on rising clock edge
        await FallingEdge(self.clk) # needed to be sure that new_frame_i is 1 during only one rising edge
        self.new_frame_i.value = 1
        await RisingEdge(self.new_data) # stack gets only updated on rising clock edge
        self.new_frame_i.value = 0
        await FallingEdge(self.clk)
        assert self.new_data.value == True

    async def get_grid_image(self, filenumber):
        # only read stack, no update
        self.drop_i.value = 0
        self.new_frame_i.value = 0
        await RisingEdge(self.clk)
        print("Get image from grid")

        img = Image.new('RGB', (720, 640), "black") 
        pixels = img.load()

        c_x = 0
        c_y = 0

        hs_old = self.vga_hs.value
        vs_old = self.vga_vs.value

        # Warte auf einen neuen Frame
        await FallingEdge(self.vga_vs)
        await RisingEdge(self.vga_vs)

        while c_y < 540:
            await RisingEdge(self.clk)
            
            if self.vga_hs.value and self.vga_vs.value:
                # if 0 <= c_x < 640 and 0 <= c_y < 480:
                r = int(self.vga_r.value) * 17
                g = int(self.vga_g.value) * 17
                b = int(self.vga_b.value) * 17
                pixels[c_x, c_y] = (r, g, b)
                
                c_x += 1
            
            if self.vga_hs.value and not hs_old:
                c_x = 0
                c_y += 1

            if not self.vga_vs.value and vs_old:
                break         

            hs_old = self.vga_hs.value
            vs_old = self.vga_vs.value    

        img.save(f"vga_output{filenumber}.png")


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

    def fill_stack(self, value):
        for x in range(self.rows):
            for y in range(self.columns):
                self.grid[x][y] = value
    

@cocotb.test()
async def test_random(dut):
    """Test: Check random dropping and topple functionality"""
    resolution = 32
    tester = MacroArrayTester(dut)
    tester.resolution.value = resolution
    rows = resolution
    cols = resolution
    print("Grid size:", rows, "x", cols)
    simulator = Sandpile(rows, cols)    

    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    await tester.reset()

    # first drop
    x = 2
    y = 2
    print("Drop at", x, y)
    await tester.drop_sand(x,y)
    topple = simulator.drop_sand(x,y)

    for i in range(1000):
        x = random.randint(0,rows-1)
        y = random.randint(0,cols-1)

        await tester.drop_sand(x,y)
        topple = simulator.drop_sand(x,y)

        if (i%100) == 99:
            print((i+1)/10, "%")

        if i%1000 == 999:
            await tester.get_grid_image(f"complete_{i}")
        
        while(topple):
            topple = simulator.topple_cycle()
            await tester.check_next_topple(topple)

    dut._log.info("✓ Full test passed")

    

def test_sand_cell_runner():
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent.parent

    sources = [ proj_path / "src" / "sand_cell_forMacro.sv",
                proj_path / "src" / "sand_array_forMacro.sv",
                proj_path / "src" / "macro_sand_array.sv",
                proj_path / "src" / "sand_grid_RAM.sv",
                proj_path / "src" / "ram_FPGA_2P.sv",
                proj_path.parent.parent.parent / "pdk/ihp-sg13g2/libs.ref/sg13g2_sram/verilog/RM_IHPSG13_2P_1024x16_c2_bm_bist.v",
                proj_path.parent.parent.parent / "pdk/ihp-sg13g2/libs.ref/sg13g2_sram/verilog/RM_IHPSG13_2P_core_behavioral_bm_bist_ideal.v",
                proj_path / "test" / "test_vga.sv",
                proj_path.parent / "M8_VGA_Controller" / "src" / "top_vga_sandpile.sv",
                proj_path.parent / "M8_VGA_Controller" / "src" / "sandpile_renderer.sv",
                proj_path.parent / "M8_VGA_Controller" / "src" / "vga_controller.sv",
                proj_path.parent / "M8_VGA_Controller" / "src" / "horizontal_counter.sv",
                proj_path.parent / "M8_VGA_Controller" / "src" / "vertical_counter.sv",]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="test_vga",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
        # build_args=["-DASIC"],      # define ASIC keyword to use ASIC version of RAM
    )

    runner.test(hdl_toplevel="test_vga", test_module="test_macro_sand_array_vga", waves=True)

if __name__ == "__main__":
    test_sand_cell_runner()