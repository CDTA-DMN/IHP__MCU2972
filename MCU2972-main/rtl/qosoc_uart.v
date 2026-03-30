// =============================================================================
// QoSoC UART Wrapper
// =============================================================================
//
// OVERVIEW:
// Integrates the `wbuart` core into the QoSoC bus and power framework. Exposes
// Wishbone slave signals, serial TX/RX pins, and a consolidated UART interrupt.
//
// NOTES:
// - Register address decode uses `wb_adr_i[3:2]` for local UART register select.
// - Core clock is not locally gated; access is controlled at SoC level.
// - Initial setup value is a safe default and can be overwritten by firmware.
//
// =============================================================================
`include "qosoc_defs.vh"

module qosoc_uart (
    input wire clk_i,
    input wire rst_i,
    input wire rst_ni,
    input wire clk_en_i,

    // Wishbone slave interface
    input  wire        wb_cyc_i,
    input  wire        wb_stb_i,
    input  wire        wb_we_i,
    input  wire [ 3:0] wb_sel_i,
    input  wire [31:0] wb_adr_i,
    input  wire [31:0] wb_dat_i,
    output wire [31:0] wb_dat_o,
    output reg         wb_ack_o,
    output wire        wb_stall_o,
    output wire        wb_err_o,

    // UART pins
    output wire ser_tx,
    input  wire ser_rx,

    // Interrupt
    output wire irq_o
);
  // wbuart uses a compact 4-register map selected by word address [3:2].
  wire [1:0] uart_addr = wb_adr_i[3:2];

  // The UART core is intentionally clocked from ungated `clk_i` so its internal
  // timing, FIFOs, and Wishbone response logic remain consistent.
  // Power policy is applied at the wrapper outputs and request qualification.
  wire [31:0] wb_dat_int;
  wire        wb_ack_int, wb_stall_int;
  wire uart_rx_int, uart_tx_int, uart_rxfifo_int, uart_txfifo_int;

  wbuart #(
      .INITIAL_SETUP                (31'd139),  
      .LGFLEN                       (4),        // 16-entry FIFOs
      .HARDWARE_FLOW_CONTROL_PRESENT(1'b0)
  ) u_wbuart (
      .clk_i            (clk_i),
      .rst_i            (rst_i),
      .i_wb_cyc         (wb_cyc_i),
      .i_wb_stb         (wb_stb_i),
      .i_wb_we          (wb_we_i),
      .i_wb_addr        (uart_addr),
      .i_wb_data        (wb_dat_i),
      .o_wb_ack         (wb_ack_int),
      .o_wb_stall       (wb_stall_int),
      .o_wb_data        (wb_dat_int),
      .i_uart_rx        (ser_rx),
      .o_uart_tx        (ser_tx),
      .i_cts_n          (1'b0),
      .o_rts_n          (),
      .o_uart_rx_int    (uart_rx_int),
      .o_uart_tx_int    (uart_tx_int),
      .o_uart_rxfifo_int(uart_rxfifo_int),
      .o_uart_txfifo_int(uart_txfifo_int)
  );
  
  // If UART power is disabled, data reads back as 0.
  // Data output is combinational (gated by clk_en_i) — safe because wb_dat_int
  // from wbuart is a registered output never driven X after rst_i.
  assign wb_dat_o   = clk_en_i ? wb_dat_int   : 32'h0;
  assign wb_stall_o = clk_en_i ? wb_stall_int : 1'b0;
  assign wb_err_o   = 1'b0;

  // Registered ACK — matches RTC module's bus interface pattern.
  // Replaces the previous assign-based ack which was a combinational wire that
  // could carry X from wbuart's sync-reset regs or pwr_en before first clock edge.
  //
  // RTC pattern:
  //   wire access = cyc && stb && en
  //   output reg wb_ack_o — cleared on rst_i
  //   wb_ack_r — prevents double-ACK within same bus cycle
  reg wb_ack_r;

  wire uart_access = wb_cyc_i && wb_stb_i;

  always @(posedge clk_i) begin
    if (rst_i) begin
      wb_ack_o <= 1'b0;
      wb_ack_r <= 1'b0;
    end else begin
      if (clk_en_i) begin
        // Normal mode: forward the wbuart core's registered ack.
        // wb_ack_int from wbuart is a registered output, so no X risk here.
        wb_ack_o <= wb_ack_int && !wb_ack_r;
        wb_ack_r <= wb_ack_int;
      end else if (uart_access && !wb_ack_r) begin
        // Power-off mode: immediately ACK with zero data so the bus master
        // does not hang. Mirrors the RTC's iso/power-off ACK handling.
        wb_ack_o <= 1'b1;
        wb_ack_r <= 1'b1;
      end else begin
        wb_ack_o <= 1'b0;
      end

      // Clear tracking when bus cycle ends
      if (!uart_access) begin
        wb_ack_o <= 1'b0;
        wb_ack_r <= 1'b0;
      end
    end
  end

  // Interrupt policy: RX-ready IRQ, gated by power and reset.
  // !rst_i guard matches RTC's `assign alarm_irq_o = !rst_i && ...` pattern.
  assign irq_o = !rst_i && clk_en_i && uart_rx_int;
endmodule