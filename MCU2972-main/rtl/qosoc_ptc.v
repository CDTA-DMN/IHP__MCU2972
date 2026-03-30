// =============================================================================
// QoSoC PTC Wrapper
// =============================================================================
//
// OVERVIEW:
// Wraps the OpenCores PTC (PWM/Timer/Counter) block for QoSoC. Adds local
// clock gating and exposes a Wishbone slave interface plus PWM/capture pins.
//
// INTERFACE NOTES:
// - Address slicing for the wrapped core is derived from `PTC_ADDRHH`.
// - `irq_o` is forwarded from the wrapped PTC interrupt output.
// - Clock gate follows `clk_en_i` with scan override through `scan_mode_i`.
//
// =============================================================================
`include "qosoc_defs.vh"
`include "ptc_defines.v"

module qosoc_ptc (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        rst_ni,
    input  wire        clk_en_i,

    // Wishbone interface
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

    // External pins
    input  wire        gate_clk_i,
    input  wire        capt_i,
    output wire        pwm_o,
    output wire        pwm_oe,

    // Interrupt
    output wire        irq_o
);
    localparam integer AW = `PTC_ADDRHH + 1;

    // Clock gate is instantiated for consistency with other wrappers.
    // The current integration keeps ptc_top on `clk_i` (see note below).
    wire clk_ptc;
    qosoc_clk_gate u_clk_gate (
        .clk_in      (clk_i),
        .rst_n       (rst_ni),
        .enable      (clk_en_i),
        .clk_out     (clk_ptc)
    );

    wire        ptc_cyc  = clk_en_i ? wb_cyc_i : 1'b0;
    wire        ptc_stb  = clk_en_i ? wb_stb_i : 1'b0;
    // ptc_top uses a small local register map.
    // Keep only low address bits so each CSR window starts at offset 0 internally.
    wire [AW-1:0] ptc_adr = {{(AW-5){1'b0}}, wb_adr_i[4:0]};

    wire [31:0] ptc_dat_o;
    wire        ptc_ack;
    wire        ptc_err;
    wire        pwm_pad;
    wire        pwm_oe_pad;

    wire        ptc_irq;

    // Integration policy for PTC:
    // - Use ungated `clk_i` for the legacy block to keep reset/startup deterministic.
    // - Enforce power gating at the bus boundary by suppressing CYC/STB and outputs.
    ptc_top u_ptc (
        .wb_clk_i (clk_i),
        .wb_rst_i (rst_i),
        .wb_rst_n_i (rst_ni),
        .wb_cyc_i (ptc_cyc),
        .wb_adr_i (ptc_adr),
        .wb_dat_i (wb_dat_i),
        .wb_sel_i (wb_sel_i),
        .wb_we_i  (wb_we_i),
        .wb_stb_i (ptc_stb),
        .wb_dat_o (ptc_dat_o),
        .wb_ack_o (ptc_ack),
        .wb_err_o (ptc_err),
        .wb_inta_o(ptc_irq),
        .gate_clk_pad_i (gate_clk_i),
        .capt_pad_i     (capt_i),
        .pwm_pad_o      (pwm_pad),
        .oen_padoen_o   (pwm_oe_pad)
    );

    // While disabled, terminate accesses immediately and force outputs inactive.
    assign wb_dat_o   = clk_en_i ? ptc_dat_o : 32'h0000_0000;
    assign wb_ack_o   = clk_en_i ? ptc_ack : (wb_cyc_i & wb_stb_i);
    assign wb_err_o   = clk_en_i ? ptc_err : 1'b0;
    assign wb_stall_o = 1'b0;
    assign pwm_o      = clk_en_i ? pwm_pad : 1'b0;
    // ptc_top.oen_padoen_o is active-low; sg13g2 pad c2p_en is active-high.
    assign pwm_oe     = clk_en_i ? ~pwm_oe_pad : 1'b0;
    assign irq_o      = clk_en_i ? ptc_irq : 1'b0;
endmodule
