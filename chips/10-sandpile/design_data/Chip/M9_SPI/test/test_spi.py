"""
Modern cocotb 2.0 testbench for the SPI module.
Tests default configuration: Slave mode, SPI Mode 0 (CPOL=0, CPHA=0), MSB first, 12-bit.
Uses async/await syntax and modern pythonic patterns.
"""

import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from cocotb_tools.runner import get_runner

os.environ['COCOTB_ANSI_OUTPUT'] = '1'
    
async def send_recv_data_from_master(dut,  reg_address: int, reg_data: int):
    word_len = 8
    transmit_data = [reg_address, reg_data]
    out = 0
    for data in transmit_data:
        for bit_pos in range(word_len):
            bit_value = (data >> (word_len - bit_pos - 1)) & 1   
            dut.PICO.value = bit_value
            await Timer(500, unit="ns")
            dut.SCLK.value = 1
            await Timer(500, unit="ns")
            bit = dut.POCI.value
            bit_val = 1 if bit == True else 0            
            out = (out << 1) | bit_val
            dut.SCLK.value = 0
    
    return out

async def control_cs(dut, val: bool):    
    dut.SS.value = 1 if val == True else 0
    await Timer(100, unit="ns")

@cocotb.test()
async def reset(dut):        
    clock = Clock(dut.sys_clock, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    """Reset the SPI module."""
    dut.rst.value = 1
    await RisingEdge(dut.sys_clock)
    
    await RisingEdge(dut.sys_clock)
    assert dut.bit_counter.value == 0
    assert dut.data_word_recv_reg.value == 0
    assert dut.is_package_recv_reg.value == 0

# addr 4 bits, data 12 bits
def built_packages(addr, data):
    if(addr < 0 or data < 0 or addr > 0xF or data > 0xFFF):
        assert False, "Input data negative or too big" 
    
    pack_1 = (addr & 0xF) << 4
    pack_1 = pack_1 | (data >> 8) # pack 1 becomes 8 bits       
    pack_2 = data & 0xFF # get last 8 bits
    
    return [pack_1, pack_2]

async def test_read_write_frames(dut):
    reg_address = 0xA # 1010
    reg_data = 0x24 # 000000100100
    
    # dut._log.info(f"input: reg_address -> {bin(reg_address)} reg_data -> {bin(reg_data)}")
    [byte_1, byte_2] = built_packages(reg_address, reg_data)
    # dut._log.info(f"transmission bytes: reg_address -> {bin(byte_1)} reg_data -> {bin(byte_2)}")
        
    dut.SCLK.value = 0
    dut.PICO.value = 0
    dut.SS.value = 1
    dut.POCI.value = 0
    dut.rst.value = 0
    await Timer(100, unit="ns")
    
    await control_cs(dut, False)    
    rx_data = await send_recv_data_from_master(dut, byte_1, byte_2)
    # dut._log.info(f"data -> {dut.data_word_recv_reg.value}")
    assert dut.spi_address.value == reg_address, f"Checking spi_address if {bin(dut.spi_address.value)} is equal to {bin(reg_address)}"
    assert dut.spi_data.value == reg_data, f"Checking spi_data if {bin(dut.spi_data.value)} is equal to {bin(reg_data)}"  
    assert dut.chip_id.value == rx_data, f"Checking chip_id if {bin(dut.chip_id.value)} is equal to {bin(rx_data)}"
    await control_cs(dut, True)    
    
@cocotb.test()
async def batch_send_write_frames(dut):
    clock = Clock(dut.sys_clock, 10, unit="ns")
    cocotb.start_soon(clock.start())
    for _ in range(10):
        await test_read_write_frames(dut)        
        await Timer(500, unit="ns")
        

def test_spi_runner():
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent.parent

    sources = [
        proj_path / "src" / "spi_module.sv",
        proj_path / "src" / "pos_edge_det.sv",
    ]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="spi_module",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )

    runner.test(hdl_toplevel="spi_module", test_module="test_spi", waves=True)

if __name__ == "__main__":
    test_spi_runner()
    # dut._log.info(f"sent -> {dut.SS.value}")