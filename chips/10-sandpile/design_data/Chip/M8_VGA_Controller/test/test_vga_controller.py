import os
import random
from unittest import runner
import cocotb
import cocotb.utils
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, FallingEdge
from cocotb_tools.runner import get_runner
from PIL import Image
from pathlib import Path


@cocotb.test()
async def test_macro_array_vga_timing(dut):
    """Testet das Zusammenspiel zwischen Macro-Array-Logik und VGA-Renderer."""
    
    # Takt starten (25 MHz)
    cocotb.start_soon(Clock(dut.clk, 40, unit="ns").start())
    
    # Reset
    dut.rst_n.value = 0
    dut.new_frame_i.value = 0
    await Timer(100, unit="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    # 1. Speicher im Macro-Array füllen
    # Da stack_a intern im array_unit liegt, greifen wir tief hinein
    size = 32
    for i in range(size * size):
        # Wir erzeugen ein Testmuster: Wert = (Index % 4) + 1
        val = (i % 4) + 1
        # Wir schreiben direkt in den Speicher des Arrays
        dut.array_unit.stack_a[i].value = val

    # 2. Array-Berechnung triggern
    # Das Macro-Array braucht diesen Puls, um die Daten intern 
    # für den VGA-Zugriff bereitzustellen
    dut._log.info("Triggere Macro-Array State Machine...")
    dut.new_frame_i.value = 1
    await RisingEdge(dut.clk)
    dut.new_frame_i.value = 0

    # Warten, bis das Array bereit ist (State Complete)
    # Das dauert bei 32x32 ein paar Takte
    while int(dut.array_unit.state.value) != 4: # 4 entspricht 'Complete'
        await RisingEdge(dut.clk)

    # 3. VGA Frame Capture
    dut._log.info("Starte Bild-Capture...")
    await FallingEdge(dut.vga_vs)
    await RisingEdge(dut.vga_vs)

    img = Image.new('RGB', (640, 480), "black")
    pixels = img.load()
    c_x, c_y = 0, 0

    while c_y < 480:
        await RisingEdge(dut.clk)
        # Wir nutzen den Video-On Ausgang des internen VGA-Controllers
        if dut.uut.vga_unit.video_on.value:
            # Wir nehmen die Farbe direkt vom VGA-Port
            r = int(dut.vga_r.value) * 17
            g = int(dut.vga_g.value) * 17
            b = int(dut.vga_b.value) * 17
            pixels[c_x, c_y] = (r, g, b)
            
            # Timing-Check am allerersten Pixel des Grids
            if c_x == 0 and c_y == 0:
                # Da grid_data (stack_data) vom Array kommt, 
                # schauen wir, ob hier der Wert 1 (von Index 0) ankommt
                dut._log.info(f"Erstes Pixel Farbe: R={r}, G={g}, B={b}")

            c_x += 1
            if c_x == 480: # Wir scannen nur den Grid-Bereich
                c_x = 0
                c_y += 1

    img.save("macro_array_check.png")
    dut._log.info("✓ Bild gespeichert: macro_array_check.png")

@cocotb.test()
async def test_timing_handshake(dut):
    """Prüft den exakten Takt-Versatz zwischen Adresse und Datenankunft."""
    cocotb.start_soon(Clock(dut.clk, 40, unit="ns").start())
    dut.rst_n.value = 0
    await Timer(100, unit="ns")
    dut.rst_n.value = 1
    
    # Grid-Größe festlegen
    dut.grid_size.value = 32
    
    # Wir schreiben Test-Werte in die ersten Zellen: 
    # Adresse 0 -> Farbe 1, Adresse 1 -> Farbe 2, etc.
    for i in range(10):
        dut.stack_a[i].value = (i + 1) %8 

    # Wir warten bis wir kurz vor dem Grid-Start (Pixel 80) sind
    # Wir beobachten pixel_x vom Controller
    while int(dut.uut.vga_unit.pixel_x.value) < 78:
        await RisingEdge(dut.clk)

    dut._log.info("--- Start Timing Analyse (Pixel 78 bis 85) ---")
    
    for _ in range(10):
        await RisingEdge(dut.clk)
        px = int(dut.uut.vga_unit.pixel_x.value)
        addr_x = int(dut.uut.grid_addr_x.value)
        # Wir greifen auf das Signal zu, das vom RAM kommt
        data = int(dut.uut.grid_data.value) 
        # Das finale VGA-Signal (Rot-Kanal als Stellvertreter)
        vga_r = int(dut.uut.vga_r.value)
        # Das verzögerte video_on vom Controller
        vid_on = int(dut.uut.video_on.value)

        dut._log.info(f"Takt | Pixel_X: {px:3} | Addr: {addr_x:2} | RAM_Data: {data} | VGA_R: {vga_r:2} | Video_On: {vid_on}")

    dut._log.info("--- Ende Analyse ---")
    
@cocotb.test()
async def test_vga_timing_and_geometry(dut):
    """Prüft, ob die Pixel zeitlich exakt zum HSYNC-Puls passen (Monitor-Perspektive)."""
    cocotb.start_soon(Clock(dut.clk, 40, unit="ns").start())
    dut.rst_n.value = 0
    await Timer(100, unit="ns")
    dut.rst_n.value = 1

    size = 4 # Wir testen 4x4 für die Quadrat-Prüfung
    dut.grid_size.value = size
    
    # Grid füllen
    for i in range(size*size):
        dut.stack_a[i].value = (i % 4) + 1

    # Warte auf einen neuen Frame
    await FallingEdge(dut.vga_vs)
    await RisingEdge(dut.vga_vs)

    img = Image.new('RGB', (800, 525), "gray") # Wir zeichnen den GANZEN VGA-Bereich incl. Rand
    pixels = img.load()

    dut._log.info("Starte präzise Zeitmessung...")

    # Wir scannen eine Zeile in der Mitte des Bildes (Zeile 240)
    # um zu sehen, ob die Quadrate 120 Pixel breit sind
    for y in range(525):
        # Wir warten auf den Start des HSYNC Pulses (Zeilenanfang)
        await FallingEdge(dut.vga_hs)
        
        # Jetzt zählen wir Takte ab exakt diesem Moment
        for x in range(800):
            await RisingEdge(dut.clk)
            
            # Farbe lesen
            r = int(dut.vga_r.value) * 17
            g = int(dut.vga_g.value) * 17
            b = int(dut.vga_b.value) * 17
            
            # Wir speichern JEDEN Takt in das Bild, um den Versatz zu sehen
            pixels[x, y] = (r, g, b)

            # --- DER GEOMETRIE CHECK ---
            # Standard: HSYNC (96) + Back Porch (48) + Offset (80) = 224 Takte
            # Wenn erst bei Takt 227 Farbe kommt, hast du 3 Pixel Versatz!
            if x == 224 and y == 240:
                if r == 0 and g == 0:
                    dut._log.error(f"TIMING FEHLER: Bei Takt 224 (Pixel 0 des Grids) ist noch keine Farbe da!")
                else:
                    dut._log.info("✓ Timing: Erstes Pixel erscheint exakt zum richtigen Zeitpunkt.")

    img.save("vga_full_frame_timing_check.png")

@cocotb.test()
async def test_grid_full_pattern_scaling(dut):
    """Test 1: Füllt das Grid mit einem Muster, um Skalierung und Quadrate zu prüfen."""
    cocotb.start_soon(Clock(dut.clk, 40, unit="ns").start())
    dut.rst_n.value = 0
    await Timer(100, unit="ns")
    dut.rst_n.value = 1

    # Wir testen verschiedene Größen
    for size in [3, 4, 7, 13, 32]:
        dut.grid_size.value = size
        dut._log.info(f"Setze Grid-Muster für Größe: {size}x{size}")
        
        # Grid mit Farbmuster füllen: Jede Spalte/Zeile wechselt die Farbe
        for i in range(32*32):
            gx, gy = i % 32, i // 32
            if gx < size and gy < size:
                # Muster: Erzeugt ein farbiges Gitter/Schachbrett
                # Farbe 1, 2, 3 oder 4
                rand_val = random.randint(0, 4)
                #color_val = ((gx % 2) + (gy % 2) * 2) % 4 + 1
                dut.stack_a[i].value = rand_val
            else:
                dut.stack_a[i].value = 0

        await FallingEdge(dut.vga_vs)
        await RisingEdge(dut.vga_vs)

        # Bild erfassen
        img = Image.new('RGB', (640, 480), "black")
        pixels = img.load()
        c_x, c_y = 0, 0
        
        while c_y < 480:
            await RisingEdge(dut.clk)
            if dut.uut.video_on.value:
                # Farbe aus den VGA-Signalen lesen
                r = int(dut.vga_r.value) * 17
                g = int(dut.vga_g.value) * 17
                b = int(dut.vga_b.value) * 17
                pixels[c_x, c_y] = (r, g, b)
                
                c_x += 1
                if c_x == 640:
                    c_x = 0
                    c_y += 1
        
        filename = f"pattern_check_{size}x{size}_random.png"
        img.save(filename)
        dut._log.info(f"✓ Muster-Bild gespeichert: {filename}")

@cocotb.test()
async def test_vga_frame_capture(dut):
    """Simulation des grids und Visualisierung der VGA-Ausgabe als PNG-Bild."""
    
    cocotb.start_soon(Clock(dut.clk, 40, unit="ns").start())
    dut.rst_n.value = 0
    await Timer(100, unit="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    grid_size = 32 
    for i in range(grid_size * grid_size):
        try:
            val = 4 if (i % 33 == 0) else 0
            dut.stack_a[i].value = val
        except Exception:
            pass

    img = Image.new('RGB', (640, 480), "black")
    pixels = img.load()
    
    await RisingEdge(dut.vga_vs)
    
    curr_x = 0
    curr_y = 0
    captured_pixels = 0

    while captured_pixels < (640 * 480):
        await RisingEdge(dut.clk)
        
        if dut.uut.vga_unit.video_on.value:
            r = int(dut.vga_r.value) * 17
            g = int(dut.vga_g.value) * 17
            b = int(dut.vga_b.value) * 17
            
            if curr_x < 640 and curr_y < 480:
                pixels[curr_x, curr_y] = (r, g, b)
            
            captured_pixels += 1
            curr_x += 1
            
            if curr_x == 640:
                curr_x = 0
                curr_y += 1

    img.save("vga_output.png")
    dut._log.info("✓ Bild ohne Versatz gespeichert!")

@cocotb.test()
async def test_vga_frame_capture_60hz(dut):
    """Simulation mit Frequenzmessung und Frame-Capture."""
    
    cocotb.start_soon(Clock(dut.clk, 40, unit="ns").start())
    
    dut.rst_n.value = 0
    await Timer(100, unit="ns")
    dut.rst_n.value = 1
    
    await FallingEdge(dut.vga_vs)
    
    last_frame_time = cocotb.utils.get_sim_time(unit='ns')
    num_frames = 3

    for frame in range(num_frames):
        await RisingEdge(dut.vga_vs)
        
        current_time = cocotb.utils.get_sim_time(unit='ns')
        if frame > 0:
            frame_duration_ns = current_time - last_frame_time
            fps = 1 / (frame_duration_ns * 1e-9)
            dut._log.info(f"Frame {frame}: Dauer = {frame_duration_ns} ns ({fps:.2f} Hz)")
        last_frame_time = current_time

        img = Image.new('RGB', (640, 480), "black")
        pixels = img.load()
        c_x, c_y = 0, 0
        captured_pixels = 0
        
        while captured_pixels < (640 * 480):
            await RisingEdge(dut.clk)
            
            if dut.uut.vga_unit.video_on.value:
                r = int(dut.vga_r.value) * 17
                g = int(dut.vga_g.value) * 17
                b = int(dut.vga_b.value) * 17
                
                if c_x < 640 and c_y < 480:
                    pixels[c_x, c_y] = (r, g, b)
                
                captured_pixels += 1
                c_x += 1
                if c_x == 640:
                    c_x = 0
                    c_y += 1
            
            if dut.vga_vs.value == 0 and captured_pixels > 0 and c_x == 0:
                break

        img.save(f"frame_60hz_{frame}.png")
        dut._log.info(f"✓ Frame {frame} gespeichert.")

def test_vga_runner():
    sim = os.getenv("SIM", "verilator")
    proj_path = Path(__file__).resolve().parent.parent
    sources = [
        proj_path / "src" / "top_vga_sandpile.sv",
        proj_path / "src" / "vga_controller.sv",
        proj_path / "src" / "horizontal_counter.sv",
        proj_path / "src" / "vertical_counter.sv",
        proj_path / "src" / "sandpile_renderer.sv",
        proj_path / "src" / "test_top.sv"
    ]

    runner = get_runner(sim)
    
    runner.build(
        sources=sources,
        hdl_toplevel="test_top",
        always=True,
        # --timing ist wichtig, falls du #delays in deinem SV-Code hast
        # --trace-fst aktiviert das platzsparende FST-Format für Wellenformen
        build_args=[
            "--trace-fst", 
            "--trace-structs", 
            "-Wno-fatal",
            "--timing" 
        ],
        waves=True,
        timescale=("1ns", "1ps")
    )
    runner.test(
        hdl_toplevel="test_top",
        test_module="test_vga_controller", # Deine Python-Testdatei
        # Hier kannst du zwischen den beiden Tests wechseln:
        # testcase="test_grid_full_pattern_scaling", 
        testcase="test_vga_timing_and_geometry",
        waves=True 
    )

if __name__ == "__main__":
    test_vga_runner()