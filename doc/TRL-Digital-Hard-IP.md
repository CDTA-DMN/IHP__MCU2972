# Digital Hard IP Quality Assessment using TRL scale

**IP Name:** MCU2972 — QoSoC  
**Technology:** IHP SG13CMOS 130 nm  
**Assessment Date:** 2026-03-31  

---

## TRL 1-3 Not evaluated

## TRL3 - Experimental proof of concept

- [x] Is the IP functionality clearly described?  
  *QoSoC is a 32-bit RISC-V SoC (RV32EC) targeting low-power IoT applications. Full architecture, memory map, peripheral descriptions, and interrupt model are documented.*

- [x] Have the potential applications of the IP been identified and described?  
  *Deeply embedded control and sensing applications; IoT endpoint nodes requiring UART, I2C, QSPI Flash XIP, GPIO, RTC, and power management.*

- [x] Are the IP requirements and specifications described (I/O description, Target technology, does it include a standard interface...)?  
  *Pinout and I/O descriptions are provided. Target process is IHP SG13CMOS. Wishbone B4 Classic is used as the internal interconnect.*

- [x] Has the RTL design been completed (Doesn't need to be synthesized)?  
  *Full RTL delivered: PicoRV32 CPU, Boot ROM, SRAM wrapper, QSPI XIP controller, GPIO, UART, I2C, PTC/PWM, dual RTC, Watchdog, PMU, Debug Subsystem, and the full pad ring (`qosoc_chip_top.sv`).*

- [x] Has a complete behavioral simulation been performed?  
  *RTL regression suite (Icarus Verilog) covers boot, GPIO/SRAM, UART, I2C, PMU/Watchdog, PTC, RTC, LED blink, stack, data processing, and memory pattern tests.*

- [x] Is a RTL model provided (doesn't need to be synthesizable)?  
  *Full synthesizable RTL is available in `MCU2972-main/rtl/`.*

- [x] Are the behavioral testbenches provided?  
  *Testbenches are provided in `MCU2972-main/testbenches/`. The simulation suite is driven by `verification/suite_integration_gls.yml` using firmware-based stimulus.*

---

## TRL4 - Component prototype

- [x] Has the design been synthesized?  
  *Synthesized with Yosys/LibreLane for IHP SG13CMOS. Synthesis statistics: ~31,649 instances (Yosys pre-map); 38,326 standard cells post-place-and-route, core area ≈ 979 kµm². Report available in `MCU2972-main/synthesis/reports/stat.rpt`.*

- [x] Has a complete post-synthesis simulation been performed?  
  *Gate-Level Simulation (GLS) was performed using Icarus Verilog with IHP SG13CMOS standard-cell models against the firmware test suite. Results are recorded in `MCU2972-main/verification/suite_integration_gls.yml`.*

- [x] Is a post-synthesis model provided with all required files?  
  *Post-synthesis netlist is available in `MCU2972-main/synthesis/netlist/`.*

- [x] Are the post-synthesis testbenches provided?  
  *GLS testbenches and simulation driver (`tb_qosoc.v`) are provided with firmware hex files for each test case.*

- [x] Are the preliminary Power, Performance and Area (PPA) results provided?  
  *Area: ~952 kµm². Timing closure at 16 MHz (period: 62.5 ns) was achieved in the LibreLane run. SDC and SDF files are available in `MCU2972-main/synthesis/sdf/` and `MCU2972-main/PlaceAndRoute/timing/`.*

---

## TRL5 - Subsystem designed and tested

- [x] Is the Place and Route stage performed successfully?  
  *Full chip P&R was performed using LibreLane (OpenROAD-based flow) for the IHP SG13CMOS process. Die size: 1732 × 1732 µm. Core area: ~979 kµm². No setup or hold violations across all PVT corners. LVS and Antenna checks passed. GDS released as `release/v.1.0.0/gds/MCU2972.gds`.*

- [x] Are all the required files to instantiate the IP provided (LEF, netlist, .gds, liberty file .lib…)?  
  *GDS: `release/v.1.0.0/gds/MCU2972.gds`. Post-P&R netlist, LEF, and parasitics are available under `MCU2972-main/PlaceAndRoute/`.*

- [x] Are all the library dependencies stated?  
  *Dependencies: IHP SG13CMOS standard cell library, `SG13CMOS_sram` macro (`RM_IHPSG13_1P_512x32_c2_bm_bist`), `bondpad_70x70_novias`. Listed in `doc/info.json` and `Librelane flow/librelane/config.yaml`.*

- [x] Are the post-place&Route simulations performed and the testbenches provided?  
  *GLS suite executed post-synthesis; waveform artifacts (VCD) are archived. Key tests passed: Boot XIP, GPIO/SRAM, UART, I2C, PMU/Watchdog, PTC, LED Blink, Stack, Data Processing, Counter.*

- [x] Are there clear instructions to use and integrate the hard IP?  
  *The `MCU2972-main/README.md` and `doc/Specification.md` describe pinout, memory map, boot modes, and the debug/bring-up procedure.*

---

## TRL6 - Functional (Alpha) prototype

- [ ] Is the silicon fabricated and demonstrated on a development board or other platform?  
  *Silicon submitted for fabrication via IHP shuttle (MPW). Results pending.*

- [ ] Are the functional tests reported?  
  *Pending silicon return.*

- [ ] Have the key performance metrics been measured in silicon (Power, timing…)?  
  *Pending silicon return.*

- [ ] Is the IP characterized under voltage, temperature and process conditions?  
  *Pending silicon return.*

---

## TRL7 - Field demonstration prototype

- [ ] Is the silicon fabricated and demonstrated on a development board or other platform?
- [ ] Are the functional tests reported?
- [ ] Have the key performance metrics been measured in silicon (Power, timing…)?
- [ ] Is the IP characterized under voltage, temperature and process conditions?

---

## TRL8 - Beta prototype (commercial ready system)

- [ ] Has the IP been deployed in an end-use product?
- [ ] Has the IP been tested in a pilot production run or customer field trial?
- [ ] Has the IP passed the industry standard compliance certification testing?

---

## TRL9 - Commercial application

- [ ] Has this IP been in product production? Is the hard IP integrated in any commercial IC?
- [ ] Are the IP authors providing support for bug fixing or enhancement requests?
- [ ] Does the IP documentation include any training materials?

---