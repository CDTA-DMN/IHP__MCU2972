# QoSoC — MCU2972 Datasheet

**Version:** v1.0.0 | **Technology:** IHP SG13CMOS | **License:** Apache-2.0

---

## Overview

QoSoC is a 32-bit RISC-V System-on-Chip designed for low-power IoT and embedded control applications. It is built around the PicoRV32 RV32EC core, a single-master Wishbone B4 interconnect, and a comprehensive peripheral set.



![QoSoC Block Diagram](qosoc.png)

---

## Key Specifications

| Parameter | Value |
|-----------|-------|
| Architecture | RISC-V RV32EC (PicoRV32) |
| Process | IHP SG13CMOS |
| Die area | 1732 × 1732 µm |
| Core area | ~979 kµm² (367.2 × 370.44 to 1359.84 × 1357.02 µm) |
| Standard cells (post-P&R) | 38,326 |
| Target clock | 16 MHz (62.5 ns period, timing-closed) |
| RTC clock | 32.768 kHz (external crystal) |
| Supply voltage | 1.2 V core / 1.8 V I/O |
| Total power (typ) | ~5.2 mW @ 16 MHz |
| TRL | 5 — silicon submitted for fabrication |

---

## Features

### Processor
- PicoRV32 RV32EC core — reduced register file (x0–x15), no hardware MUL/DIV
- 32-input interrupt controller with mask and acknowledge logic
- Wishbone B4 Classic single-master fabric

### Memory
- 4 KB Boot ROM (mask-programmed bootloader)
- 2 KB Internal SRAM — IHP `RM_IHPSG13_1P_512x32_c2_bm_bist` macro
- External QSPI Flash — XIP (execute-in-place) up to 8 MB

### Peripherals
- **GPIO** — 8-bit bidirectional, edge/level interrupt, individual output-enable
- **UART** — ZipCPU wbuart32, 16-byte TX/RX FIFOs, configurable baud
- **I2C** — OpenCores master, 100/400 kHz, interrupt on complete/NACK
- **PTC** — 32-bit programmable timer/counter, PWM output, capture input
- **Dual RTC** — two independent calendar/alarm instances, 32.768 kHz domain
- **Watchdog** — 32-bit auto-reload, interrupt before reset

### Power Management
- 5-state power FSM: Active → Sleep → Deep-Sleep → Shutdown → Waking
- Fine-grained per-peripheral clock gating (glitch-free)
- CPU sleep/wake handshake with the PMU
- 8 configurable wake sources (GPIO, UART, I2C, PTC, RTC0, RTC1, WDT, QSPI)

### Debug & DFT
- Post-silicon debug subsystem — reset-time entry via `GPIO[7]` strap
- Shared UART pad reuse for ASCII command-based debug protocol
- Wishbone bus-master takeover (CPU held in reset during debug)
- SRAM MBIST — March-style algorithm via IHP macro BIST pins
- 32-entry event FIFO for post-mortem inspection

---

## Pinout

The pad ring is defined in `qosoc_chip_top.sv`. Pads are placed on all four sides of the die.

### Signal Pads

| Pad Instance | Signal | Direction | Side | Description |
|---|---|---|---|---|
| `u_pad_clk` | `clk_PAD` | Input | South | Main system clock (16 MHz nominal) |
| `u_pad_rst_n` | `rst_n_PAD` | Input | South | Active-low asynchronous reset |
| `u_pad_uart_rx` | `uart_rx_PAD` | Input | South | UART receive |
| `u_pad_uart_tx` | `uart_tx_PAD` | Output | South | UART transmit |
| `u_pad_i2c_scl` | `i2c_scl_PAD` | Bidir | South | I2C clock (open-drain) |
| `u_pad_i2c_sda` | `i2c_sda_PAD` | Bidir | South | I2C data (open-drain) |
| `u_pad_pwm0` | `pwm0_PAD` | Bidir | South | PTC PWM output / capture input |
| `u_pad_gpio_0`–`3` | `gpio_PAD[3:0]` | Bidir | East | General purpose I/O |
| `u_pad_gpio_4` | `gpio_PAD[4]` | Bidir | East | GPIO / **BOOT_MODE strap** (sampled at reset) |
| `u_pad_gpio_5` | `gpio_PAD[5]` | Bidir | East | General purpose I/O |
| `u_pad_gpio_6` | `gpio_PAD[6]` | Bidir | North | General purpose I/O |
| `u_pad_gpio_7` | `gpio_PAD[7]` | Bidir | North | GPIO / **DBG_MODE strap** (sampled at reset) |
| `u_pad_trap` | `trap_PAD` | Output | North | CPU trap indicator |
| `u_pad_clk_rtc` | `clk_rtc_PAD` | Input | North | RTC reference clock (32.768 kHz) |
| `u_pad_qspi_sck` | `qspi_sck_PAD` | Output | West | QSPI flash clock |
| `u_pad_qspi_cs_n` | `qspi_cs_n_PAD` | Output | West | QSPI chip select (active-low) |
| `qspi_dat_pads[3:0]` | `qspi_dat_PAD[3:0]` | Bidir | West | QSPI data (quad) |

### Strap Pins

| Strap | Pad | Sampled | Effect |
|---|---|---|---|
| `BOOT_MODE` | `gpio_PAD[4]` | First rising clock after reset | `0` = XIP boot from QSPI Flash; `1` = UART download mode |
| `DBG_MODE` | `gpio_PAD[7]` | First rising clock after reset | `1` = enter debug session (CPU held in reset, UART used by debug subsystem) |

### Power Pads

| Count | Cell | Side | Net |
|---|---|---|---|
| 2 | `sg13g2_IOPadIOVdd` | North | IOVDD (1.8 V I/O supply) |
| 2 | `sg13g2_IOPadIOVss` | North/East | IOVSS |
| 3 | `sg13g2_IOPadVdd` | South/West | VDD (1.2 V core supply) |
| 2 | `sg13g2_IOPadVss` | North/West | VSS |

---

## Memory Map

| Base Address | Size | Region |
|---|---|---|
| `0x0000_0000` | 4 KB | Boot ROM |
| `0x1000_0000` | 2 KB | Internal SRAM |
| `0x2000_0000` | 8 MB | QSPI Flash (XIP) |
| `0x8000_0000` | 1 MB | Peripheral register space |

Detailed register-level descriptions are provided in `doc/Specification.md`.

---

## Physical

| Parameter | Value |
|---|---|
| Top cell | `qosoc_chip_top` (pad ring) / `MCU2972` (tapeout cell) |
| GDS | `release/v.1.0.0/gds/MCU2972.gds` |
| Die dimensions | 1732 × 1732 µm |
| Core area | ~979 kµm² |
| Standard cells | 38,326 (post-P&R) |
| PDK | IHP SG13G2 (SG13CMOS) |
| Setup violations | None (all corners) |
| Hold violations | None (all corners) |
| LVS | Passed |
| Antenna | Passed |
| IR drop (VDD worst) | 1.7 mV (0.14%) |

---

## Tooling & Infrastructure

| Toolset | Version |
|---|---|
| **GCC Compiler** | riscv-none-elf-gcc 14.2.0-3  Firmware building (xPack distribution) |
| **Physical Design** | LibreLane 3.0.0 |
| **Linting** | Verilator 5.044 | 
| **Verilog Lint** | Verible v0.2.1 | 
| **Simulation** | Icarus Verilog 13.0 (devel) |
| **Verification FW** | cocotb 1.9.2 |
| **PDK** | IHP SG13G2 (0418301...) | 

---

## License

This design is released under the [Apache 2.0 License](../LICENSE).
