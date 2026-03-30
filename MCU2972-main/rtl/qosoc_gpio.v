// =============================================================================
// QoSoC GPIO Wrapper
// =============================================================================
//
// OVERVIEW:
// Adapts the OpenCores GPIO block to the QoSoC bus/power conventions. Adds
// local clock gating, exposes Wishbone signals, and exports GPIO interrupt.
//
// INTERFACE NOTES:
// - GPIO width is 8 bits at this wrapper boundary.
// - Clock gating is controlled by `clk_en_i` with `scan_mode_i` override.
// - Wishbone addressing is passed through directly to the GPIO core.
//
// =============================================================================
`include "qosoc_defs.vh"
`include "gpio_defines.v"

module qosoc_gpio (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        rst_ni,
    input  wire        clk_en_i,

    // Wishbone slave
    input  wire        wb_cyc_i,
    input  wire        wb_stb_i,
    input  wire        wb_we_i,
    input  wire [ 3:0] wb_sel_i,
    input  wire [31:0] wb_adr_i,
    input  wire [31:0] wb_dat_i,
    output wire [31:0] wb_dat_o,
    output wire        wb_ack_o,
    output wire        wb_err_o,
    output wire        wb_stall_o,
    output wire        irq_o,

    // GPIO pads - 8 pins
    input  wire [7:0]  gpio_in,
    output wire [7:0]  gpio_out,
    output wire [7:0]  gpio_oe
);
    // Local peripheral clock is gated by PMU power intent and opened in scan.
    // The wrapped OpenCores GPIO still sees a clean clock edge stream when active.
    wire clk_gpio;
    qosoc_clk_gate u_clk_gate (
        .clk_in      (clk_i),
        .rst_n       (rst_ni),
        .enable      (clk_en_i),
        .clk_out     (clk_gpio)
    );

    assign wb_stall_o = 1'b0;

    // Internal GPIO signals.
    wire [7:0] pad_out;
    wire [7:0] pad_oe;
    wire [31:0] gpio_dat_int;
    wire        gpio_ack_int;
    wire        gpio_err_int;
    wire        gpio_irq_int;

`ifdef GPIO_AUX_IMPLEMENT
    wire [`GPIO_IOS-1:0] gpio_aux_in = {`GPIO_IOS{1'b0}};
`endif

`ifdef GPIO_CLKPAD
    wire gpio_clk_pad = 1'b0;
`endif

    // Gate bus request strobes when the peripheral is off.
    // This keeps the wrapped block quiescent and avoids toggling from stray cycles.
    gpio_top u_gpio (
        .wb_clk_i   (clk_gpio),
        .wb_rst_i   (rst_i),
        .wb_cyc_i   (clk_en_i ? wb_cyc_i : 1'b0),
        .wb_adr_i   (wb_adr_i[`GPIO_ADDRHH:0]),
        .wb_dat_i   (wb_dat_i),
        .wb_sel_i   (wb_sel_i),
        .wb_we_i    (wb_we_i),
        .wb_stb_i   (clk_en_i ? wb_stb_i : 1'b0),
        .wb_dat_o   (gpio_dat_int),
        .wb_ack_o   (gpio_ack_int),
        .wb_err_o   (gpio_err_int),
        .wb_inta_o  (gpio_irq_int),
`ifdef GPIO_AUX_IMPLEMENT
        .aux_i      (gpio_aux_in),
`endif
        .ext_pad_i  (gpio_in),
        .ext_pad_o  (pad_out),
        .ext_padoe_o(pad_oe)
`ifdef GPIO_CLKPAD
        , .clk_pad_i (gpio_clk_pad)
`endif
    );

    // Power-off behavior:
    // - Reads return zero.
    // - A transfer still gets ACKed immediately so the system bus cannot hang.
    // - IRQ is forced low while the domain is disabled.
    assign wb_dat_o = clk_en_i ? gpio_dat_int : 32'h0000_0000;
    assign wb_ack_o = clk_en_i ? gpio_ack_int : (wb_cyc_i & wb_stb_i);
    assign wb_err_o = clk_en_i ? gpio_err_int : 1'b0;
    assign irq_o    = clk_en_i ? gpio_irq_int : 1'b0;

    assign gpio_out = pad_out;
    assign gpio_oe  = pad_oe;
endmodule
