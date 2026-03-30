`default_nettype none

`include "qosoc_defs.vh"

module qosoc_chip_top #(
    // Power/ground pads for core
    parameter NUM_VDD_PADS  = 3,
    parameter NUM_VSS_PADS  = 2,

    // Power/ground pads for I/O ring
    parameter NUM_IOVDD_PADS = 2,
    parameter NUM_IOVSS_PADS = 2
)(
    `ifdef USE_POWER_PINS
    inout wire IOVDD,
    inout wire IOVSS,
    inout wire VDD,
    inout wire VSS,
    `endif

    // Clock & reset
    inout wire        clk_PAD,
    inout wire        rst_n_PAD,

    // UART
    inout wire        uart_rx_PAD,
    inout wire        uart_tx_PAD,

    // I2C
    inout wire        i2c_scl_PAD,
    inout wire        i2c_sda_PAD,

    // PWM / Timer capture (bidirectional)
    inout wire        pwm0_PAD,

    // QSPI Flash
    inout wire        qspi_sck_PAD,
    inout wire        qspi_cs_n_PAD,
    inout wire [3:0]  qspi_dat_PAD,

    // GPIO (8-bit bidirectional)
    // gpio_PAD[4] doubles as BOOT_MODE strap.
    // gpio_PAD[7] doubles as DBG_MODE strap.
    inout wire [7:0]  gpio_PAD,

    // Trap status (output)
    inout wire        trap_PAD,

    // RTC clock (input)
    inout wire        clk_rtc_PAD
);

    // -------------------------------------------------------------------------
    // Internal signals: PAD2CORE (inputs), CORE2PAD (outputs), OE (enables)
    // -------------------------------------------------------------------------

    // Clock & reset
    wire        clk_PAD2CORE;
    wire        rst_n_PAD2CORE;

    // UART
    wire        uart_rx_PAD2CORE;
    wire        uart_tx_CORE2PAD;

    // I2C SCL
    wire        i2c_scl_CORE2PAD;
    wire        i2c_scl_CORE2PAD_OE;
    wire        i2c_scl_PAD2CORE;

    // I2C SDA
    wire        i2c_sda_CORE2PAD;
    wire        i2c_sda_CORE2PAD_OE;
    wire        i2c_sda_PAD2CORE;

    // PWM0 / PTC0 
    wire        pwm0_CORE2PAD;
    wire        pwm0_CORE2PAD_OE;
    wire        pwm0_PAD2CORE;    

    // QSPI Flash
    wire        qspi_sck_CORE2PAD;
    wire        qspi_cs_n_CORE2PAD;
    wire [3:0]  qspi_dat_CORE2PAD;
    wire [3:0]  qspi_dat_CORE2PAD_OE;
    wire [3:0]  qspi_dat_PAD2CORE;

    // GPIO (raw pad signals)
    wire [7:0]  gpio_CORE2PAD;
    wire [7:0]  gpio_CORE2PAD_OE;
    wire [7:0]  gpio_PAD2CORE;

    // Trap & RTC
    wire        trap_CORE2PAD;
    wire        clk_rtc_PAD2CORE;
    
    reg  boot_mode_latched;
    reg  dbg_mode_latched;
    reg  strap_sampled;
    wire dbg_mode_session;

    always @(posedge clk_PAD2CORE or negedge rst_n_PAD2CORE) begin
        if (!rst_n_PAD2CORE) begin
            boot_mode_latched <= 1'b0;
            dbg_mode_latched  <= 1'b0;
            strap_sampled     <= 1'b0;
        end else if (!strap_sampled) begin
            boot_mode_latched <= gpio_PAD2CORE[4];
            dbg_mode_latched  <= gpio_PAD2CORE[7];
            strap_sampled     <= 1'b1;
        end
    end

    assign dbg_mode_session = strap_sampled ? dbg_mode_latched : gpio_PAD2CORE[7];

    wire gpio_pad4_oe = strap_sampled ? 1'b0 : gpio_CORE2PAD_OE[4];
    wire gpio_pad7_c2p = dbg_mode_session ? 1'b0 : gpio_CORE2PAD[7];
    wire gpio_pad7_oe  = dbg_mode_session ? 1'b0 : gpio_CORE2PAD_OE[7];
    wire [7:0] gpio_core_i;
    assign gpio_core_i[6:0] = gpio_PAD2CORE[6:0];
    assign gpio_core_i[7]   = dbg_mode_session ? 1'b0 : gpio_PAD2CORE[7];

    // =========================================================================
    // Power/Ground Pad Instances
    // =========================================================================

    generate
    for (genvar i = 0; i < NUM_IOVDD_PADS; i++) begin : iovdd_pads
        (* keep *)
        sg13g2_IOPadIOVdd iovdd_pad (
            `ifdef USE_POWER_PINS
            .iovdd (IOVDD),
            .iovss (IOVSS),
            .vdd   (VDD),
            .vss   (VSS)
            `endif
        );
    end

    for (genvar i = 0; i < NUM_IOVSS_PADS; i++) begin : iovss_pads
        (* keep *)
        sg13g2_IOPadIOVss iovss_pad (
            `ifdef USE_POWER_PINS
            .iovdd (IOVDD),
            .iovss (IOVSS),
            .vdd   (VDD),
            .vss   (VSS)
            `endif
        );
    end

    for (genvar i = 0; i < NUM_VDD_PADS; i++) begin : vdd_pads
        (* keep *)
        sg13g2_IOPadVdd vdd_pad (
            `ifdef USE_POWER_PINS
            .iovdd (IOVDD),
            .iovss (IOVSS),
            .vdd   (VDD),
            .vss   (VSS)
            `endif
        );
    end

    for (genvar i = 0; i < NUM_VSS_PADS; i++) begin : vss_pads
        (* keep *)
        sg13g2_IOPadVss vss_pad (
            `ifdef USE_POWER_PINS
            .iovdd (IOVDD),
            .iovss (IOVSS),
            .vdd   (VDD),
            .vss   (VSS)
            `endif
        );
    end
    endgenerate

    // =========================================================================
    // Signal I/O Pad Instances
    // =========================================================================

    // --- Clock (input) ---
    sg13g2_IOPadIn u_pad_clk (
        `ifdef USE_POWER_PINS
        .iovdd (IOVDD),
        .iovss (IOVSS),
        .vdd   (VDD),
        .vss   (VSS),
        `endif
        .pad (clk_PAD),
        .p2c (clk_PAD2CORE)
    );

    // --- Reset (active-low input) ---
    sg13g2_IOPadIn u_pad_rst_n (
        `ifdef USE_POWER_PINS
        .iovdd (IOVDD),
        .iovss (IOVSS),
        .vdd   (VDD),
        .vss   (VSS),
        `endif
        .pad (rst_n_PAD),
        .p2c (rst_n_PAD2CORE)
    );

    // --- UART RX (input) ---
    sg13g2_IOPadIn u_pad_uart_rx (
        `ifdef USE_POWER_PINS
        .iovdd (IOVDD),
        .iovss (IOVSS),
        .vdd   (VDD),
        .vss   (VSS),
        `endif
        .pad (uart_rx_PAD),
        .p2c (uart_rx_PAD2CORE)
    );

    // --- UART TX (output) ---
    sg13g2_IOPadOut16mA u_pad_uart_tx (
        `ifdef USE_POWER_PINS
        .iovdd (IOVDD),
        .iovss (IOVSS),
        .vdd   (VDD),
        .vss   (VSS),
        `endif
        .pad (uart_tx_PAD),
        .c2p (uart_tx_CORE2PAD)
    );

    // --- I2C SCL (bidirectional) ---
    sg13g2_IOPadInOut16mA u_pad_i2c_scl (
        `ifdef USE_POWER_PINS
        .iovdd  (IOVDD),
        .iovss  (IOVSS),
        .vdd    (VDD),
        .vss    (VSS),
        `endif
        .pad    (i2c_scl_PAD),
        .c2p    (i2c_scl_CORE2PAD),
        .c2p_en (i2c_scl_CORE2PAD_OE),
        .p2c    (i2c_scl_PAD2CORE)
    );

    // --- I2C SDA (bidirectional) ---
    sg13g2_IOPadInOut16mA u_pad_i2c_sda (
        `ifdef USE_POWER_PINS
        .iovdd  (IOVDD),
        .iovss  (IOVSS),
        .vdd    (VDD),
        .vss    (VSS),
        `endif
        .pad    (i2c_sda_PAD),
        .c2p    (i2c_sda_CORE2PAD),
        .c2p_en (i2c_sda_CORE2PAD_OE),
        .p2c    (i2c_sda_PAD2CORE)
    );

    // --- PWM0 / PTC0 capture (bidirectional) ---
    sg13g2_IOPadInOut16mA u_pad_pwm0 (
        `ifdef USE_POWER_PINS
        .iovdd  (IOVDD),
        .iovss  (IOVSS),
        .vdd    (VDD),
        .vss    (VSS),
        `endif
        .pad    (pwm0_PAD),
        .c2p    (pwm0_CORE2PAD),
        .c2p_en (pwm0_CORE2PAD_OE),
        .p2c    (pwm0_PAD2CORE)
    );

    // --- QSPI SCK (output) ---
    sg13g2_IOPadOut16mA u_pad_qspi_sck (
        `ifdef USE_POWER_PINS
        .iovdd (IOVDD),
        .iovss (IOVSS),
        .vdd   (VDD),
        .vss   (VSS),
        `endif
        .pad (qspi_sck_PAD),
        .c2p (qspi_sck_CORE2PAD)
    );

    // --- QSPI CS_N (output) ---
    sg13g2_IOPadOut16mA u_pad_qspi_cs_n (
        `ifdef USE_POWER_PINS
        .iovdd (IOVDD),
        .iovss (IOVSS),
        .vdd   (VDD),
        .vss   (VSS),
        `endif
        .pad (qspi_cs_n_PAD),
        .c2p (qspi_cs_n_CORE2PAD)
    );

    // --- QSPI Data [3:0] (bidirectional) ---
    generate
    for (genvar i = 0; i < 4; i++) begin : qspi_dat_pads
        sg13g2_IOPadInOut16mA qspi_dat_pad (
            `ifdef USE_POWER_PINS
            .iovdd  (IOVDD),
            .iovss  (IOVSS),
            .vdd    (VDD),
            .vss    (VSS),
            `endif
            .pad    (qspi_dat_PAD[i]),
            .c2p    (qspi_dat_CORE2PAD[i]),
            .c2p_en (qspi_dat_CORE2PAD_OE[i]),
            .p2c    (qspi_dat_PAD2CORE[i])
        );
    end
    endgenerate

    sg13g2_IOPadInOut16mA u_pad_gpio_0 (
        `ifdef USE_POWER_PINS
        .iovdd  (IOVDD), .iovss  (IOVSS), .vdd    (VDD), .vss    (VSS),
        `endif
        .pad    (gpio_PAD[0]),
        .c2p    (gpio_CORE2PAD[0]),
        .c2p_en (gpio_CORE2PAD_OE[0]),
        .p2c    (gpio_PAD2CORE[0])
    );

    sg13g2_IOPadInOut16mA u_pad_gpio_1 (
        `ifdef USE_POWER_PINS
        .iovdd  (IOVDD), .iovss  (IOVSS), .vdd    (VDD), .vss    (VSS),
        `endif
        .pad    (gpio_PAD[1]),
        .c2p    (gpio_CORE2PAD[1]),
        .c2p_en (gpio_CORE2PAD_OE[1]),
        .p2c    (gpio_PAD2CORE[1])
    );

    sg13g2_IOPadInOut16mA u_pad_gpio_2 (
        `ifdef USE_POWER_PINS
        .iovdd  (IOVDD), .iovss  (IOVSS), .vdd    (VDD), .vss    (VSS),
        `endif
        .pad    (gpio_PAD[2]),
        .c2p    (gpio_CORE2PAD[2]),
        .c2p_en (gpio_CORE2PAD_OE[2]),
        .p2c    (gpio_PAD2CORE[2])
    );

    sg13g2_IOPadInOut16mA u_pad_gpio_3 (
        `ifdef USE_POWER_PINS
        .iovdd  (IOVDD), .iovss  (IOVSS), .vdd    (VDD), .vss    (VSS),
        `endif
        .pad    (gpio_PAD[3]),
        .c2p    (gpio_CORE2PAD[3]),
        .c2p_en (gpio_CORE2PAD_OE[3]),
        .p2c    (gpio_PAD2CORE[3])
    );

    sg13g2_IOPadInOut16mA u_pad_gpio_4 (
        `ifdef USE_POWER_PINS
        .iovdd  (IOVDD), .iovss  (IOVSS), .vdd    (VDD), .vss    (VSS),
        `endif
        .pad    (gpio_PAD[4]),
        .c2p    (gpio_CORE2PAD[4]),
        .c2p_en (gpio_pad4_oe),          // locked to 0 after strap_sampled
        .p2c    (gpio_PAD2CORE[4])
    );

    sg13g2_IOPadInOut16mA u_pad_gpio_5 (
        `ifdef USE_POWER_PINS
        .iovdd  (IOVDD), .iovss  (IOVSS), .vdd    (VDD), .vss    (VSS),
        `endif
        .pad    (gpio_PAD[5]),
        .c2p    (gpio_CORE2PAD[5]),
        .c2p_en (gpio_CORE2PAD_OE[5]),
        .p2c    (gpio_PAD2CORE[5])
    );

    sg13g2_IOPadInOut16mA u_pad_gpio_6 (
        `ifdef USE_POWER_PINS
        .iovdd  (IOVDD), .iovss  (IOVSS), .vdd    (VDD), .vss    (VSS),
        `endif
        .pad    (gpio_PAD[6]),
        .c2p    (gpio_CORE2PAD[6]),
        .c2p_en (gpio_CORE2PAD_OE[6]),
        .p2c    (gpio_PAD2CORE[6])
    );

    sg13g2_IOPadInOut16mA u_pad_gpio_7 (
        `ifdef USE_POWER_PINS
        .iovdd  (IOVDD), .iovss  (IOVSS), .vdd    (VDD), .vss    (VSS),
        `endif
        .pad    (gpio_PAD[7]),
        .c2p    (gpio_pad7_c2p),         // 0 when dbg_mode_session
        .c2p_en (gpio_pad7_oe),          // 0 when dbg_mode_session
        .p2c    (gpio_PAD2CORE[7])       // masked in gpio_core_i[7] below
    );

    // --- Trap status (output) ---
    sg13g2_IOPadOut16mA u_pad_trap (
        `ifdef USE_POWER_PINS
        .iovdd (IOVDD),
        .iovss (IOVSS),
        .vdd   (VDD),
        .vss   (VSS),
        `endif
        .pad (trap_PAD),
        .c2p (trap_CORE2PAD)
    );

    // --- RTC Clock (input) ---
    sg13g2_IOPadIn u_pad_clk_rtc (
        `ifdef USE_POWER_PINS
        .iovdd (IOVDD),
        .iovss (IOVSS),
        .vdd   (VDD),
        .vss   (VSS),
        `endif
        .pad (clk_rtc_PAD),
        .p2c (clk_rtc_PAD2CORE)
    );

    // =========================================================================
    // QoSoC Core Instance
    // =========================================================================

    (* keep *) qosoc u_qosoc_core (
        .clk_i           (clk_PAD2CORE),
        .rst_ni          (rst_n_PAD2CORE),

        // UART
        .ser_rx_i        (uart_rx_PAD2CORE),
        .ser_tx_o        (uart_tx_CORE2PAD),

        // I2C
        .i2c_scl_o       (i2c_scl_CORE2PAD),
        .i2c_scl_oe_o    (i2c_scl_CORE2PAD_OE),
        .i2c_scl_i       (i2c_scl_PAD2CORE),
        .i2c_sda_o       (i2c_sda_CORE2PAD),
        .i2c_sda_oe_o    (i2c_sda_CORE2PAD_OE),
        .i2c_sda_i       (i2c_sda_PAD2CORE),

        .gpio_i          (gpio_core_i),
        .gpio_o          (gpio_CORE2PAD),
        .gpio_oe_o       (gpio_CORE2PAD_OE),

        .boot_mode_i     (boot_mode_latched),
        .dbg_mode_i      (dbg_mode_session),

        // PTC0 / PWM
        .ptc0_gate_clk_i (1'b0),
        .ptc0_capt_i     (pwm0_PAD2CORE),
        .ptc0_pwm_o      (pwm0_CORE2PAD),
        .ptc0_pwm_oe_o   (pwm0_CORE2PAD_OE),

        // QSPI Flash
        .qspi_sck_o      (qspi_sck_CORE2PAD),
        .qspi_cs_n_o     (qspi_cs_n_CORE2PAD),
        .qspi_dat_o      (qspi_dat_CORE2PAD),
        .qspi_dat_oe_o   (qspi_dat_CORE2PAD_OE),
        .qspi_dat_i      (qspi_dat_PAD2CORE),
        .qspi_dat_mode_o (),

        // RTC Clock
        .clk_rtc_i       (clk_rtc_PAD2CORE),


        // Status
        .trap_o          (trap_CORE2PAD)
    );

endmodule

`default_nettype wire