# QoSoC — System Specification

**IP:** MCU2972 | **Version:** v1.0.0 | **Process:** IHP SG13G2 130 nm

---

## 1. Overview

QoSoC is a compact, low-power 32-bit RISC-V SoC designed for the IHP SG13G2 130 nm BiCMOS process. It targets deeply embedded IoT control and sensing applications. The architecture is built around the PicoRV32 RV32EC core interconnected via a single-master Wishbone B4 Classic fabric.

---

## 2. Processor

- **Core:** PicoRV32 (`picorv32_wb` variant)  
- **ISA:** RV32EC — 32-bit embedded, compressed instructions, 16 registers (x0–x15)  
- **Pipeline:** 2-stage (in-order, no hardware MUL/DIV)  
- **Bus interface:** Wishbone B4 Classic (parallel)  
- **Interrupts:** 32 sources, mask + acknowledge, NMI supported  

### Interrupt Map

| IRQ | Source | Description |
|---|---|---|
| 0 | GPIO | Edge/level interrupt |
| 1 | UART | RX/TX/error combined |
| 2 | I2C | Command complete or NACK |
| 4 | PTC | Timer overflow / PWM period |
| 6 | RTC0 | Calendar/alarm match |
| 7 | RTC1 | Calendar/alarm match |
| 8 | WDT | Pre-warning before reset |

---

## 3. Clock and Reset

| Domain | Source | Nominal Frequency |
|---|---|---|
| System (`clk_i`) | External pin `clk_PAD` | 16 MHz |
| RTC (`clk_rtc_i`) | External crystal `clk_rtc_PAD` | 32.768 kHz |

Reset strategy: **asynchronous assert, synchronous de-assert** via a 2-FF synchronizer (`qosoc_reset_sync.v`).

---

## 4. Memory Map

| Base | Size | Region |
|---|---|---|
| `0x0000_0000` | 4 KB | Boot ROM |
| `0x1000_0000` | 2 KB | Internal SRAM |
| `0x2000_0000` | 8 MB | QSPI Flash (XIP) |
| `0x8000_0000` | ~1 MB | Peripheral Register Space |

### Peripheral Register Offsets (base `0x8000_0000`)

| Peripheral | Offset |
|---|---|
| GPIO | `0x82000000` |
| UART | `0x82001000` |
| I2C | `0x82002000` |
| PTC | `0x82003000` |
| SysCtrl | `0x82004800` |
| PMU | `0x82005000` |
| RTC0 | `0x82006000` |
| RTC1 | `0x82007000` |
| Watchdog | `0x82008000` |
| QSPI Ctrl | `0x82009000` |

Unoccupied ranges return `ack=1` with all-zero data in normal mode, and `err=1` / `DEAD_BEEF` in debug mode.

---

## 5. Peripherals

### GPIO
- 8-bit bidirectional pad interface
- Per-bit direction control, data register, and interrupt enable
- Edge-triggered and level interrupts; `gpio_PAD[4]` = BOOT strap; `gpio_PAD[7]` = DBG strap (both latched on first clock after reset)

### UART
- ZipCPU `wbuart32` — 16-byte TX and RX FIFOs
- Configurable baud divisor; defaults to 115200 baud at 50 MHz (`DEBUG_UART_SETUP_PARAM` for simulation)
- Shared pad with debug UART (muxed based on `DBG_MODE` strap)

### I2C
- OpenCores I2C master
- 100/400 kHz selectable via prescaler
- IRQ on transfer complete or NACK received

### PTC (Programmable Timer/Counter)
- 32-bit counter, free-running or one-shot
- PWM output on `pwm0_PAD`; capture input from the same pad (bidir)
- IRQ on overflow or PWM period complete

### Dual RTC
- Two independent instances (`qosoc_rtc.v`), each with calendar and alarm
- Run from 32.768 kHz domain; system-clock register interface
- IRQ on alarm match

### Watchdog
- 32-bit auto-reload timer
- Configurable pre-warning IRQ before hardware reset
- Enabled in `PWR_EN[7]`; disable with caution

### QSPI Flash Controller
- ZipCPU `wbqspiflash` — single/dual/quad SPI
- XIP-capable: CPU fetches instructions directly from flash
- Chip select, clock, and 4 data lines on the west pad side

---

## 6. Power Management

The PMU (`qosoc_pmu.v`) owns all power-state transitions and peripheral clock enables.

### Power States

| State | Description |
|---|---|
| ACTIVE | All clocks running per `PWR_EN` |
| SLEEP | CPU clock gated; peripherals active |
| DEEP_SLEEP | All peripheral clocks gated; SRAM retained |
| SHUTDOWN | Same as DEEP_SLEEP, intended for near-zero standby |
| WAKING | Transitional; restoring clocks, waiting for CPU ack |

