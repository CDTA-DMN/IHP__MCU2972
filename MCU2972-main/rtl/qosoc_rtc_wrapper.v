// =============================================================================
// QoSoC RTC Wrapper
// =============================================================================
//
// OVERVIEW:
// Bridges `qosoc_rtc` into the SoC peripheral fabric. Selects RTC clock source
// for normal operation versus accelerated simulation and forwards Wishbone
// transactions to the RTC core.
//
// NOTES:
// - `SIM_SPEEDUP=1` routes `clk_i` as RTC clock for faster simulation progress.
// - IRQ outputs are qualified with clock-enable and reset status.
//
// =============================================================================

module qosoc_rtc_wrapper #(
    parameter SIM_SPEEDUP = 0
) (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        rst_ni,     
    input  wire        clk_en_i,
    input  wire        clk_rtc_i, 

    // Wishbone interface (single clock domain)
    input  wire        wb_cyc_i,
    input  wire        wb_stb_i,
    input  wire        wb_we_i,
    input  wire [3:0]  wb_sel_i,
    input  wire [31:0] wb_adr_i,
    input  wire [31:0] wb_dat_i,
    output wire [31:0] wb_dat_o,
    output wire        wb_ack_o,
    output wire        wb_err_o,
    output wire        wb_stall_o,

    output wire        alarm_irq_o,
    output wire        periodic_irq_o
);
    wire rtc_clock = (SIM_SPEEDUP == 1) ? clk_i : clk_rtc_i;

    // Raw RTC interrupt outputs before wrapper-level masking.
    wire alarm_irq_raw, periodic_irq_raw;
    
    qosoc_rtc #(
        .SIM_SPEEDUP(SIM_SPEEDUP)
    ) u_rtc (
        .clk_i          (clk_i),
        .rtc_clk_i      (rtc_clock),
        .rst_i          (rst_i),
        .rst_ni         (rst_ni),
        .bus_en_i       (clk_en_i),
        .aon_en_i       (1'b1),
        .iso_en_i       (1'b0),
        .wb_cyc_i       (wb_cyc_i),
        .wb_stb_i       (wb_stb_i),
        .wb_we_i        (wb_we_i),
        .wb_sel_i       (wb_sel_i),
        .wb_adr_i       (wb_adr_i),
        .wb_dat_i       (wb_dat_i),
        .wb_dat_o       (wb_dat_o),
        .wb_ack_o       (wb_ack_o),
        .wb_err_o       (wb_err_o),
        .wb_stall_o     (wb_stall_o),
        .alarm_irq_o    (alarm_irq_raw),
        .periodic_irq_o (periodic_irq_raw)
    );
    assign alarm_irq_o = (alarm_irq_raw & clk_en_i) & (~rst_i);
    assign periodic_irq_o = (periodic_irq_raw & clk_en_i) & (~rst_i);

endmodule
