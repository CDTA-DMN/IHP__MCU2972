# MCU2972 — QoSoC Design Sources

QoSoC is a 32-bit RISC-V MCU (RV32EC) designed for low-power IoT and embedded control
applications on the IHP SG13CMOS process.

## Features

- **CPU**: PicoRV32 RV32EC — 16 GPRs, 2-stage pipeline, no hardware MUL/DIV
- **Memory**: 4 KB Boot ROM · 2 KB Internal SRAM · QSPI Flash XIP
- **Peripherals**: GPIO (8-bit) · UART · I2C · PTC/PWM · Dual RTC · Watchdog
- **PMU**: 5-state power FSM (Active / Sleep / Deep-Sleep / Shutdown / Waking), per-peripheral clock gating
- **Debug**: Post-silicon ASCII debug subsystem over UART, SRAM MBIST (March algorithm)
- **Interconnect**: Wishbone B4 Classic single-master fabric

## Directory Layout

```
rtl/                  — All synthesisable RTL sources
  qosoc_chip_top.sv   — Full-chip top with IHP SG13G2 pad ring
  qosoc.v             — SoC core (CPU + bus + peripherals)
  qosoc_bus.v         — Wishbone address decoder / fabric
  picorv32.v          — PicoRV32 RISC-V core
  qosoc_pmu.v         — Power Management Unit
  qosoc_rtc.v         — Dual-domain RTC
  qosoc_debug_subsys.v — Post-silicon debug subsystem
  mbist_controller.v  — SRAM MBIST controller
  vendor/             — Third-party IP (ZipCPU QSPI flash controller)

testbenches/          — Simulation environment
  sim/                — Top-level testbench (tb_qosoc.v)
  firmware/           — C firmware test suite (HAL + peripheral tests)
  verification/       — Suite manifests and GLS configuration

constraints/          — SDC timing constraints
synthesis/
  netlist/            — Post-synthesis netlist
  reports/            — Area and timing reports (stat.rpt)
  sdf/                — SDF files for GLS

PlaceAndRoute/
  gds/                — Post-P&R GDS
  lef/                — LEF abstract
  netlist/            — Post-P&R netlist
  parasitics/         — SPEF
  timing/             — Timing reports and liberty files

verification/
  suite_integration_gls.yml — GLS test suite manifest
  sta/  lint/  drc/  lvs/  lec/  cdc/  — Sign-off report placeholders

Flow/
  scripts/            — LibreLane / build support scripts
```

## Testbenches and Verification

The simulation framework uses **Icarus Verilog** with firmware-driven stimulus.
The test suite covers:

| Test | Coverage |
|---|---|
| Boot XIP Check | CPU boot from QSPI Flash, GPIO toggling |
| GPIO & SRAM | GPIO write/read and SRAM patterns |
| UART | Transmit and receive via loopback |
| I2C | Master transaction and ACK handling |
| PTC | Timer interrupt and PWM |
| PMU & Watchdog | Sleep entry, wakeup, watchdog reset |
| Dual RTC | Alarm generation (ultra-fast simulation) |
| LED Blink | GPIO output pattern |
| Stack / Data | CPU stack and ALU correctness |
| Counter Basic | 32-bit counter rollover |
| Memory Pattern | SRAM address/data pattern |

## Physical

| Parameter | Value |
|---|---|
| Flow | LibreLane |
| Die | 1732 × 1732 µm |
| Core | 993 × 993 µm |
| Cell count | ~31,649 |
| Clock period (timing-closed) | 62.5 ns (16 MHz) |
| GDS | `../release/v.1.0.0/gds/MCU2972.gds` |
