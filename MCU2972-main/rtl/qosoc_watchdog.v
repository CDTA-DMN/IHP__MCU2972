// =============================================================================
// QoSoC Watchdog Timer
// =============================================================================
//
// OVERVIEW:
// Wishbone-programmable watchdog with timeout flag, optional IRQ generation,
// and optional auto-reload behavior.
//
// BUS/POWER NOTES:
// - Register accesses are qualified by `clk_en_i`.
// - When `clk_en_i` is low, wrapper still returns ACK to avoid bus hangs.
// - STATUS register bit[0] is write-1-to-clear for timeout flag.
//
// REGISTER MAP (word offsets):
// 0x0 LOAD   - Reload value and current counter preset.
// 0x1 CTRL   - [0]=enable, [1]=irq_enable, [2]=auto_reload, [3]=kick/reload.
// 0x2 STATUS - [0]=timeout_flag (W1C).
//
// =============================================================================
`include "qosoc_defs.vh"

module qosoc_watchdog (
    input wire clk_i,
    input wire rst_i,
    input wire rst_ni,
    input wire clk_en_i,

    // Wishbone interface
    input  wire        wb_cyc_i,
    input  wire        wb_stb_i,
    input  wire        wb_we_i,
    input  wire [ 3:0] wb_sel_i,
    input  wire [31:0] wb_adr_i,
    input  wire [31:0] wb_dat_i,
    output reg  [31:0] wb_dat_o,
    output reg         wb_ack_o,
    output wire        wb_err_o,
    output wire        wb_stall_o,

    output wire irq_o
);
  localparam REG_LOAD   = 3'b000;
  localparam REG_CTRL   = 3'b001;
  localparam REG_STATUS = 3'b010;

  reg [31:0] load_value;
  reg [31:0] counter;
  reg        enable;
  reg        irq_enable;
  reg        auto_reload;
  reg        timeout_flag;

  assign wb_err_o   = 1'b0;
  assign wb_stall_o = 1'b0;
  assign irq_o      = (clk_en_i & (~rst_i)) & (timeout_flag & irq_enable);

  // Access decode uses word-aligned address bits [4:2].
  wire access = clk_en_i && wb_cyc_i && wb_stb_i;
  wire write = access && wb_we_i;
  wire read = access && !wb_we_i;
  wire [2:0] reg_sel = wb_adr_i[4:2];

  // Reserved debug hook for temporary waveform/console instrumentation.
  // Kept as a no-op block so debug prints can be re-enabled quickly if needed.
  always @(posedge clk_i) begin
    if (access) begin
      // $display("WATCHDOG ACCESS: adr=%h we=%b sel=%b dat_i=%h reg_sel=%d write=%b read=%b ack=%b", wb_adr_i, wb_we_i, wb_sel_i, wb_dat_i, reg_sel, write, read, wb_ack_o);
    end
    if (read && !wb_ack_o) begin
      // $display("WATCHDOG READ HIT: reg_sel=%d dat_o=%h", reg_sel, wb_dat_o);
    end
  end

  // Timeout can be cleared by:
  // - CTRL[3] "kick/reload" command, or
  // - STATUS[0] write-1-to-clear.
  wire ctrl_clear = write && wb_sel_i[0] && (reg_sel == REG_CTRL) && wb_dat_i[3];
  wire status_clear = write && wb_sel_i[0] && (reg_sel == REG_STATUS) && wb_dat_i[0];
  wire clear_timeout = ctrl_clear | status_clear;

  // Single sequential process keeps bus, control, and counter behavior aligned
  // in one place, which simplifies formal/simulation reasoning.
  always @(posedge clk_i) begin
    if (rst_i) begin
      wb_ack_o     <= 1'b0;
      wb_dat_o     <= 32'h0;
      load_value   <= 32'h0;
      counter      <= 32'h0;
      enable       <= 1'b0;
      irq_enable   <= 1'b0;
      auto_reload  <= 1'b0;
      timeout_flag <= 1'b0;
    end else if (clk_en_i) begin
      // Wishbone Acknowledge
      wb_ack_o <= access & ~wb_ack_o;


      // Register writes accept byte lane 0 only. Other lanes are ignored.
      if (write && wb_sel_i[0]) begin
        if (reg_sel == REG_LOAD) begin
           load_value <= wb_dat_i;
           counter <= wb_dat_i;
           // Corner case: enabling with a zero load triggers immediate timeout.
           if (enable && wb_dat_i == 32'h0) timeout_flag <= 1'b1;
        end else if (reg_sel == REG_CTRL) begin
          enable      <= wb_dat_i[0];
          irq_enable  <= wb_dat_i[1];
          auto_reload <= wb_dat_i[2];
          // CTRL[3] acts as an explicit reload/kick command.
          if (wb_dat_i[3]) begin
             counter <= load_value;
             if (wb_dat_i[0] && load_value == 32'h0) timeout_flag <= 1'b1;
          end else if (wb_dat_i[0] && counter == 32'h0) begin
             timeout_flag <= 1'b1;
          end
        end else if (reg_sel == REG_STATUS) begin
          if (wb_dat_i[0]) timeout_flag <= 1'b0;
        end
      end

      // Register Reads
      if (read) begin
        case (reg_sel)
          REG_LOAD:   wb_dat_o <= load_value;
          REG_CTRL:   wb_dat_o <= {29'h0, auto_reload, irq_enable, enable};
          REG_STATUS: wb_dat_o <= {31'h0, timeout_flag};
          default:    wb_dat_o <= 32'h0;
        endcase
      end

      if (enable && (counter != 32'h0) && !(write && (reg_sel == REG_LOAD || (reg_sel == REG_CTRL && wb_dat_i[3])))) begin
        counter <= counter - 1'b1;
        if (counter == 32'h1) begin
          timeout_flag <= 1'b1;
          if (auto_reload) counter <= load_value;
          else counter <= 32'h0;
        end
      end
    end else begin
      wb_ack_o <= (wb_cyc_i & wb_stb_i) & ~wb_ack_o;
      wb_dat_o <= 32'h0;
    end
  end
endmodule
