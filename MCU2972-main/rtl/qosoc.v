// =============================================================================
// QoSoC Top-Level Integration
// =============================================================================
//
// OVERVIEW:
// Top-level SoC module. Instantiates CPU, interconnect, memories, peripherals,
// PMU/SYSCTRL, and top-level pad-facing interfaces.
//
// INTEGRATION NOTES:
// - Address map and power bit positions are defined in `qosoc_defs.vh`.
// - `rst_ni` is the chip-level asynchronous reset input.
// - `SIM_SPEEDUP` is used by RTC-related logic to accelerate simulation only.
//
// =============================================================================
`include "qosoc_defs.vh"

module qosoc #(
        parameter [31:0] PROGADDR_RESET_PARAM = `QOSOC_ADDR_ROM_BASE,
        parameter SIM_SPEEDUP = 0,
        parameter [30:0] DEBUG_UART_SETUP_PARAM = 31'd139 // 16MHz / 115200 = 139
    ) (
        input wire clk_i,
        input wire rst_ni,

        // UART
        input  wire ser_rx_i,
        output wire ser_tx_o,

        // I2C
        output wire i2c_scl_o,
        output wire i2c_scl_oe_o,
        input  wire i2c_scl_i,
        output wire i2c_sda_o,
        output wire i2c_sda_oe_o,
        input  wire i2c_sda_i,

        // GPIO
        input  wire [7:0] gpio_i,
        output wire [7:0] gpio_o,
        output wire [7:0] gpio_oe_o,

        // Boot mode input (1=Download/UART, 0=Normal/Flash)
        input  wire       boot_mode_i,
        input  wire       dbg_mode_i,

        // PWM / Timer (PTC) channel
        input  wire ptc0_gate_clk_i,
        input  wire ptc0_capt_i,
        output wire ptc0_pwm_o,
        output wire ptc0_pwm_oe_o,

        // QSPI flash
        output wire       qspi_sck_o,
        output wire       qspi_cs_n_o,
        output wire [3:0] qspi_dat_o,
        output wire [3:0] qspi_dat_oe_o,
        input  wire [3:0] qspi_dat_i,
        output wire [1:0] qspi_dat_mode_o,

        // RTC Clock
        input  wire clk_rtc_i,
        
        // Status
        output wire trap_o
    );

    // ------------------------------------------------------------------
    // Reset synchronisation
    // ------------------------------------------------------------------
    wire rst_i;
    qosoc_reset_sync u_reset_sync (
                         .clk_i       (clk_i),
                         .rst_ni      (rst_ni),
                         .rst_sync_o  (rst_i)
                     );

    // ------------------------------------------------------------------
    // Power control and wake infrastructure
    // ------------------------------------------------------------------
    // `pwr_en` bits are owned by PMU and consumed throughout top-level to gate
    // bus visibility, local clocks, and IRQ forwarding for each peripheral.
    wire [15:0] pwr_en;
    wire        pmu_cpu_sleep_req;
    wire        sysctrl_cpu_sleep_req;
    wire        cpu_sleep_req = sysctrl_cpu_sleep_req | pmu_cpu_sleep_req;
    wire        cpu_sleep_ack;
    wire [ 7:0] wake_sources;
    wire        wake_event;

    // Wakeup sources assigned at end of file

    // ------------------------------------------------------------------
    // CPU clock gating
    // ------------------------------------------------------------------
    // CPU runs only when both PMU enables CPU power and no sleep request is active.
    wire        cpu_clk_en = pwr_en[`QOSOC_PWR_CPU_EN_BIT] & ~cpu_sleep_req;
    wire        clk_cpu;
    wire        cpu_rst_dbg = rst_i | dbg_mode_i;
    qosoc_clk_gate u_cpu_clk_gate (
                       .clk_in     (clk_i),
                       .rst_n      (rst_ni),
                       .enable     (cpu_clk_en),
                       .clk_out    (clk_cpu)
                   );
    // Sleep acknowledge is derived from effective CPU clock enable in this top.
    assign cpu_sleep_ack = ~cpu_clk_en;

    // ------------------------------------------------------------------
    // CPU instance
    // ------------------------------------------------------------------
    wire [31:0] cpu_adr;
    wire [31:0] cpu_dat_o;
    wire [31:0] bus_dat_s2m;
    wire [ 3:0] cpu_sel;
    wire        cpu_we;
    wire        cpu_stb;
    wire        cpu_cyc;
    wire        bus_ack_s2m;
    wire        bus_err_s2m;
    wire        bus_stall_s2m;
    wire [31:0] cpu_irq;
    wire [31:0] cpu_eoi;
    wire        cpu_trap;
    wire        cpu_trace_valid;
    wire [35:0] cpu_trace_data;
    wire        cpu_mem_instr;
    wire [31:0] cpu_bus_dat_i = dbg_mode_i ? 32'h0 : bus_dat_s2m;
    wire        cpu_bus_ack_i = dbg_mode_i ? 1'b0 : bus_ack_s2m;

    picorv32_wb #(
                    .ENABLE_COUNTERS     (0),
                    .ENABLE_REGS_16_31   (0),
                    .ENABLE_REGS_DUALPORT(1),
                    .TWO_STAGE_SHIFT     (1),
                    .COMPRESSED_ISA      (1),
                    .CATCH_MISALIGN      (1),
                    .CATCH_ILLINSN       (1),
                    .ENABLE_MUL          (0),
                    .ENABLE_DIV          (0),
                    .ENABLE_IRQ          (1),
                    .ENABLE_IRQ_QREGS    (1),
                    .ENABLE_IRQ_TIMER    (0),
                    .ENABLE_TRACE        (1),
                    .PROGADDR_RESET      (PROGADDR_RESET_PARAM),
                    .PROGADDR_IRQ        (32'h20001010)
                ) u_cpu (
                    .trap       (cpu_trap),
                    .wb_rst_i   (cpu_rst_dbg),
                    .wb_clk_i   (clk_cpu),
                    .wbm_adr_o  (cpu_adr),
                    .wbm_dat_o  (cpu_dat_o),
                    .wbm_dat_i  (cpu_bus_dat_i),
                    .wbm_we_o   (cpu_we),
                    .wbm_sel_o  (cpu_sel),
                    .wbm_stb_o  (cpu_stb),
                    .wbm_ack_i  (cpu_bus_ack_i),
                    .wbm_cyc_o  (cpu_cyc),
                    .irq        (cpu_irq),
                    .eoi        (),
                    .pcpi_valid (),
                    .pcpi_insn  (),
                    .pcpi_rs1   (),
                    .pcpi_rs2   (),
                    .pcpi_wr    (1'b0),
                    .pcpi_rd    (32'h0),
                    .pcpi_wait  (1'b0),
                    .pcpi_ready (1'b0),
                    .trace_valid(cpu_trace_valid),
                    .trace_data (cpu_trace_data),
                    .mem_instr  (cpu_mem_instr)
                );
    assign trap_o = cpu_trap;

    // ------------------------------------------------------------------
    // Wishbone interconnect wiring
    // ------------------------------------------------------------------
    // One signal bundle per target keeps peripheral wiring explicit and makes
    // address-map reviews easier before tapeout.
    wire [31:0] rom_adr;
    wire [31:0] rom_dat_m2s;
    wire [31:0] rom_dat_s2m;
    wire [ 3:0] rom_sel;
    wire        rom_we;
    wire        rom_cyc;
    wire        rom_stb;
    wire        rom_ack;
    wire        rom_stall;
    wire        rom_err;

    wire [31:0] sram_adr;
    wire [31:0] sram_dat_m2s;
    wire [31:0] sram_dat_s2m;
    wire [ 3:0] sram_sel;
    wire        sram_we;
    wire        sram_cyc;
    wire        sram_stb;
    wire        sram_ack;
    wire        sram_stall;
    wire        sram_err;

    wire [31:0] qspi_adr;
    wire [31:0] qspi_dat_m2s;
    wire [31:0] qspi_dat_s2m;
    wire [ 3:0] qspi_sel;
    wire        qspi_we;
    wire        qspi_cyc;
    wire        qspi_stb;
    wire        qspi_ack;
    wire        qspi_stall;
    wire        qspi_err;

    wire [31:0] gpio_adr;
    wire [31:0] gpio_dat_m2s;
    wire [31:0] gpio_dat_s2m;
    wire [ 3:0] gpio_sel;
    wire        gpio_we;
    wire        gpio_cyc;
    wire        gpio_stb;
    wire        gpio_ack;
    wire        gpio_stall;
    wire        gpio_err;

    wire [31:0] uart_adr;
    wire [31:0] uart_dat_m2s;
    wire [31:0] uart_dat_s2m;
    wire [ 3:0] uart_sel;
    wire        uart_we;
    wire        uart_cyc;
    wire        uart_stb;
    wire        uart_ack;
    wire        uart_stall;
    wire        uart_err;

    wire [31:0] i2c_adr;
    wire [31:0] i2c_dat_m2s;
    wire [31:0] i2c_dat_s2m;
    wire [ 3:0] i2c_sel;
    wire        i2c_we;
    wire        i2c_cyc;
    wire        i2c_stb;
    wire        i2c_ack;
    wire        i2c_stall;
    wire        i2c_err;


    // PWM0/PTC0 signals
    wire [31:0] pwm0_adr;
    wire [31:0] pwm0_dat_m2s;
    wire [31:0] pwm0_dat_s2m;
    wire [ 3:0] pwm0_sel;
    wire        pwm0_we;
    wire        pwm0_cyc;
    wire        pwm0_stb;
    wire        pwm0_ack;
    wire        pwm0_stall;
    wire        pwm0_err;

    wire [31:0] rtc0_adr;
    wire [31:0] rtc0_dat_m2s;
    wire [31:0] rtc0_dat_s2m;
    wire [ 3:0] rtc0_sel;
    wire        rtc0_we;
    wire        rtc0_cyc;
    wire        rtc0_stb;
    wire        rtc0_ack;
    wire        rtc0_stall;
    wire        rtc0_err;

    wire [31:0] rtc1_adr;
    wire [31:0] rtc1_dat_m2s;
    wire [31:0] rtc1_dat_s2m;
    wire [ 3:0] rtc1_sel;
    wire        rtc1_we;
    wire        rtc1_cyc;
    wire        rtc1_stb;
    wire        rtc1_ack;
    wire        rtc1_stall;
    wire        rtc1_err;

    wire [31:0] wdog_adr;
    wire [31:0] wdog_dat_m2s;
    wire [31:0] wdog_dat_s2m;
    wire [ 3:0] wdog_sel;
    wire        wdog_we;
    wire        wdog_cyc;
    wire        wdog_stb;
    wire        wdog_ack;
    wire        wdog_stall;
    wire        wdog_err;

    wire [31:0] sys_adr;
    wire [31:0] sys_dat_m2s;
    wire [31:0] sys_dat_s2m;
    wire [ 3:0] sys_sel;
    wire        sys_we;
    wire        sys_cyc;
    wire        sys_stb;
    wire        sys_ack;
    wire        sys_stall;
    wire        sys_err;

    wire [31:0] pmu_adr;
    wire [31:0] pmu_dat_m2s;
    wire [31:0] pmu_dat_s2m;
    wire [ 3:0] pmu_sel;
    wire        pmu_we;
    wire        pmu_cyc;
    wire        pmu_stb;
    wire        pmu_ack;

    wire [31:0] dbg_adr;
    wire [31:0] dbg_dat_m2s;
    wire [31:0] dbg_dat_s2m = dbg_mode_i ? bus_dat_s2m : 32'h0;
    wire [ 3:0] dbg_sel;
    wire        dbg_we;
    wire        dbg_cyc;
    wire        dbg_stb;
    wire        dbg_ack   = dbg_mode_i ? bus_ack_s2m   : 1'b0;
    wire        dbg_err   = dbg_mode_i ? bus_err_s2m   : 1'b0;
    wire        dbg_stall = dbg_mode_i ? bus_stall_s2m : 1'b0;

    wire [31:0] master_adr = dbg_mode_i ? dbg_adr     : cpu_adr;
    wire [31:0] master_dat = dbg_mode_i ? dbg_dat_m2s : cpu_dat_o;
    wire [ 3:0] master_sel = dbg_mode_i ? dbg_sel     : cpu_sel;
    wire        master_we  = dbg_mode_i ? dbg_we      : cpu_we;
    wire        master_cyc = dbg_mode_i ? dbg_cyc     : cpu_cyc;
    wire        master_stb = dbg_mode_i ? dbg_stb     : cpu_stb;

    wire        debug_ser_tx;
    wire        main_ser_tx;
    wire        dbg_mbist_enable;
    wire        dbg_mbist_start;
    wire [ 2:0] pmu_power_state;
    wire        pmu_domains_ready;
    wire        mbist_busy;
    wire        mbist_done;
    wire        mbist_pass;
    wire        mbist_fail;
    wire        mbist_sram_clk;
    wire        mbist_sram_men;
    wire        mbist_sram_wen;
    wire        mbist_sram_ren;
    wire [ 8:0] mbist_sram_addr;
    wire [31:0] mbist_sram_din;
    wire [31:0] mbist_sram_dout;
    wire        mbist_bist_clk;
    wire        mbist_bist_en;
    wire        mbist_bist_men;

    assign rom_err   = 1'b0;
    assign sys_stall = 1'b0;

    qosoc_debug_subsys #(
                           .UART_SETUP(DEBUG_UART_SETUP_PARAM),
                           .DEBUG_LITE(1'b1)
                       ) u_debug_subsys (
                           .clk_i            (clk_i),
                           .rst_i            (rst_i),
                           .dbg_mode_i       (dbg_mode_i),
                           .boot_mode_i      (boot_mode_i),
                           .trap_i           (cpu_trap),
                           .pwr_en_i         (pwr_en),
                           .wake_sources_i   (wake_sources),
                           .wake_event_i     (wake_event),
                           .cpu_clk_en_i     (cpu_clk_en),
                           .power_state_i    (pmu_power_state),
                           .domains_ready_i  (pmu_domains_ready),
                           .uart_rx_i        (ser_rx_i),
                           .uart_tx_o        (debug_ser_tx),
                           .wb_adr_o         (dbg_adr),
                           .wb_dat_o         (dbg_dat_m2s),
                           .wb_dat_i         (dbg_dat_s2m),
                           .wb_sel_o         (dbg_sel),
                           .wb_we_o          (dbg_we),
                           .wb_cyc_o         (dbg_cyc),
                           .wb_stb_o         (dbg_stb),
                           .wb_ack_i         (dbg_ack),
                           .wb_err_i         (dbg_err),
                           .wb_stall_i       (dbg_stall),
                           .mbist_enable_o   (dbg_mbist_enable),
                           .mbist_start_o    (dbg_mbist_start),
                           .mbist_busy_i     (mbist_busy),
                           .mbist_done_i     (mbist_done),
                           .mbist_pass_i     (mbist_pass),
                           .mbist_fail_i     (mbist_fail)
                       );

    qosoc_bus u_bus (
                  .clk_i         (clk_i),
                  .rst_i         (rst_i),
                  .strict_access_i(dbg_mode_i),
                  .m_adr_i       (master_adr),
                  .m_dat_i       (master_dat),
                  .m_dat_o       (bus_dat_s2m),
                  .m_sel_i       (master_sel),
                  .m_we_i        (master_we),
                  .m_cyc_i       (master_cyc),
                  .m_stb_i       (master_stb),
                  .m_ack_o       (bus_ack_s2m),
                  .m_err_o       (bus_err_s2m),
                  .m_stall_o     (bus_stall_s2m),
                  .rom_en        (1'b1),
                  .rom_adr_o     (rom_adr),
                  .rom_dat_o     (rom_dat_m2s),
                  .rom_dat_i     (rom_dat_s2m),
                  .rom_sel_o     (rom_sel),
                  .rom_we_o      (rom_we),
                  .rom_cyc_o     (rom_cyc),
                  .rom_stb_o     (rom_stb),
                  .rom_ack_i     (rom_ack),
                  .rom_err_i     (rom_err),
                  .rom_stall_i   (rom_stall),
                  .sram_en       (pwr_en[`QOSOC_PWR_CPU_EN_BIT]),
                  .sram_adr_o    (sram_adr),
                  .sram_dat_o    (sram_dat_m2s),
                  .sram_dat_i    (sram_dat_s2m),
                  .sram_sel_o    (sram_sel),
                  .sram_we_o     (sram_we),
                  .sram_cyc_o    (sram_cyc),
                  .sram_stb_o    (sram_stb),
                  .sram_ack_i    (sram_ack),
                  .sram_err_i    (sram_err),
                  .sram_stall_i  (sram_stall),
                  .qspi_en       (pwr_en[`QOSOC_PWR_QSPI_EN_BIT]),
                  .qspi_adr_o    (qspi_adr),
                  .qspi_dat_o    (qspi_dat_m2s),
                  .qspi_dat_i    (qspi_dat_s2m),
                  .qspi_sel_o    (qspi_sel),
                  .qspi_we_o     (qspi_we),
                  .qspi_cyc_o    (qspi_cyc),
                  .qspi_stb_o    (qspi_stb),
                  .qspi_ack_i    (qspi_ack),
                  .qspi_err_i    (qspi_err),
                  .qspi_stall_i  (qspi_stall),
                  .gpio_en       (pwr_en[`QOSOC_PWR_GPIO_EN_BIT]),
                  .gpio_adr_o    (gpio_adr),
                  .gpio_dat_o    (gpio_dat_m2s),
                  .gpio_dat_i    (gpio_dat_s2m),
                  .gpio_sel_o    (gpio_sel),
                  .gpio_we_o     (gpio_we),
                  .gpio_cyc_o    (gpio_cyc),
                  .gpio_stb_o    (gpio_stb),
                  .gpio_ack_i    (gpio_ack),
                  .gpio_err_i    (gpio_err),
                  .gpio_stall_i  (gpio_stall),
                  .uart_en       (pwr_en[`QOSOC_PWR_UART_EN_BIT]),
                  .uart_adr_o    (uart_adr),
                  .uart_dat_o    (uart_dat_m2s),
                  .uart_dat_i    (uart_dat_s2m),
                  .uart_sel_o    (uart_sel),
                  .uart_we_o     (uart_we),
                  .uart_cyc_o    (uart_cyc),
                  .uart_stb_o    (uart_stb),
                  .uart_ack_i    (uart_ack),
                  .uart_err_i    (uart_err),
                  .uart_stall_i  (uart_stall),
                  .i2c_en        (pwr_en[`QOSOC_PWR_I2C_EN_BIT]),
                  .i2c_adr_o     (i2c_adr),
                  .i2c_dat_o     (i2c_dat_m2s),
                  .i2c_dat_i     (i2c_dat_s2m),
                  .i2c_sel_o     (i2c_sel),
                  .i2c_we_o      (i2c_we),
                  .i2c_cyc_o     (i2c_cyc),
                  .i2c_stb_o     (i2c_stb),
                  .i2c_ack_i     (i2c_ack),
                  .i2c_err_i     (i2c_err),
                  .i2c_stall_i   (i2c_stall),
                  .pwm0_en       (pwr_en[`QOSOC_PWR_PWM0_EN_BIT]),
                  .pwm0_adr_o    (pwm0_adr),
                  .pwm0_dat_o    (pwm0_dat_m2s),
                  .pwm0_dat_i    (pwm0_dat_s2m),
                  .pwm0_sel_o    (pwm0_sel),
                  .pwm0_we_o     (pwm0_we),
                  .pwm0_cyc_o    (pwm0_cyc),
                  .pwm0_stb_o    (pwm0_stb),
                  .pwm0_ack_i    (pwm0_ack),
                  .pwm0_err_i    (pwm0_err),
                  .pwm0_stall_i  (pwm0_stall),
                  .rtc0_en       (pwr_en[`QOSOC_PWR_TMR0_EN_BIT]),
                  .rtc0_adr_o    (rtc0_adr),
                  .rtc0_dat_o    (rtc0_dat_m2s),
                  .rtc0_dat_i    (rtc0_dat_s2m),
                  .rtc0_sel_o    (rtc0_sel),
                  .rtc0_we_o     (rtc0_we),
                  .rtc0_cyc_o    (rtc0_cyc),
                  .rtc0_stb_o    (rtc0_stb),
                  .rtc0_ack_i    (rtc0_ack),
                  .rtc0_err_i    (rtc0_err),
                  .rtc0_stall_i  (rtc0_stall),
                  .rtc1_en       (pwr_en[`QOSOC_PWR_TMR1_EN_BIT]),
                  .rtc1_adr_o    (rtc1_adr),
                  .rtc1_dat_o    (rtc1_dat_m2s),
                  .rtc1_dat_i    (rtc1_dat_s2m),
                  .rtc1_sel_o    (rtc1_sel),
                  .rtc1_we_o     (rtc1_we),
                  .rtc1_cyc_o    (rtc1_cyc),
                  .rtc1_stb_o    (rtc1_stb),
                  .rtc1_ack_i    (rtc1_ack),
                  .rtc1_err_i    (rtc1_err),
                  .rtc1_stall_i  (rtc1_stall),
                  .wdog_en       (pwr_en[`QOSOC_PWR_WDOG_EN_BIT]),
                  .wdog_adr_o    (wdog_adr),
                  .wdog_dat_o    (wdog_dat_m2s),
                  .wdog_dat_i    (wdog_dat_s2m),
                  .wdog_sel_o    (wdog_sel),
                  .wdog_we_o     (wdog_we),
                  .wdog_cyc_o    (wdog_cyc),
                  .wdog_stb_o    (wdog_stb),
                  .wdog_ack_i    (wdog_ack),
                  .wdog_err_i    (wdog_err),
                  .wdog_stall_i  (wdog_stall),
                  .sys_en        (1'b1),
                  .sys_adr_o     (sys_adr),
                  .sys_dat_o     (sys_dat_m2s),
                  .sys_dat_i     (sys_dat_s2m),
                  .sys_sel_o     (sys_sel),
                  .sys_we_o      (sys_we),
                  .sys_cyc_o     (sys_cyc),
                  .sys_stb_o     (sys_stb),
                  .sys_ack_i     (sys_ack),
                  .sys_err_i     (sys_err),
                  .sys_stall_i   (sys_stall),
                  .pmu_en        (1'b1),
                  .pmu_adr_o     (pmu_adr),
                  .pmu_dat_o     (pmu_dat_m2s),
                  .pmu_dat_i     (pmu_dat_s2m),
                  .pmu_sel_o     (pmu_sel),
                  .pmu_we_o      (pmu_we),
                  .pmu_cyc_o     (pmu_cyc),
                  .pmu_stb_o     (pmu_stb),
                  .pmu_ack_i     (pmu_ack)
              );

    // ------------------------------------------------------------------
    // Memories and peripheral instances
    // ------------------------------------------------------------------
    qosoc_rom #(
                  .WORDS(1024)
              ) u_rom (
                  .clk_i     (clk_i),
                  .rst_i     (rst_i),
                  .rst_ni    (rst_ni),
                  .clk_en_i  (1'b1),
                  .wb_cyc_i  (rom_cyc),
                  .wb_stb_i  (rom_stb),
                  .wb_we_i   (rom_we),
                  .wb_sel_i  (rom_sel),
                  .wb_adr_i  (rom_adr),
                  .wb_dat_i  (rom_dat_m2s),
                  .wb_dat_o  (rom_dat_s2m),
                  .wb_ack_o  (rom_ack),
                  .wb_stall_o(rom_stall)
              );

    mbist_controller u_mbist_controller (
        .clk_i       (clk_i),
        .rst_ni      (rst_ni),
        .mbist_enable(dbg_mbist_enable),
        .mbist_start (dbg_mbist_start),
        .mbist_busy  (mbist_busy),
        .mbist_done  (mbist_done),
        .mbist_pass  (mbist_pass),
        .mbist_fail  (mbist_fail),
        .sram_clk    (mbist_sram_clk),
        .sram_men    (mbist_sram_men),
        .sram_wen    (mbist_sram_wen),
        .sram_ren    (mbist_sram_ren),
        .sram_addr   (mbist_sram_addr),
        .sram_din    (mbist_sram_din),
        .sram_dout   (mbist_sram_dout),
        .bist_clk    (mbist_bist_clk),
        .bist_en     (mbist_bist_en),
        .bist_men    (mbist_bist_men)
    );

    // IHP SG13G2 SRAM macro wrapper (512 x 32-bit words = 2 KiB).
    // Connected as CPU data SRAM and controlled by CPU-domain power bit.
    qosoc_sram_wrapper u_sram (
                           .clk_i     (clk_i),
                           .rst_i     (rst_i),
                           .rst_ni    (rst_ni),
                           .wb_adr_i  (sram_adr),
                           .wb_dat_i  (sram_dat_m2s),
                           .wb_dat_o  (sram_dat_s2m),
                           .wb_sel_i  (sram_sel),
                           .wb_we_i   (sram_we),
                           .wb_stb_i  (sram_stb),
                           .wb_cyc_i  (sram_cyc),
                           .wb_ack_o  (sram_ack),
                           .wb_err_o  (sram_err),
                           .wb_stall_o(sram_stall),
                           .pwr_en_i  (pwr_en[`QOSOC_PWR_CPU_EN_BIT]),
                           .mbist_clk (mbist_bist_clk),
                           .mbist_en  (mbist_bist_en),
                           .mbist_men (mbist_bist_men),
                           .mbist_wen (mbist_sram_wen),
                           .mbist_ren (mbist_sram_ren),
                           .mbist_addr(mbist_sram_addr),
                           .mbist_din (mbist_sram_din),
                           .mbist_bm  (32'hFFFFFFFF),
                           .mbist_dout_o(mbist_sram_dout)
                       );

    wire irq_qspi;
    qosoc_qspi #(
                   .ADDRESS_WIDTH(23)  // 23 bits = 8MB for W25Q64FW
               ) u_qspi (
                   .clk_i        (clk_i),
                   .rst_i        (rst_i),
                   .rst_ni       (rst_ni),
                   .clk_en_i     (pwr_en[`QOSOC_PWR_QSPI_EN_BIT]),
                   .wb_cyc_i     (qspi_cyc),
                   .wb_stb_i     (qspi_stb),
                   .wb_we_i      (qspi_we),
                   .wb_sel_i     (qspi_sel),
                   .wb_adr_i     (qspi_adr),
                   .wb_dat_i     (qspi_dat_m2s),
                   .wb_dat_o     (qspi_dat_s2m),
                   .wb_ack_o     (qspi_ack),
                   .wb_err_o     (qspi_err),
                   .wb_stall_o   (qspi_stall),
                   .irq_o        (irq_qspi),
                   .qspi_sck     (qspi_sck_o),
                   .qspi_cs_n    (qspi_cs_n_o),
                   .qspi_dat_o   (qspi_dat_o),
                   .qspi_dat_oe  (qspi_dat_oe_o),
                   .qspi_dat_i   (qspi_dat_i),
                   .qspi_dat_mode(qspi_dat_mode_o)
               );

    wire irq_gpio;
    qosoc_gpio u_gpio (
                   .clk_i     (clk_i),
                   .rst_i     (rst_i),
                   .rst_ni    (rst_ni),
                   .clk_en_i  (pwr_en[`QOSOC_PWR_GPIO_EN_BIT]),
                   .wb_cyc_i  (gpio_cyc),
                   .wb_stb_i  (gpio_stb),
                   .wb_we_i   (gpio_we),
                   .wb_sel_i  (gpio_sel),
                   .wb_adr_i  (gpio_adr),
                   .wb_dat_i  (gpio_dat_m2s),
                   .wb_dat_o  (gpio_dat_s2m),
                   .wb_ack_o  (gpio_ack),
                   .wb_err_o  (gpio_err),
                   .wb_stall_o(gpio_stall),
                   .irq_o     (irq_gpio),
                   .gpio_in   (gpio_i),
                   .gpio_out  (gpio_o),
                   .gpio_oe   (gpio_oe_o)
               );

    wire irq_uart;
    assign ser_tx_o = dbg_mode_i ? debug_ser_tx : main_ser_tx;
    qosoc_uart u_uart (
                   .clk_i     (clk_i),
                   .rst_i     (rst_i),
                   .rst_ni    (rst_ni),
                   .clk_en_i  (pwr_en[`QOSOC_PWR_UART_EN_BIT]),
                   .wb_cyc_i  (uart_cyc),
                   .wb_stb_i  (uart_stb),
                   .wb_we_i   (uart_we),
                   .wb_sel_i  (uart_sel),
                   .wb_adr_i  (uart_adr),
                   .wb_dat_i  (uart_dat_m2s),
                   .wb_dat_o  (uart_dat_s2m),
                   .wb_ack_o  (uart_ack),
                   .wb_stall_o(uart_stall),
                   .wb_err_o  (uart_err),
                   .ser_tx    (main_ser_tx),
                   .ser_rx    (ser_rx_i),
                   .irq_o     (irq_uart)
               );

    wire irq_i2c;
    qosoc_i2c u_i2c (
                  .clk_i     (clk_i),
                  .rst_i     (rst_i),
                  .rst_ni    (rst_ni),
                  .clk_en_i  (pwr_en[`QOSOC_PWR_I2C_EN_BIT]),
                  .wb_cyc_i  (i2c_cyc),
                  .wb_stb_i  (i2c_stb),
                  .wb_we_i   (i2c_we),
                  .wb_sel_i  (i2c_sel),
                  .wb_adr_i  (i2c_adr),
                  .wb_dat_i  (i2c_dat_m2s),
                  .wb_dat_o  (i2c_dat_s2m),
                  .wb_ack_o  (i2c_ack),
                  .wb_err_o  (i2c_err),
                  .wb_stall_o(i2c_stall),
                  .irq_o     (irq_i2c),
                  .scl_in    (i2c_scl_i),
                  .scl_out   (i2c_scl_o),
                  .scl_oe    (i2c_scl_oe_o),
                  .sda_in    (i2c_sda_i),
                  .sda_out   (i2c_sda_o),
                  .sda_oe    (i2c_sda_oe_o)
              );

    // PTC0/PWM0 timer/capture block.
    wire irq_pwm0;
    qosoc_ptc u_ptc0 (
                  .clk_i     (clk_i),
                  .rst_i     (rst_i),
                  .rst_ni    (rst_ni),
                  .clk_en_i  (pwr_en[`QOSOC_PWR_PWM0_EN_BIT]),
                  .wb_cyc_i  (pwm0_cyc),
                  .wb_stb_i  (pwm0_stb),
                  .wb_we_i   (pwm0_we),
                  .wb_sel_i  (pwm0_sel),
                  .wb_adr_i  (pwm0_adr),
                  .wb_dat_i  (pwm0_dat_m2s),
                  .wb_dat_o  (pwm0_dat_s2m),
                  .wb_ack_o  (pwm0_ack),
                  .wb_err_o  (pwm0_err),
                  .wb_stall_o(pwm0_stall),
                  .gate_clk_i(ptc0_gate_clk_i),
                  .capt_i    (ptc0_capt_i),
                  .pwm_o     (ptc0_pwm_o),
                  .pwm_oe    (ptc0_pwm_oe_o),
                  .irq_o     (irq_pwm0)
              );

    // RTC0 is intended as always-on timer source from a system viewpoint.
    // Power behavior still follows the PMU bit associated with TIMER0.
    wire irq_rtc0_alarm, irq_rtc0_periodic;
    qosoc_rtc_wrapper #(
        .SIM_SPEEDUP(SIM_SPEEDUP)
    ) u_rtc0 (
        .clk_i          (clk_i),
        .rst_i          (rst_i),
        .rst_ni         (rst_ni),
        .clk_en_i       (pwr_en[`QOSOC_PWR_TMR0_EN_BIT]),
        .clk_rtc_i      (clk_rtc_i),
        .wb_cyc_i       (rtc0_cyc),
        .wb_stb_i       (rtc0_stb),
        .wb_we_i        (rtc0_we),
        .wb_sel_i       (rtc0_sel),
        .wb_adr_i       (rtc0_adr),
        .wb_dat_i       (rtc0_dat_m2s),
        .wb_dat_o       (rtc0_dat_s2m),
        .wb_ack_o       (rtc0_ack),
        .wb_err_o       (rtc0_err),
        .wb_stall_o     (rtc0_stall),
        .alarm_irq_o    (irq_rtc0_alarm),
        .periodic_irq_o (irq_rtc0_periodic)
    );

    // RTC1 mirrors RTC0 functionality but uses a separate PMU enable bit.
    wire irq_rtc1_alarm, irq_rtc1_periodic;
    qosoc_rtc_wrapper #(
        .SIM_SPEEDUP(SIM_SPEEDUP)
    ) u_rtc1 (
        .clk_i          (clk_i),
        .rst_i          (rst_i),
        .rst_ni         (rst_ni),
        .clk_en_i       (pwr_en[`QOSOC_PWR_TMR1_EN_BIT]),
        .clk_rtc_i      (clk_rtc_i),
        .wb_cyc_i       (rtc1_cyc),
        .wb_stb_i       (rtc1_stb),
        .wb_we_i        (rtc1_we),
        .wb_sel_i       (rtc1_sel),
        .wb_adr_i       (rtc1_adr),
        .wb_dat_i       (rtc1_dat_m2s),
        .wb_dat_o       (rtc1_dat_s2m),
        .wb_ack_o       (rtc1_ack),
        .wb_err_o       (rtc1_err),
        .wb_stall_o     (rtc1_stall),
        .alarm_irq_o    (irq_rtc1_alarm),
        .periodic_irq_o (irq_rtc1_periodic)
    );

    wire irq_wdog;
    qosoc_watchdog u_watchdog (
                       .clk_i     (clk_i),
                       .rst_i     (rst_i),
                       .rst_ni    (rst_ni),
                       .clk_en_i  (pwr_en[`QOSOC_PWR_WDOG_EN_BIT]),
                       .wb_cyc_i  (wdog_cyc),
                       .wb_stb_i  (wdog_stb),
                       .wb_we_i   (wdog_we),
                       .wb_sel_i  (wdog_sel),
                       .wb_adr_i  (wdog_adr),
                       .wb_dat_i  (wdog_dat_m2s),
                       .wb_dat_o  (wdog_dat_s2m),
                       .wb_ack_o  (wdog_ack),
                       .wb_err_o  (wdog_err),
                       .wb_stall_o(wdog_stall),
                       .irq_o     (irq_wdog)
                   );

    wire        sysctrl_pwr_en_we;
    wire [15:0] sysctrl_pwr_en_wdata;
    wire        sysctrl_pwr_ctrl_we;
    wire [31:0] sysctrl_pwr_ctrl_wdata;
    wire [ 7:0] sysctrl_wake_mask;
    wire        sysctrl_wake_event;

    qosoc_sysctrl u_sysctrl (
                      .clk_i        (clk_i),
                      .rst_i        (rst_i),
                      .wb_cyc_i     (sys_cyc),
                      .wb_stb_i     (sys_stb),
                      .wb_we_i      (sys_we),
                      .wb_sel_i     (sys_sel),
                      .wb_adr_i     (sys_adr),
                      .wb_dat_i     (sys_dat_m2s),
                      .wb_dat_o     (sys_dat_s2m),
                      .wb_ack_o     (sys_ack),
                      .wb_err_o     (sys_err),
                      .pmu_pwr_en   (pwr_en),
                      .pwr_en_write (sysctrl_pwr_en_we),
                      .pwr_en_wdata (sysctrl_pwr_en_wdata),
                      .pwr_ctrl_write(sysctrl_pwr_ctrl_we),
                      .pwr_ctrl_wdata(sysctrl_pwr_ctrl_wdata),
                      .cpu_sleep_req(sysctrl_cpu_sleep_req),
                      .cpu_sleep_ack(cpu_sleep_ack),
                      .wake_event   (sysctrl_wake_event),
                      .wake_sources (wake_sources),
                      .wake_mask    (sysctrl_wake_mask),
                      .boot_mode_i  (boot_mode_i)
                  );

    // PMU is the single owner of power-state transitions and `pwr_en` outputs.
    qosoc_pmu u_pmu (
                  .clk_i          (clk_i),
                  .rst_i          (rst_i),
                  .wb_adr_i       (pmu_adr),
                  .wb_dat_i       (pmu_dat_m2s),
                  .wb_dat_o       (pmu_dat_s2m),
                  .wb_sel_i       (pmu_sel),
                  .wb_we_i        (pmu_we),
                  .wb_stb_i       (pmu_stb),
                  .wb_cyc_i       (pmu_cyc),
                  .wb_ack_o       (pmu_ack),
                  .pwr_en_o       (pwr_en),
                  .cpu_sleep_req_o(pmu_cpu_sleep_req),
                  .cpu_sleep_ack_i(cpu_sleep_ack),
                  .pwr_en_we      (sysctrl_pwr_en_we),
                  .pwr_en_wdata   (sysctrl_pwr_en_wdata),
                  .pwr_ctrl_we    (sysctrl_pwr_ctrl_we),
                  .pwr_ctrl_wdata (sysctrl_pwr_ctrl_wdata),
                  .wake_sources_i (wake_sources & sysctrl_wake_mask),
                  .wake_event_o   (wake_event),
                  .power_state_o  (pmu_power_state),
                  .domains_ready_o(pmu_domains_ready)
              );

    assign sysctrl_wake_event = wake_event;

    // ------------------------------------------------------------------
    // Interrupt aggregation and wake generation (Defensive boot gate)
    // ------------------------------------------------------------------
    reg [7:0] wake_sources_r;
    reg [31:0] cpu_irq_r;
    reg [9:0] boot_wait_cnt;

    // Hold interrupts/wake sources low for the first 512 system clocks after
    // reset release. This avoids false wake/IRQ pulses during initialization.
    wire boot_finished = (boot_wait_cnt >= 10'h1FF);

    always @(posedge clk_i) begin
        if (rst_i) begin
            wake_sources_r <= 8'h00;
            cpu_irq_r      <= 32'h00000000;
            boot_wait_cnt  <= 10'h000;
        end else begin
            if (!boot_finished) begin
                boot_wait_cnt <= boot_wait_cnt + 10'h001;
                wake_sources_r <= 8'h00;
                cpu_irq_r      <= 32'h00000000;
            end else begin
                // Wake source bit map [7:0]:
                // [7]=QSPI [6]=WDOG [5]=RTC1 alarm [4]=RTC0 alarm
                // [3]=PTC0 [2]=I2C [1]=UART [0]=GPIO
                wake_sources_r <= {
                    irq_qspi & 1'b1,
                    irq_wdog & 1'b1,
                    irq_rtc1_alarm & 1'b1,
                    irq_rtc0_alarm & 1'b1,
                    irq_pwm0 & 1'b1,
                    irq_i2c & 1'b1,
                    irq_uart & 1'b1,
                    irq_gpio & 1'b1
                };
                // CPU IRQ line map (Picorv32 custom IRQ encoding):
                // [11]=RTC1 periodic [10]=RTC0 periodic [9]=QSPI [8]=WDOG
                // [7]=RTC1 alarm [6]=RTC0 alarm [4]=PTC0 [2]=I2C [1]=UART [0]=GPIO
                cpu_irq_r <= {
                    20'b0,
                    irq_rtc1_periodic & 1'b1,
                    irq_rtc0_periodic & 1'b1,
                    irq_qspi & 1'b1,
                    irq_wdog & 1'b1,
                    irq_rtc1_alarm & 1'b1,
                    irq_rtc0_alarm & 1'b1,
                    1'b0,
                    irq_pwm0 & 1'b1,
                    1'b0,
                    irq_i2c & 1'b1,
                    irq_uart & 1'b1,
                    irq_gpio & 1'b1
                };
            end
        end
    end

    assign wake_sources = wake_sources_r;
    assign cpu_irq      = cpu_irq_r;

endmodule
