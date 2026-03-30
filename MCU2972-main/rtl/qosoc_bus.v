// =============================================================================
// QoSoC Wishbone Interconnect
// =============================================================================
//
// OVERVIEW:
// Single-master Wishbone interconnect for the QoSoC CPU. Performs address
// decode, forwards request signals to one slave window, and multiplexes the
// selected response back to the CPU.
//
// BUS BEHAVIOR:
// - Unmapped or disabled targets return `ack=1` with zero read data.
// - At most one slave select is expected per request.
// - Error/stall are passed through from the selected slave.
//
// =============================================================================
`include "qosoc_defs.vh"
// `define QOSOC_BUS_TRACE

module qosoc_bus (
    input wire clk_i,
    input wire rst_i,
    input wire strict_access_i,

    // Master 0: CPU
    input  wire [31:0] m_adr_i,
    input  wire [31:0] m_dat_i,
    output reg  [31:0] m_dat_o,
    input  wire [ 3:0] m_sel_i,
    input  wire        m_we_i,
    input  wire        m_cyc_i,
    input  wire        m_stb_i,
    output reg         m_ack_o,
    output reg         m_err_o,
    output reg         m_stall_o,

    // Slaves
    input  wire        rom_en,
    output reg  [31:0] rom_adr_o,
    output reg  [31:0] rom_dat_o,
    input  wire [31:0] rom_dat_i,
    output reg  [ 3:0] rom_sel_o,
    output reg         rom_we_o,
    output reg         rom_cyc_o,
    output reg         rom_stb_o,
    input  wire        rom_ack_i,
    input  wire        rom_err_i,
    input  wire        rom_stall_i,

    input  wire        sram_en,
    output reg  [31:0] sram_adr_o,
    output reg  [31:0] sram_dat_o,
    input  wire [31:0] sram_dat_i,
    output reg  [ 3:0] sram_sel_o,
    output reg         sram_we_o,
    output reg         sram_cyc_o,
    output reg         sram_stb_o,
    input  wire        sram_ack_i,
    input  wire        sram_err_i,
    input  wire        sram_stall_i,

    input  wire        qspi_en,
    output reg  [31:0] qspi_adr_o,
    output reg  [31:0] qspi_dat_o,
    input  wire [31:0] qspi_dat_i,
    output reg  [ 3:0] qspi_sel_o,
    output reg         qspi_we_o,
    output reg         qspi_cyc_o,
    output reg         qspi_stb_o,
    input  wire        qspi_ack_i,
    input  wire        qspi_err_i,
    input  wire        qspi_stall_i,

    input  wire        gpio_en,
    output reg  [31:0] gpio_adr_o,
    output reg  [31:0] gpio_dat_o,
    input  wire [31:0] gpio_dat_i,
    output reg  [ 3:0] gpio_sel_o,
    output reg         gpio_we_o,
    output reg         gpio_cyc_o,
    output reg         gpio_stb_o,
    input  wire        gpio_ack_i,
    input  wire        gpio_err_i,
    input  wire        gpio_stall_i,

    input  wire        uart_en,
    output reg  [31:0] uart_adr_o,
    output reg  [31:0] uart_dat_o,
    input  wire [31:0] uart_dat_i,
    output reg  [ 3:0] uart_sel_o,
    output reg         uart_we_o,
    output reg         uart_cyc_o,
    output reg         uart_stb_o,
    input  wire        uart_ack_i,
    input  wire        uart_err_i,
    input  wire        uart_stall_i,

    input  wire        i2c_en,
    output reg  [31:0] i2c_adr_o,
    output reg  [31:0] i2c_dat_o,
    input  wire [31:0] i2c_dat_i,
    output reg  [ 3:0] i2c_sel_o,
    output reg         i2c_we_o,
    output reg         i2c_cyc_o,
    output reg         i2c_stb_o,
    input  wire        i2c_ack_i,
    input  wire        i2c_err_i,
    input  wire        i2c_stall_i,

    input  wire        pwm0_en,      
    output reg  [31:0] pwm0_adr_o,
    output reg  [31:0] pwm0_dat_o,
    input  wire [31:0] pwm0_dat_i,
    output reg  [ 3:0] pwm0_sel_o,
    output reg         pwm0_we_o,
    output reg         pwm0_cyc_o,
    output reg         pwm0_stb_o,
    input  wire        pwm0_ack_i,
    input  wire        pwm0_err_i,
    input  wire        pwm0_stall_i,

    input  wire        rtc0_en,
    output reg  [31:0] rtc0_adr_o,
    output reg  [31:0] rtc0_dat_o,
    input  wire [31:0] rtc0_dat_i,
    output reg  [ 3:0] rtc0_sel_o,
    output reg         rtc0_we_o,
    output reg         rtc0_cyc_o,
    output reg         rtc0_stb_o,
    input  wire        rtc0_ack_i,
    input  wire        rtc0_err_i,
    input  wire        rtc0_stall_i,

    input  wire        rtc1_en,
    output reg  [31:0] rtc1_adr_o,
    output reg  [31:0] rtc1_dat_o,
    input  wire [31:0] rtc1_dat_i,
    output reg  [ 3:0] rtc1_sel_o,
    output reg         rtc1_we_o,
    output reg         rtc1_cyc_o,
    output reg         rtc1_stb_o,
    input  wire        rtc1_ack_i,
    input  wire        rtc1_err_i,
    input  wire        rtc1_stall_i,

    input  wire        wdog_en,
    output reg  [31:0] wdog_adr_o,
    output reg  [31:0] wdog_dat_o,
    input  wire [31:0] wdog_dat_i,
    output reg  [ 3:0] wdog_sel_o,
    output reg         wdog_we_o,
    output reg         wdog_cyc_o,
    output reg         wdog_stb_o,
    input  wire        wdog_ack_i,
    input  wire        wdog_err_i,
    input  wire        wdog_stall_i,

    input  wire        sys_en,
    output reg  [31:0] sys_adr_o,
    output reg  [31:0] sys_dat_o,
    input  wire [31:0] sys_dat_i,
    output reg  [ 3:0] sys_sel_o,
    output reg         sys_we_o,
    output reg         sys_cyc_o,
    output reg         sys_stb_o,
    input  wire        sys_ack_i,
    input  wire        sys_err_i,
    input  wire        sys_stall_i,

    input  wire        pmu_en,
    output reg  [31:0] pmu_adr_o,
    output reg  [31:0] pmu_dat_o,
    input  wire [31:0] pmu_dat_i,
    output reg  [ 3:0] pmu_sel_o,
    output reg         pmu_we_o,
    output reg         pmu_cyc_o,
    output reg         pmu_stb_o,
    input  wire        pmu_ack_i
);

  wire [31:0] active_adr = m_adr_i;
  wire [31:0] active_dat = m_dat_i;
  wire [ 3:0] active_sel = m_sel_i;
  wire        active_we  = m_we_i;
  wire        active_cyc = m_cyc_i;
  wire        active_stb = m_stb_i;

  // ----------------------------------------------------------------
  // Address Decoding
  // ----------------------------------------------------------------
  wire request = active_cyc && active_stb;
  wire [31:0] csr_addr = active_adr & `QOSOC_ADDR_CSR_SUB_MASK;

  wire hit_rom = request && rom_en && ((active_adr & `QOSOC_ADDR_ROM_MASK) == `QOSOC_ADDR_ROM_BASE);
  wire hit_sram  = request && sram_en && ((active_adr & `QOSOC_ADDR_SRAM_MASK) == `QOSOC_ADDR_SRAM_BASE);
  wire hit_qspi  = request && qspi_en && ((active_adr & `QOSOC_ADDR_QSPI_MASK) == `QOSOC_ADDR_QSPI_BASE);
  wire hit_csr = request && ((active_adr & `QOSOC_ADDR_CSR_MASK) == `QOSOC_ADDR_CSR_BASE);

  wire hit_gpio   = hit_csr && gpio_en && (csr_addr == (`QOSOC_ADDR_CSR_BASE + `QOSOC_ADDR_GPIO_OFFSET));
  wire hit_uart   = hit_csr && uart_en && (csr_addr == (`QOSOC_ADDR_CSR_BASE + `QOSOC_ADDR_UART_OFFSET));
  wire hit_i2c = hit_csr && i2c_en && (csr_addr == (`QOSOC_ADDR_CSR_BASE + `QOSOC_ADDR_I2C_OFFSET));
  wire hit_pwm0   = hit_csr && pwm0_en && (csr_addr == (`QOSOC_ADDR_CSR_BASE + `QOSOC_ADDR_PTC_OFFSET));  // PTC0
  wire hit_rtc0  = hit_csr && rtc0_en && (csr_addr == (`QOSOC_ADDR_CSR_BASE + `QOSOC_ADDR_TIMER0_OFFSET));
  wire hit_rtc1  = hit_csr && rtc1_en && (csr_addr == (`QOSOC_ADDR_CSR_BASE + `QOSOC_ADDR_TIMER1_OFFSET));
  wire hit_wdog   = hit_csr && wdog_en && (csr_addr == (`QOSOC_ADDR_CSR_BASE + `QOSOC_ADDR_WDOG_OFFSET));
  wire hit_sys = hit_csr && sys_en && (csr_addr == (`QOSOC_ADDR_CSR_BASE + `QOSOC_ADDR_SYS_OFFSET));
  wire hit_pmu = hit_csr && pmu_en && (csr_addr == (`QOSOC_ADDR_CSR_BASE + `QOSOC_ADDR_PMU_OFFSET));
  wire hit_any = hit_rom | hit_sram | hit_qspi | hit_gpio | hit_uart | hit_i2c | hit_pwm0
               | hit_rtc0 | hit_rtc1 | hit_wdog | hit_sys | hit_pmu;

  // ----------------------------------------------------------------
  // Slave Request Fanout
  // ----------------------------------------------------------------
  always @* begin
    rom_adr_o  = active_adr;
    rom_dat_o  = active_dat;
    rom_sel_o  = active_sel;
    rom_we_o   = active_we;
    rom_cyc_o  = hit_rom;
    rom_stb_o  = hit_rom;

    sram_adr_o = active_adr;
    sram_dat_o = active_dat;
    sram_sel_o = active_sel;
    sram_we_o  = active_we;
    sram_cyc_o = hit_sram;
    sram_stb_o = hit_sram;

    qspi_adr_o = active_adr;
    qspi_dat_o = active_dat;
    qspi_sel_o = active_sel;
    qspi_we_o  = active_we;
    qspi_cyc_o = hit_qspi;
    qspi_stb_o = hit_qspi;

    gpio_adr_o = active_adr;
    gpio_dat_o = active_dat;
    gpio_sel_o = active_sel;
    gpio_we_o  = active_we;
    gpio_cyc_o = hit_gpio;
    gpio_stb_o = hit_gpio;

    uart_adr_o = active_adr;
    uart_dat_o = active_dat;
    uart_sel_o = active_sel;
    uart_we_o  = active_we;
    uart_cyc_o = hit_uart;
    uart_stb_o = hit_uart;

    i2c_adr_o  = active_adr;
    i2c_dat_o  = active_dat;
    i2c_sel_o  = active_sel;
    i2c_we_o   = active_we;
    i2c_cyc_o  = hit_i2c;
    i2c_stb_o  = hit_i2c;

    pwm0_adr_o = active_adr;  
    pwm0_dat_o = active_dat;
    pwm0_sel_o = active_sel;
    pwm0_we_o  = active_we;
    pwm0_cyc_o = hit_pwm0;
    pwm0_stb_o = hit_pwm0;



    rtc0_adr_o = active_adr;
    rtc0_dat_o = active_dat;
    rtc0_sel_o = active_sel;
    rtc0_we_o  = active_we;
    rtc0_cyc_o = hit_rtc0;
    rtc0_stb_o = hit_rtc0;

    rtc1_adr_o = active_adr;
    rtc1_dat_o = active_dat;
    rtc1_sel_o = active_sel;
    rtc1_we_o  = active_we;
    rtc1_cyc_o = hit_rtc1;
    rtc1_stb_o = hit_rtc1;

    wdog_adr_o  = active_adr;
    wdog_dat_o  = active_dat;
    wdog_sel_o  = active_sel;
    wdog_we_o   = active_we;
    wdog_cyc_o  = hit_wdog;
    wdog_stb_o  = hit_wdog;

    sys_adr_o   = active_adr;
    sys_dat_o   = active_dat;
    sys_sel_o   = active_sel;
    sys_we_o    = active_we;
    sys_cyc_o   = hit_sys;
    sys_stb_o   = hit_sys;

    pmu_adr_o   = active_adr;
    pmu_dat_o   = active_dat;
    pmu_sel_o   = active_sel;
    pmu_we_o    = active_we;
    pmu_cyc_o   = hit_pmu;
    pmu_stb_o   = hit_pmu;
  end

  // ----------------------------------------------------------------
  // Slave Response Selection
  // ----------------------------------------------------------------
  reg [31:0] wb_dat_mux;
  reg        wb_ack_mux;
  reg        wb_err_mux;
  reg        wb_stall_mux;

  always @* begin
    wb_dat_mux   = 32'h0;
    wb_ack_mux   = 1'b0;
    wb_err_mux   = 1'b0;
    wb_stall_mux = 1'b0;

    if (hit_rom) begin
      wb_dat_mux   = rom_dat_i;
      wb_ack_mux   = rom_ack_i;
      wb_err_mux   = rom_err_i;
      wb_stall_mux = rom_stall_i;
    end else if (hit_sram) begin
      wb_dat_mux   = sram_dat_i;
      wb_ack_mux   = sram_ack_i;
      wb_err_mux   = sram_err_i;
      wb_stall_mux = sram_stall_i;
    end else if (hit_qspi) begin
      wb_dat_mux   = qspi_dat_i;
      wb_ack_mux   = qspi_ack_i;
      wb_err_mux   = qspi_err_i;
      wb_stall_mux = qspi_stall_i;
    end else if (hit_gpio) begin
      wb_dat_mux   = gpio_dat_i;
      wb_ack_mux   = gpio_ack_i;
      wb_err_mux   = gpio_err_i;
      wb_stall_mux = gpio_stall_i;
    end else if (hit_uart) begin
      wb_dat_mux   = uart_dat_i;
      wb_ack_mux   = uart_ack_i;
      wb_err_mux   = uart_err_i;
      wb_stall_mux = uart_stall_i;
    end else if (hit_i2c) begin
      wb_dat_mux   = i2c_dat_i;
      wb_ack_mux   = i2c_ack_i;
      wb_err_mux   = i2c_err_i;
      wb_stall_mux = i2c_stall_i;
    end else if (hit_pwm0) begin  // PTC0
      wb_dat_mux   = pwm0_dat_i;
      wb_ack_mux   = pwm0_ack_i;
      wb_err_mux   = pwm0_err_i;
      wb_stall_mux = pwm0_stall_i;
    end else if (hit_rtc0) begin
      wb_dat_mux   = rtc0_dat_i;
      wb_ack_mux   = rtc0_ack_i;
      wb_err_mux   = rtc0_err_i;
      wb_stall_mux = rtc0_stall_i;
    end else if (hit_rtc1) begin
      wb_dat_mux   = rtc1_dat_i;
      wb_ack_mux   = rtc1_ack_i;
      wb_err_mux   = rtc1_err_i;
      wb_stall_mux = rtc1_stall_i;
    end else if (hit_wdog) begin
      wb_dat_mux   = wdog_dat_i;
      wb_ack_mux   = wdog_ack_i;
      wb_err_mux   = wdog_err_i;
      wb_stall_mux = wdog_stall_i;
    end else if (hit_sys) begin
      wb_dat_mux   = sys_dat_i;
      wb_ack_mux   = sys_ack_i;
      wb_err_mux   = sys_err_i;
      wb_stall_mux = sys_stall_i;
    end else if (hit_pmu) begin
      wb_dat_mux   = pmu_dat_i;
      wb_ack_mux   = pmu_ack_i;
      wb_err_mux   = 1'b0;
      wb_stall_mux = 1'b0;
    end else if (request) begin
      wb_dat_mux = strict_access_i ? 32'hDEAD_BEEF : 32'h0000_0000;
      wb_ack_mux = ~strict_access_i;
      wb_err_mux =  strict_access_i;
    end
  end

  always @* begin
    m_dat_o   = rst_i ? 32'h0 : wb_dat_mux;
    m_ack_o   = rst_i ? 1'b0  : wb_ack_mux;
    m_err_o   = rst_i ? 1'b0  : wb_err_mux;
    m_stall_o = rst_i ? 1'b0  : wb_stall_mux;
  end

`ifdef QOSOC_BUS_TRACE
  // Optional bus trace for early firmware bring-up and decode validation.
  // Disabled in normal synthesis/simulation unless `QOSOC_BUS_TRACE` is defined.
  // Log UART bus accesses for debug
  always @(posedge clk_i) begin
    if (request && hit_uart) begin
      if (active_we)
        $display(
            "[BUS][UART] WRITE adr=%08x data=%08x sel=%1x at %t",
            active_adr,
            active_dat,
            active_sel,
            $time
        );
      else $display("[BUS][UART] READ  adr=%08x sel=%1x at %t", active_adr, active_sel, $time);
    end
    // Log all CSR window accesses to see what peripherals firmware touches
    if (request && hit_csr) begin
      if (active_we)
        $display(
            "[BUS][CSR] WRITE adr=%08x data=%08x sel=%1x (GPIO=%d UART=%d I2C=%d PTC=%d RTC0=%d RTC1=%d PMU=%d) at %t",
            active_adr,
            active_dat,
            active_sel,
            hit_gpio,
            hit_uart,
            hit_i2c,
            hit_pwm0,
            hit_rtc0,
            hit_rtc1,
            hit_pmu,
            $time
        );
      else
        $display(
            "[BUS][CSR] READ  adr=%08x sel=%1x (GPIO=%d UART=%d I2C=%d PTC=%d RTC0=%d RTC1=%d PMU=%d) at %t",
            active_adr,
            active_sel,
            hit_gpio,
            hit_uart,
            hit_i2c,
            hit_pwm0,
            hit_rtc0,
            hit_rtc1,
            hit_pmu,
            $time
        );
    end
    // Log QSPI accesses (XIP fetches) - reads and writes
    if (request && hit_qspi) begin
      if (active_we)
        $display(
            "[BUS][QSPI] WRITE adr=%08x data=%08x sel=%1x at %t",
            active_adr,
            active_dat,
            active_sel,
            $time
        );
      else if ($time < 100000000)  // Only log first 100ms to avoid spam
        $display("[BUS][QSPI] READ  adr=%08x sel=%1x at %t", active_adr, active_sel, $time);
    end
    // Log ROM accesses to verify boot sequence
    if (request && hit_rom && $time < 10000000) begin  // First 10ms only
      if (active_we)
        $display(
            "[BUS][ROM] WRITE adr=%08x data=%08x sel=%1x at %t",
            active_adr,
            active_dat,
            active_sel,
            $time
        );
      else $display("[BUS][ROM] READ  adr=%08x sel=%1x at %t", active_adr, active_sel, $time);
    end
    // Log SRAM accesses early to see stack usage and .data copy
    if (request && hit_sram && time < 100000000) begin
      if (active_we)
        $display(
            "[BUS][SRAM] WRITE adr=%08x data=%08x sel=%1x at %t",
            active_adr,
            active_dat,
            active_sel,
            $time
        );
      else if (active_adr == 32'h10000000 || active_adr == 32'h10000004)
        $display(
            "[BUS][SRAM] READ  adr=%08x sel=%1x (will return data next cycle) at %t",
            active_adr,
            active_sel,
            $time
        );
    end
    // Log SRAM read data
    if (hit_sram && sram_ack_i && !active_we && (active_adr == 32'h10000000 || active_adr == 32'h10000004) && $time < 100000000) begin
      $display("[BUS][SRAM] READ  adr=%08x returned data=%08x at %t", active_adr, sram_dat_i,
               $time);
    end
  end
`endif
endmodule
