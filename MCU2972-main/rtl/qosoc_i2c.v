// =============================================================================
// QoSoC I2C Wrapper
// =============================================================================
//
// OVERVIEW:
// Wraps the OpenCores I2C master with QoSoC clock/power control and Wishbone
// integration. Converts SoC-level enables to a gated local I2C clock.
//
// INTERFACE NOTES:
// - External pins use separate input, output, and output-enable signals.
// - Wishbone register decode remains inside the wrapped I2C core.
// - `irq_o` is forwarded from the wrapped controller interrupt output.
//
// =============================================================================
`include "qosoc_defs.vh"
`include "i2c_master_defines.v"

module qosoc_i2c (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        rst_ni,
    input  wire        clk_en_i,

    // Wishbone slave
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
    output wire        irq_o,

    // I2C pins
    input  wire        scl_in,
    output wire        scl_out,
    output wire        scl_oe,
    input  wire        sda_in,
    output wire        sda_out,
    output wire        sda_oe
);
    // Local I2C clock follows peripheral power intent and remains forced-on in scan.
    wire clk_i2c;
    qosoc_clk_gate u_clk_gate (
        .clk_in      (clk_i),
        .rst_n       (rst_ni),
        .enable      (clk_en_i),
        .clk_out     (clk_i2c)
    );

    // OpenCores i2c_master_top expects compact register addressing.
    // QoSoC maps CSR word addresses [4:2] to these internal register indices.
    wire access = clk_en_i && wb_cyc_i && wb_stb_i;
    wire [2:0] adr = wb_adr_i[4:2];

    wire [7:0] core_dat_o;
    wire       core_ack;
    wire       core_irq;

    wire scl_oe_raw, sda_oe_raw;

    // Keep the wrapped core dormant while power-gated by suppressing CYC/STB.
    i2c_master_top #(
        .ARST_LVL(1'b0)
    ) u_i2c (
        .wb_clk_i      (clk_i2c),
        .wb_rst_i      (rst_i),
        .arst_i        (~rst_i),
        .wb_adr_i      (adr),
        .wb_dat_i      (wb_dat_i[7:0]),
        .wb_dat_o      (core_dat_o),
        .wb_we_i       (wb_we_i),
        .wb_stb_i      (access),
        .wb_cyc_i      (access),
        .wb_ack_o      (core_ack),
        .wb_inta_o     (core_irq),
        .scl_pad_i     (scl_in),
        .scl_pad_o     (scl_out),
        .scl_padoen_o  (scl_oe_raw),
        .sda_pad_i     (sda_in),
        .sda_pad_o     (sda_out),
        .sda_padoen_o  (sda_oe_raw)
    );

    // IHP SG13G2 pad cells use active-high output enables (c2p_en).
    // The OpenCores I2C block provides active-low padoen signals.
    assign scl_oe = ~scl_oe_raw;
    assign sda_oe = ~sda_oe_raw;

    // Power-off behavior mirrors other wrappers:
    // return ACK+zero data so masters complete the cycle cleanly.
    assign wb_dat_o   = clk_en_i ? {24'h0, core_dat_o} : 32'h0000_0000;
    assign wb_ack_o   = clk_en_i ? core_ack : (wb_cyc_i & wb_stb_i);
    assign wb_stall_o = 1'b0;
    assign wb_err_o   = 1'b0;
    assign irq_o      = clk_en_i ? core_irq : 1'b0;
endmodule
