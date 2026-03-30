// =============================================================================
// QoSoC Global Definitions
// Address Map and Utility Parameters
// =============================================================================
//
// ADDRESS DECODING CONTRACT:
// ---------------------------
// All CSR peripherals receive ABSOLUTE addresses on wb_adr_i.
// Each peripheral is responsible for decoding its own register offsets.
// The bus fabric (qosoc_sysctrl or interconnect) uses BASE+MASK to select
// the peripheral, but does NOT strip the base address before forwarding.
//
// IMPORTANT: Peripherals must mask wb_adr_i appropriately to extract their
// register index. Example: reg_addr = wb_adr_i[N:2] where N depends on
// the peripheral's address space size.
//
// =============================================================================

`ifndef QOSOC_DEFS_VH
`define QOSOC_DEFS_VH

// -----------------------------------------------------------------------------
// Wishbone Slave Indices (12 slaves total)
// -----------------------------------------------------------------------------
`define QOSOC_SLV_ROM 0
`define QOSOC_SLV_SRAM 1
`define QOSOC_SLV_QSPI 2
`define QOSOC_SLV_GPIO 3
`define QOSOC_SLV_UART 4
`define QOSOC_SLV_I2C 5
`define QOSOC_SLV_PTC0 6   
`define QOSOC_SLV_TIMER0 7
`define QOSOC_SLV_TIMER1 8
`define QOSOC_SLV_WDOG 9
`define QOSOC_SLV_SYSCTRL 10
`define QOSOC_SLV_PMU 11
`define QOSOC_SLV_COUNT 12

// -----------------------------------------------------------------------------
// Memory-Mapped Address Ranges
// -----------------------------------------------------------------------------
// ROM: 4KB window (1024 x 32-bit words)
`define QOSOC_ADDR_ROM_BASE 32'h0000_0000
`define QOSOC_ADDR_ROM_MASK 32'hFFFF_F000  // Masks 12 bits -> 4KB

// SRAM: 2KB window (512 x 32-bit words)
`define QOSOC_ADDR_SRAM_BASE 32'h1000_0000
`define QOSOC_ADDR_SRAM_MASK 32'hFFFF_F800  // Masks 11 bits -> 2KB

// QSPI Flash: 8MB window for W25Q64 (8 megabytes)
`define QOSOC_ADDR_QSPI_BASE 32'h2000_0000
`define QOSOC_ADDR_QSPI_MASK 32'hFF80_0000  // Masks 23 bits -> 8MB (CORRECTED)
`define QOSOC_ADDR_QSPI_CTRL 32'h2000_0000  // QSPI controller registers

// CSR (Control/Status Register) Region: 32KB window
`define QOSOC_ADDR_CSR_BASE 32'h8200_0000
`define QOSOC_ADDR_CSR_MASK 32'hFFFF_8000  // Masks 15 bits -> 32KB

// -----------------------------------------------------------------------------
// CSR Peripheral Offsets (from CSR_BASE)
// -----------------------------------------------------------------------------
// Each peripheral gets a 2KB window (0x800 bytes)
// This allows 256 x 32-bit registers per peripheral (more than enough)

`define QOSOC_ADDR_GPIO_OFFSET   32'h0000  // 0x8200_0000
`define QOSOC_ADDR_UART_OFFSET   32'h0800  // 0x8200_0800
`define QOSOC_ADDR_I2C_OFFSET    32'h1000  // 0x8200_1000
`define QOSOC_ADDR_PTC_OFFSET    32'h2000  // 0x8200_2000
`define QOSOC_ADDR_TIMER0_OFFSET 32'h3000  // 0x8200_3000
`define QOSOC_ADDR_TIMER1_OFFSET 32'h3800  // 0x8200_3800
`define QOSOC_ADDR_WDOG_OFFSET   32'h4000  // 0x8200_4000
`define QOSOC_ADDR_SYS_OFFSET    32'h4800  // 0x8200_4800
`define QOSOC_ADDR_PMU_OFFSET    32'h5000  // 0x8200_5000

// CSR sub-window mask (2KB granularity for peripheral decode)
`define QOSOC_ADDR_CSR_SUB_MASK 32'hFFFF_F800  // Masks 11 bits -> 2KB

// -----------------------------------------------------------------------------
// Compile-Time Address Map Validation (Simulation Only)
// -----------------------------------------------------------------------------
// These checks catch overlapping address ranges at synthesis time
`ifdef SIMULATION
initial begin
    // Check ROM and SRAM don't overlap
    if (((`QOSOC_ADDR_ROM_BASE & `QOSOC_ADDR_ROM_MASK) == 
         (`QOSOC_ADDR_SRAM_BASE & `QOSOC_ADDR_ROM_MASK)) ||
        ((`QOSOC_ADDR_SRAM_BASE & `QOSOC_ADDR_SRAM_MASK) == 
         (`QOSOC_ADDR_ROM_BASE & `QOSOC_ADDR_SRAM_MASK)))
        $fatal(1, "Address map overlap: ROM and SRAM");
    
    // Check QSPI doesn't overlap with CSR
    if ((`QOSOC_ADDR_QSPI_BASE & `QOSOC_ADDR_CSR_MASK) == 
        (`QOSOC_ADDR_CSR_BASE & `QOSOC_ADDR_CSR_MASK))
        $fatal(1, "Address map overlap: QSPI and CSR");
    
    // Verify CSR offsets don't exceed CSR window
    if (`QOSOC_ADDR_PMU_OFFSET >= 32'h8000)
        $fatal(1, "CSR offset exceeds 32KB window");
end
`endif

// -----------------------------------------------------------------------------
// UART Register Indices (for wbuart wrapper compatibility)
// -----------------------------------------------------------------------------
`define UART_SETUP_ADDR 5'h00
`define UART_FIFO_ADDR  5'h01
`define UART_RX_ADDR    5'h02
`define UART_TX_ADDR    5'h03

// -----------------------------------------------------------------------------
// Power Control Register Bit Fields
// -----------------------------------------------------------------------------
`define QOSOC_PWR_CPU_EN_BIT   0
`define QOSOC_PWR_GPIO_EN_BIT  1
`define QOSOC_PWR_UART_EN_BIT  2
`define QOSOC_PWR_I2C_EN_BIT   3
`define QOSOC_PWR_PWM0_EN_BIT  4   
`define QOSOC_PWR_TMR0_EN_BIT  5
`define QOSOC_PWR_TMR1_EN_BIT  6
`define QOSOC_PWR_WDOG_EN_BIT  7
`define QOSOC_PWR_QSPI_EN_BIT  8

// Default power state: CPU, UART, GPIO enabled (safe boot state)
`define QOSOC_PWR_DEFAULT 16'h0107  // Bits [2:0] = CPU, UART, GPIO; Bit [8] = QSPI

// -----------------------------------------------------------------------------
// Helper Macros
// -----------------------------------------------------------------------------
`define QOSOC_WORD_OFFSET(addr) addr[4:2]  // Extract word offset from byte address
`define QOSOC_BYTE_OFFSET(addr) addr[1:0]  // Extract byte offset

`endif  // QOSOC_DEFS_VH
