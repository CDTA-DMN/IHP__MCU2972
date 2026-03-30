// =============================================================================
// QoSoC SRAM Wrapper
// =============================================================================
//
// OVERVIEW:
// Wishbone wrapper for the IHP SG13G2 512x32 SRAM macro with MBIST override
// support. Arbitrates between normal bus accesses and MBIST control signals.
//
// MEMORY/PROTOCOL NOTES:
// - `A_DLY` is tied high per macro requirement.
// - Read data returns with one-cycle latency.
// - MBIST path has priority whenever `mbist_en` is asserted.
// - If power is off, wrapper returns an ACK to avoid bus deadlock.
//
// =============================================================================

module qosoc_sram_wrapper (
    // Wishbone interface
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        rst_ni,
    input  wire [31:0] wb_adr_i,
    input  wire [31:0] wb_dat_i,
    output reg  [31:0] wb_dat_o,
    input  wire [ 3:0] wb_sel_i,
    input  wire        wb_we_i,
    input  wire        wb_stb_i,
    input  wire        wb_cyc_i,
    output reg         wb_ack_o,
    output wire        wb_err_o,
    output wire        wb_stall_o,
    input  wire        pwr_en_i,

    // MBIST interface
    input wire        mbist_clk,
    input wire        mbist_en,
    input wire        mbist_men,
    input wire        mbist_wen,
    input wire        mbist_ren,
    input wire [ 8:0] mbist_addr,
    input wire [31:0] mbist_din,
    input wire [31:0] mbist_bm,
    output wire [31:0] mbist_dout_o
);

  // Wishbone signals
  assign wb_err_o   = 1'b0;
  assign wb_stall_o = 1'b0;

  // Minimal FSM for single-port SRAM access timing:
  // IDLE -> READ/WRITE -> DONE -> IDLE.
  localparam IDLE = 2'b00;
  localparam READ = 2'b01;
  localparam WRITE = 2'b10;
  localparam DONE = 2'b11;

  reg [1:0] state, next_state;
  // Initialization moved to reset logic


  // Address decoding - 512 words = 9 bits, word-aligned
  wire [8:0] wb_addr = wb_adr_i[10:2];

  // A request is accepted only when powered, not in MBIST mode, and no ACK is
  // currently being returned.
  wire wb_req = wb_cyc_i && wb_stb_i && pwr_en_i && !wb_ack_o;
  wire wb_read_req = wb_req && !wb_we_i;
  wire wb_write_req = wb_req && wb_we_i;

  // Byte mask generation (active high for IHP SRAM)
  wire [31:0] wb_byte_mask = {
    {8{wb_sel_i[3]}}, {8{wb_sel_i[2]}}, {8{wb_sel_i[1]}}, {8{wb_sel_i[0]}}
  };

  // A_CLK is always clk_i. When A_BIST_EN=1 the macro ignores A_CLK entirely
  // (datasheet operation table: A_BIST_EN=1 -> A_MEN 0/1 irrelevant -> No Operation).
  // Routing a clock through an always @* mux is unnecessary and creates a
  // combinational path that bypasses the clock tree.
  wire sram_clk = clk_i;
  reg sram_men;
  reg sram_wen;
  reg sram_ren;
  reg [8:0] sram_addr;
  reg [31:0] sram_din;
  reg [31:0] sram_bm;
  wire [31:0] sram_dout;
  assign mbist_dout_o = sram_dout;

  // MBIST path fully overrides normal bus controls while enabled.
  // Note: sram_clk (A_CLK) is not muxed — see declaration above.
  // The A_* control signals below are overridden but are ignored by the macro
  // when A_BIST_EN=1 (per datasheet); the mux is retained for safety and clarity.
  always @* begin
    if (mbist_en) begin
      // MBIST mode
      sram_men  = mbist_men;
      sram_wen  = mbist_wen;
      sram_ren  = mbist_ren;
      sram_addr = mbist_addr;
      sram_din  = mbist_din;
      sram_bm   = mbist_bm;
    end else begin
      // Normal Wishbone mode
      // Assert enable signals immediately when request arrives (IDLE) to capture on next clock edge
      sram_men  = (state == READ) || (state == WRITE) || (state == IDLE && wb_req);
      sram_wen  = (state == WRITE) || (state == IDLE && wb_write_req);
      sram_ren  = (state == READ) || (state == IDLE && wb_read_req);
      sram_addr = wb_addr;
      sram_din  = wb_dat_i;
      sram_bm   = wb_byte_mask;
    end
  end

  // FSM runs only when wrapper is in normal powered bus mode.
  always @(posedge clk_i) begin
    if (rst_i) begin
      state <= IDLE;
    end else if (pwr_en_i && !mbist_en) begin
      state <= next_state;
    end
  end

  always @* begin
    next_state = state;
    case (state)
      IDLE : begin
        if (wb_read_req) begin
          next_state = READ;
        end else if (wb_write_req) begin
          next_state = WRITE;
        end
      end

      READ : begin
        // SRAM has 1 cycle latency for reads
        next_state = DONE;
      end

      WRITE : begin
        // Write completes in 1 cycle
        next_state = DONE;
      end

      DONE : begin
        next_state = IDLE;
      end
      default: ; // No action; keeps combinational next-state fully specified.
    endcase
  end

  // ACK is asserted for one cycle in DONE, or immediately when powered off.
  always @(posedge clk_i) begin
    if (rst_i) begin
      wb_ack_o <= 1'b0;
    end else if (!mbist_en && pwr_en_i) begin
      wb_ack_o <= (state == DONE);
      /*
      if (wb_req)
        $display(
            "[SRAM] Req @ %t: addr=%h, we=%b, pwr=%b, state=%b",
            $time,
            wb_addr,
            wb_we_i,
            pwr_en_i,
            state
        );
      if (state == DONE) $display("[SRAM] ACK @ %t: dat=%h", $time, wb_dat_o);
      */
    end else begin
      wb_ack_o <= 1'b0;
      // Return an immediate ACK when the SRAM domain is off so the bus cannot stall.
      if (wb_cyc_i && wb_stb_i && !pwr_en_i) begin
        wb_ack_o <= 1'b1;
      end
    end
  end

  // Capture macro data for bus return path. Reads are one-cycle latent.
  always @(posedge clk_i) begin
    if (rst_i) begin
      wb_dat_o <= 32'h0;
    end else if (!mbist_en && pwr_en_i) begin
      if (state == READ || state == WRITE || (state == IDLE && wb_req)) begin
        wb_dat_o <= sram_dout;
      end
    end
  end

  // IHP SG13G2 SRAM Macro Instance
  RM_IHPSG13_1P_512x32_c2_bm_bist u_sram (
      .A_CLK      (sram_clk),
      .A_MEN      (sram_men),
      .A_WEN      (sram_wen),
      .A_REN      (sram_ren),
      .A_ADDR     (sram_addr),
      .A_DIN      (sram_din),
      .A_DLY      (1'b1),
      .A_DOUT     (sram_dout),
      .A_BM       (sram_bm),
      .A_BIST_CLK (mbist_clk),
      .A_BIST_EN  (mbist_en),
      .A_BIST_MEN (mbist_men),
      .A_BIST_WEN (mbist_wen),
      .A_BIST_REN (mbist_ren),
      .A_BIST_ADDR(mbist_addr),
      .A_BIST_DIN (mbist_din),
      .A_BIST_BM  (mbist_bm)
  );

endmodule
