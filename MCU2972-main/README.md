# MCU2972



QoSoC is a 32-bit RISC-V MCU designed for low-power IoT applications. 

## Features

- **CPU**: PicoRV32 (RV32EC)
- **Memory**:
  - 4 KB Boot ROM
  - 2 KB Internal SRAM (IHP SG13G2 Single-Port Macro)
  - QSPI Flash with XIP Support
- **Peripherals**:
  - GPIO (8-bit bidirectional, edge interrupts)
  - UART (ZipCPU wbuart32, 16-byte FIFOs)
  - I2C (OpenCores Master, 100/400 kHz)
  - PTC (32-bit Timer/Counter, PWM, Capture)
  - RTC (Dual-domain, Calendar, Alarms)
  - Watchdog (32-bit, Auto-reload)

