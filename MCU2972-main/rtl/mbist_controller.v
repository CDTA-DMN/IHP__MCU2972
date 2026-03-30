// =============================================================================
// QoSoC MBIST Controller
// =============================================================================
//
// OVERVIEW:
// Built-in self-test controller for the 512x32 SRAM instance. Runs a compact
// March-style sequence and reports pass/fail completion status.
//
// IMPLEMENTATION NOTES:
// - Uses 9-bit addressing for 512-word SRAM depth.
// - Read checks are split with an explicit wait state to match macro latency.
// - MBIST control outputs map directly to SRAM BIST-side control pins.
//
// =============================================================================

module mbist_controller (
    input  wire clk_i,
    input  wire rst_ni,
    input  wire mbist_enable,
    input  wire mbist_start,
    output reg  mbist_busy,
    output reg  mbist_done,
    output reg  mbist_pass,
    output reg  mbist_fail,

    // SRAM interface (directly maps to A_BIST_* signals in wrapper)
    output wire        sram_clk,  // pure pass-through — driven by assign below
    output reg         sram_men,
    output reg         sram_wen,
    output reg         sram_ren,
    output reg  [ 8:0] sram_addr,  // 9-bit address for 512-word SRAM
    output reg  [31:0] sram_din,
    input  wire [31:0] sram_dout,

    // BIST control
    output wire bist_clk,  // pure pass-through — driven by assign below
    output reg bist_en,
    output reg bist_men
);

  // MBIST states - include explicit BIST-enable entry/exit guard cycles to
  // match the SRAM macro requirement that no memory operation occurs on the
  // cycles surrounding an A_BIST_EN transition.
  localparam [3:0] IDLE        = 4'd0;
  localparam [3:0] ENTRY_GUARD = 4'd1;
  localparam [3:0] MARCH_W0    = 4'd2;   // Write 0 ascending
  localparam [3:0] MARCH_R0    = 4'd3;   // Read 0 ascending (phase 1)
  localparam [3:0] MARCH_W1    = 4'd4;   // Write 1 ascending (phase 2)
  localparam [3:0] MARCH_R1    = 4'd5;   // Read 1 descending (phase 1)
  localparam [3:0] MARCH_W0D   = 4'd6;   // Write 0 descending (phase 2)
  localparam [3:0] MARCH_R0D   = 4'd7;   // Read 0 descending (final check)
  localparam [3:0] WAIT_READ   = 4'd8;   // Wait for read data (1-cycle latency)
  localparam [3:0] CHECK_READ  = 4'd9;   // Compare registered SRAM output
  localparam [3:0] EXIT_GUARD  = 4'd10;
  localparam [3:0] DONE        = 4'd11;

  // Highest valid address in a 512-word SRAM.
  localparam [8:0] MAX_ADDR = 9'h1FF;

  reg [3:0] state;
  reg [3:0] next_state;           // Return state after wait
  reg [8:0] addr_count;           // 9-bit counter to cover all 512 words
  reg [31:0] expected_data;
  reg error_flag;
  // Main MBIST sequencer:
  // drives the SRAM BIST-side interface and advances through the March steps.
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state <= IDLE;
      next_state <= IDLE;
      addr_count <= 9'h0;
      mbist_busy <= 1'b0;
      mbist_done <= 1'b0;
      mbist_pass <= 1'b0;
      mbist_fail <= 1'b0;
      error_flag <= 1'b0;
      sram_men <= 1'b0;
      sram_wen <= 1'b0;
      sram_ren <= 1'b0;
      sram_addr <= 9'h0;
      sram_din <= 32'h0;
      expected_data <= 32'h0;
      bist_en <= 1'b0;
      bist_men <= 1'b0;
    end else if (mbist_enable) begin
      case (state)
        IDLE : begin
          mbist_busy <= 1'b0;
          mbist_done <= 1'b0;
          mbist_pass <= 1'b0;
          mbist_fail <= 1'b0;
          sram_men <= 1'b0;
          sram_wen <= 1'b0;
          sram_ren <= 1'b0;
          bist_en <= 1'b0;
          bist_men <= 1'b0;
          if (mbist_start) begin
            state <= ENTRY_GUARD;
            addr_count <= 9'h0;
            error_flag <= 1'b0;
            mbist_busy <= 1'b1;
            bist_en <= 1'b1;
            bist_men <= 1'b0;
          end
        end

        ENTRY_GUARD : begin
          sram_men <= 1'b0;
          sram_wen <= 1'b0;
          sram_ren <= 1'b0;
          bist_en <= 1'b1;
          bist_men <= 1'b0;
          state <= MARCH_W0;
        end

        // Phase 1: Write 0 to all addresses (ascending)
        MARCH_W0 : begin
          bist_en   <= 1'b1;
          bist_men  <= 1'b1;
          sram_men  <= 1'b1;
          sram_wen  <= 1'b1;
          sram_ren  <= 1'b0;
          sram_addr <= addr_count;
          sram_din  <= 32'h00000000;

          if (addr_count == MAX_ADDR) begin
            state <= MARCH_R0;
            addr_count <= 9'h0;
          end else begin
            addr_count <= addr_count + 1;
          end
        end

        // Phase 2: Read 0, then Write 1 (ascending) - READ cycle
        MARCH_R0 : begin
          bist_en   <= 1'b1;
          bist_men  <= 1'b1;
          sram_men  <= 1'b1;
          sram_ren  <= 1'b1;
          sram_wen  <= 1'b0;
          sram_addr <= addr_count;
          expected_data <= 32'h00000000;
          next_state <= MARCH_W1;
          state <= WAIT_READ;
        end

        // Phase 2: Read 0, then Write 1 (ascending) - WRITE cycle
        MARCH_W1 : begin
          bist_en   <= 1'b1;
          bist_men  <= 1'b1;
          sram_men  <= 1'b1;
          sram_wen  <= 1'b1;
          sram_ren  <= 1'b0;
          sram_addr <= addr_count;
          sram_din  <= 32'hFFFFFFFF;

          if (addr_count == MAX_ADDR) begin
            state <= MARCH_R1;
            addr_count <= MAX_ADDR;
          end else begin
            addr_count <= addr_count + 1;
            state <= MARCH_R0;
          end
        end

        // Phase 3: Read 1, then Write 0 (descending) - READ cycle
        MARCH_R1 : begin
          bist_en   <= 1'b1;
          bist_men  <= 1'b1;
          sram_men  <= 1'b1;
          sram_ren  <= 1'b1;
          sram_wen  <= 1'b0;
          sram_addr <= addr_count;
          expected_data <= 32'hFFFFFFFF;
          next_state <= MARCH_W0D;
          state <= WAIT_READ;
        end

        // Phase 3: Read 1, then Write 0 (descending) - WRITE cycle
        MARCH_W0D : begin
          bist_en   <= 1'b1;
          bist_men  <= 1'b1;
          sram_men  <= 1'b1;
          sram_wen  <= 1'b1;
          sram_ren  <= 1'b0;
          sram_addr <= addr_count;
          sram_din  <= 32'h00000000;

          if (addr_count == 9'h0) begin
            state <= MARCH_R0D;
            addr_count <= MAX_ADDR;
          end else begin
            addr_count <= addr_count - 1;
            state <= MARCH_R1;
          end
        end

        // Phase 4: Final read 0 (descending) - verify all zeros
        MARCH_R0D : begin
          bist_en   <= 1'b1;
          bist_men  <= 1'b1;
          sram_men  <= 1'b1;
          sram_ren  <= 1'b1;
          sram_wen  <= 1'b0;
          sram_addr <= addr_count;
          expected_data <= 32'h00000000;
          
          if (addr_count == 9'h0) begin
            next_state <= EXIT_GUARD;
          end else begin
            next_state <= MARCH_R0D;
          end
          state <= WAIT_READ;
          
          if (addr_count != 9'h0)
            addr_count <= addr_count - 1;
        end

        // Wait one cycle for SRAM read latency, then check data
        WAIT_READ : begin
          bist_en   <= 1'b1;
          bist_men  <= 1'b1;
          sram_men  <= 1'b0;
          sram_ren <= 1'b0;
          sram_wen <= 1'b0;
          state <= CHECK_READ;
        end

        CHECK_READ : begin
          bist_en <= 1'b1;
          bist_men <= 1'b1;
          sram_men <= 1'b0;
          sram_ren <= 1'b0;
          sram_wen <= 1'b0;
          if (sram_dout != expected_data) begin
            error_flag <= 1'b1;
          end
          state <= next_state;
        end

        EXIT_GUARD : begin
          sram_men <= 1'b0;
          sram_ren <= 1'b0;
          sram_wen <= 1'b0;
          bist_en <= 1'b1;
          bist_men <= 1'b0;
          state <= DONE;
        end

        DONE : begin
          mbist_busy <= 1'b0;
          mbist_done <= 1'b1;
          mbist_pass <= !error_flag;
          mbist_fail <= error_flag;
          sram_men <= 1'b0;
          sram_ren <= 1'b0;
          sram_wen <= 1'b0;
          bist_men <= 1'b0;
          bist_en <= 1'b0;
          state <= IDLE;
        end

        default: begin
          state <= IDLE;
          mbist_busy <= 1'b0;
          mbist_done <= 1'b0;
          mbist_pass <= 1'b0;
          mbist_fail <= 1'b0;
          sram_men <= 1'b0;
          sram_ren <= 1'b0;
          sram_wen <= 1'b0;
          bist_en <= 1'b0;
          bist_men <= 1'b0;
        end
      endcase
    end else begin
      state <= IDLE;
      next_state <= IDLE;
      addr_count <= 9'h0;
      mbist_busy <= 1'b0;
      mbist_done <= 1'b0;
      mbist_pass <= 1'b0;
      mbist_fail <= 1'b0;
      error_flag <= 1'b0;
      sram_men <= 1'b0;
      sram_wen <= 1'b0;
      sram_ren <= 1'b0;
      sram_addr <= 9'h0;
      sram_din <= 32'h0;
      expected_data <= 32'h0;
      bist_en <= 1'b0;
      bist_men <= 1'b0;
    end
  end

  // SRAM test clock and MBIST control clock are tied to the controller clock.
  // Must be output wire: assign is the only driver, procedural block must not touch them.
  assign sram_clk = clk_i;
  assign bist_clk = clk_i;

endmodule