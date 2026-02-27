# 14-ir-decoder

**Author:** Alexander Sauerwein, Maik Unglert

## Description

A fully hardware-based Infrared Remote Decoder, Recorder, and Replay system implemented in SystemVerilog and taped out on IHP SG13G2 (130 nm).

The chip receives raw IR signals from a standard IR receiver module, decodes them in real time according to the **NEC**, **Samsung36**, and **N8X2** (custom Christmas-lights) protocols, and outputs decoded frames as human-readable text over **UART** (9600 baud, 8N1). Up to **40 decoded IR codes** can be stored in on-chip BRAM slots and replayed at any time via a 38 kHz modulated IR transmitter output. Recording and replay can be triggered either by physical buttons or wirelessly through an **ESP32-C3 WiFi web-UI** connected over a software SPI interface.

**Key facts:**
- Technology: IHP SG13G2 (130 nm)
- Die size: 1340 × 1340 µm (1.34 × 1.34 mm)
- Core area: ~655 × 651 µm
- Core clock: 10 MHz (divided internally from input clock)
- UART output: 9600 baud, 8N1

## Pin List

| Pin | Direction | Description |
| --- | --- | --- |
| `io_clk_pad` | Input | Main clock input (100 MHz on FPGA, divided to 10 MHz core clock) |
| `io_rst_n_pad` | Input | Active-low asynchronous reset |
| `io_ir_in_pad` | Input | Raw IR signal from IR receiver module (active low, demodulated) |
| `io_spi_clk_pad` | Input | Software-SPI clock from ESP32-C3 WiFi module |
| `io_spi_data_pad` | Input | Software-SPI data from ESP32-C3 WiFi module (MSB first, 8-bit frames) |
| `io_ir_tx_npn_drive_pad` | Output | IR LED drive output — 38 kHz modulated NEC/Samsung transmit signal (NPN transistor drive) |
| `io_uart_tx_pad` | Output | UART TX — decoded frame as ASCII text (`A:xx C:yy` / `P:SAM36 A:aaaa C:cc`) |
| `io_receiving_pad` | Output | Status: IR reception active (decoder is currently receiving a frame) |
| `io_valid_pad` | Output | Status: pulse when a frame has been successfully decoded and validated |
| `io_recording_pad` | Output | Status: recording active (waiting for a valid frame to store into BRAM) |

## Architecture

```
ir_in ──► EdgeDetector ──► PulseTimer ──► NECDecoder ─┬──► OutputFormatter ──► UART_TX ──► uart_tx
                                                       └──► IRRecorder ──► BRAM (40 slots)
                                                                               │
replay_req / spi ──────────────────────────────► IRReplayFSM ◄─────────────────
                                                       │
                                               NECEncoder ──► IR_TX (38 kHz) ──► ir_tx_npn_drive
```

## Design Data

The full RTL source, testbenches, and build scripts are provided as a Git submodule in [`design_data/`](design_data/).

```bash
git submodule update --init chips/14-ir-decoder/design_data
```

All tests can be run with:

```bash
cd chips/14-ir-decoder/design_data
pytest
```
