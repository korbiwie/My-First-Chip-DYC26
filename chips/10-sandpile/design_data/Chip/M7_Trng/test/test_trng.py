import os
import random
import math
import matplotlib.pyplot as plt
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb_tools.runner import get_runner

os.environ['COCOTB_ANSI_OUTPUT'] = '1'

class TrngTester:
    def __init__(self, dut):
        self.dut = dut
        self.state = 0x1234567 

    async def reset(self):
        self.dut.rst_n.value = 0
        self.dut.sensordata.value = 0
        self.state = 0x1234567 
        await Timer(20, units="ns")
        self.dut.rst_n.value = 1

    def keccak_round(self, s):
        theta = 0
        for i in range(25):
            bit_i  = (s >> i) & 1
            bit_5  = (s >> ((i + 5) % 25)) & 1
            bit_20 = (s >> ((i + 20) % 25)) & 1
            
            res_theta = bit_i ^ bit_5 ^ bit_20
            theta |= (res_theta << i)

        pi = 0
        for i in range(25):
            bit_theta = (theta >> i) & 1
            new_pos = (i * 7) % 25
            pi |= (bit_theta << new_pos)

        chi = 0
        for i in range(25):
            curr_bit  = (pi >> i) & 1
            next_bit  = (pi >> ((i + 1) % 25)) & 1
            next2_bit = (pi >> ((i + 2) % 25)) & 1
            
            res_chi = curr_bit ^ ((next_bit ^ 1) & next2_bit)
            chi |= (res_chi << i)

        return chi & 0x1FFFFFF  
    
    def update_model(self, sensor_in):
        mixed_state = self.state ^ ((0 << 15) | (sensor_in & 0x3FF))
        mixed_state &= 0x1FFFFFF  # 25 bits
        self.state = self.keccak_round(mixed_state)
        # scale to MAX
        max = int(self.dut.MAX.value)
        return (self.state * max) >> 25
    
@cocotb.test()
async def test_logic_verification(dut):
    tester = TrngTester(dut)
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await tester.reset()
    
    expected = [0,0,0]
    
    for i in range(100):
        sensor_in = random.getrandbits(10) 
        dut.sensordata.value = sensor_in
        expected[2] = expected[1] 
        expected[1] = expected[0] 
        expected[0] = tester.update_model(sensor_in)
        await RisingEdge(dut.clk)
        
        # TRNG needs two cycles to calculate random value from input state (offset of 2 rising edges)
        if i > 2:
            actual = int(dut.random_out.value)
            dut._log.info(f"Schritt {i:02d}: In={sensor_in:03x} | Model={expected[2]:03x} | HW={actual:03x}")
        
            assert actual == expected[2], f"Abweichung in Schritt {i}! Hardware: {actual:03x}, Model: {expected[2]:03x}"
        
    dut._log.info("✓ Golden Model Test erfolgreich!")

@cocotb.test()
async def test_distribution(dut):
    tester = TrngTester(dut)
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await tester.reset()
    scenarios = [
        ("Vollrauschen", lambda: random.getrandbits(10)),
        ("viele 1er", lambda: 0x3FF if random.random() > 0.3 else 0x000),
        ("nur 0er", lambda: 0x000)
    ]
    
    for name, input_gen in scenarios:
        dut._log.info(f"Teste Szenario: {name}")
        await tester.reset()
        samples = 100000
        max_value = int(tester.dut.MAX.value)
        bins = [0] * max_value
        expected_per_bin = samples / max_value
        
        for i in range(samples):
            sensor_in = input_gen()
            dut.sensordata.value = sensor_in
            
            await RisingEdge(dut.clk)
            
            output_val = int(dut.random_out.value)
            bins[output_val] += 1
            
            if i % 25000 == 0 and i > 0:
                dut._log.info(f"  Fortschritt: {i}/{samples} Samples")
            
        unique_values = sum(1 for b in bins if b > 0)
        total_sum = sum(unique_values* count for unique_values, count in enumerate(bins))
        mean = total_sum / samples
        variance = sum(count * ((val - mean) ** 2) for val, count in enumerate(bins)) / samples
        std_dev = math.sqrt(variance)
        
        expected_variance = (max_value*max_value-1)/12
        expected_std_dev = math.sqrt(expected_variance)
        
        chi_sq = sum(((count - expected_per_bin) ** 2) / expected_per_bin for count in bins)
        plot_distribution(bins, name, mean, std_dev, chi_sq, max_value)
        
        assert unique_values == max_value, f"Lücken in der Verteilung bei {name}"
        assert max_value/2*0.95 < mean < max_value/2*1.05, f"Unerwarteter Mittelwert bei {name}: {mean:.2f}"
        assert expected_std_dev*0.95 < std_dev < expected_std_dev*1.05, f"Standardabweichung untypisch: {std_dev:.2f} bei {name}"
        assert chi_sq < (max_value*1.5), f"Gleichverteilung nicht ausreichend! Chi-Sq: {chi_sq:.2f} bei {name}"

def plot_distribution(bins, name, mean, std_dev, chi_sq, max_value):
    plt.figure(figsize=(12, 6))

    values = list(range(max_value))
    plt.bar(values, bins, color='steelblue', alpha=0.7, width=1.0, label='Häufigkeit')
    
    samples = sum(bins)
    ideal = samples / max_value
    plt.axhline(y=ideal, color='red', linestyle='--', linewidth=1.5, label=f'Ideal ({ideal:.1f})')
    
    plt.title(f"TRNG Verteilung - Szenario: {name}")
    plt.xlabel("Ausgabewert (0-1023)")
    plt.ylabel("Anzahl der Treffer")
    
    stats_text = (f"Samples: {samples}\n"
                  f"Mean: {mean:.2f}\n"
                  f"Std Dev: {std_dev:.2f}\n"
                  f"Chi-Sq: {chi_sq:.2f}")
    
    plt.text(0.95, 0.95, stats_text, transform=plt.gca().transAxes, 
             fontsize=10, verticalalignment='top', horizontalalignment='right',
             bbox=dict(boxstyle='round', facecolor='white', alpha=0.5))
    
    plt.legend(loc='upper left')
    plt.grid(axis='y', linestyle=':', alpha=0.6)
    
    filename = f"trng_plot_{name.replace(' ', '_').lower()}.png"
    plt.savefig(filename)
    plt.close() 
    print(f"Grafik gespeichert unter: {filename}") 

def test_trng_runner():
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sources = [proj_path / "src" / "trng.sv"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="trng",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )
    runner.test(hdl_toplevel="trng", test_module="test_trng", waves=True)

if __name__ == "__main__":
    test_trng_runner()