### Wake Sources

Any of 8 sources can be masked individually via `WAKE_MASK`: GPIO, UART, I2C, PTC0, RTC0, RTC1, Watchdog, QSPI.

### Clock Gating

Each peripheral has a dedicated glitch-free clock gate (`qosoc_clk_gate.v`). Enable is sampled on the falling edge; `test_enable` bypasses the gate for DFT.

Default `PWR_EN` on reset: `0x0107` (CPU + UART + GPIO + QSPI enabled).

---

## 7. Debug and DFT

### Debug Subsystem
- Entered at reset via `GPIO[7]` (`DBG_MODE`) strap
- CPU is held in reset; debug subsystem becomes Wishbone master
- ASCII command protocol over shared UART pads (115200 8N1)

### Commands (partial)
`PING`, `ID`, `STAT`, `DETAIL`, `R <addr>`, `W <addr> <data>`, `D <addr> <n>`, `MBIST START`, `MBIST STAT`, `EVENT POP/CLR/STAT`, `SCRATCH`, `CLR`, `HELP`

### SRAM MBIST
- March-style algorithm on `RM_IHPSG13_1P_512x32_c2_bm_bist`
- Controlled exclusively through the debug subsystem
- Reports pass/fail; does not capture failing address

---

## 8. Physical Implementation

| Parameter | Value |
|---|---|
| Flow | LibreLane (OpenROAD-based), Chip mode |
| Die | 1732 × 1732 µm |
| Core area | ~979 kµm² (367.2 × 370.44 to 1359.84 × 1357.02 µm) |
| Standard cells | 38,326 (post-P&R) |
| PDN | Core ring (15 µm wide straps), connected to pad power cells |
| SRAM macro | Placed at (365, 365), orientation South |
| Pad ring | IHP SG13G2 IO pad library (`sg13g2_IOPad*`) |
| Bondpads | `bondpad_70x70_novias` |
| GDS output | `release/v.1.0.0/gds/MCU2972.gds` |
| Setup violations | None (all PVT corners) |
| Hold violations | None (all PVT corners) |
| LVS | Passed |
| Antenna | Passed |
| IR drop (VDD, worst) | 1.7 mV (0.14%) |
| Total power (typ) | ~5.2 mW @ 16 MHz, 1.2 V |

---

## 9. Dependencies

| Dependency | Version / Source |
|---|---|
| IHP SG13G2 PDK | Hash: `0418301723d86133de686ef743cfd668bb3d11d4` |
| `RM_IHPSG13_1P_512x32_c2_bm_bist` | IHP SG13G2 SRAM macro |
| `bondpad_70x70_novias` | Local IP (`Librelane flow/ip/`) |
| PicoRV32 | Open-source RISC-V (included in `rtl/`) |
| wbuart32 | ZipCPU project (included in `rtl/`) |
| wbqspiflash | ZipCPU project (included in `rtl/vendor/`) |
| OpenCores I2C master | (included in `rtl/`) |

### 9.1 Software Toolchain

| Toolset | Version | Purpose |
|---|---|---|
| **LibreLane** | 3.0.0 | RTL-to-GDSII flow |
| **Icarus Verilog** | 13.0 (devel) | Simulation / Verification |
| **cocotb** | 1.9.2 | Python-based testbench framework |
| **Verilator** | 5.044 | Design Linting |
| **Verible** | v0.2.1 | RTL Linting |
| **RISC-V GCC** | 14.2.0-3 | Firmware (xPack) |
| **Python** | 3.10+ | Support Scripts |

---

## 10. Source File Index

| File | Description |
|---|---|
| `rtl/qosoc_chip_top.sv` | Top-level with pad ring |
| `rtl/qosoc.v` | SoC core (CPU + bus + peripherals) |
| `rtl/qosoc_bus.v` | Wishbone address decoder/fabric |
| `rtl/picorv32.v` | PicoRV32 RISC-V core |
| `rtl/qosoc_rom.v` | Boot ROM |
| `rtl/qosoc_sram_wrapper.v` | SRAM macro wrapper + BIST hookup |
| `rtl/qosoc_pmu.v` | Power Management Unit |
| `rtl/qosoc_rtc.v` | Dual-domain RTC |
| `rtl/qosoc_debug_subsys.v` | Post-silicon debug subsystem |
| `rtl/mbist_controller.v` | SRAM MBIST controller |
| `synthesis/reports/stat.rpt` | Synthesis area/cell statistics |
