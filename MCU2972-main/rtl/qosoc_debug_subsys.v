`include "qosoc_defs.vh"
`include "qosoc_debug_status_defs.vh"

`ifdef QOSOC_YOSYS_STUB
`include "qosoc_debug_subsys_gls_stub.v"
`else

// =============================================================================
// QoSoC Debug Subsystem 
// =============================================================================
//
//
//   Request  (host → SoC) : [1B opcode] [4B payload]   (5 bytes)
//   Response (SoC → host) : [1B status] [4B data]      (5 bytes)
//
// Multi-word responses (DUMP, DETAIL, EVT_POP) send N consecutive 5-byte
// packets.  The host knows how many to expect from the opcode semantics.
//
// A sticky "address register" (SET_ADDR) is used so that READ, WRITE and
// DUMP all fit within a single 5-byte request.
//
// Opcode map:
//   0x01  PING           payload=ignored       → [OK][BUILD_ID]
//   0x02  STAT           payload=ignored       → [OK][packed_status]
//   0x03  SET_ADDR       payload=address       → [OK][echoed_addr]
//   0x04  READ           payload=ignored       → [OK][read_data]
//   0x05  WRITE          payload=write_data    → [OK][0x00000000]
//   0x06  DUMP           payload={27'h0,count} → count × [OK|CONT][data]
//   0x07  MBIST_GO       payload=ignored       → [OK][0x00000000]
//   0x08  MBIST_STAT     payload=ignored       → [OK][packed_mbist]
//   0x09  CLR            payload=ignored       → [OK][0x00000000]
//   0x0A  SET_SEL        payload={28'h0,sel}   → [OK][0x0000000s]
//   --- FULL mode only (DEBUG_LITE == 0) ---
//   0x10  DETAIL         payload=ignored       → 8 × [OK|CONT][packed]
//   0x11  EVT_STAT       payload=ignored       → [OK][packed_event]
//   0x12  EVT_POP        payload=ignored       → 2 × [OK|CONT][data]
//   0x13  EVT_CLR        payload=ignored       → [OK][0x00000000]
//   0x14  SCR_RD         payload={30'h0,idx}   → [OK][scratch_data]
//   0x15  SCR_WR         payload=write_data    → [OK][0x00000000]
//            (writes to scratch idx previously set via SET_ADDR[1:0])
//
// Status byte:
//   0x01  OK              0x02  CONT (continuation)
//   0x81  ERR_ARG         0x82  ERR_BUS
//   0x83  ERR_BUSY        0x84  ERR_EMPTY
// =============================================================================

module qosoc_debug_subsys #(
    parameter [31:0] BUILD_ID = 32'h44424732,
    parameter [30:0] UART_SETUP = 31'd139,
    parameter        DEBUG_LITE = 1'b0
) (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        dbg_mode_i,
    input  wire        boot_mode_i,
    input  wire        trap_i,
    input  wire [15:0] pwr_en_i,
    input  wire [ 7:0] wake_sources_i,
    input  wire        wake_event_i,
    input  wire        cpu_clk_en_i,
    input  wire [ 2:0] power_state_i,
    input  wire        domains_ready_i,
    input  wire        uart_rx_i,
    output wire        uart_tx_o,

    output reg  [31:0] wb_adr_o,
    output reg  [31:0] wb_dat_o,
    input  wire [31:0] wb_dat_i,
    output reg  [ 3:0] wb_sel_o,
    output reg         wb_we_o,
    output reg         wb_cyc_o,
    output reg         wb_stb_o,
    input  wire        wb_ack_i,
    input  wire        wb_err_i,
    input  wire        wb_stall_i,

    output wire        mbist_enable_o,
    output reg         mbist_start_o,
    input  wire        mbist_busy_i,
    input  wire        mbist_done_i,
    input  wire        mbist_pass_i,
    input  wire        mbist_fail_i
);

  // -----------------------------------------------------------------------
  // Protocol constants
  // -----------------------------------------------------------------------
  localparam [7:0] OP_PING       = 8'h01, OP_STAT       = 8'h02,
                   OP_SET_ADDR   = 8'h03, OP_READ       = 8'h04,
                   OP_WRITE      = 8'h05, OP_DUMP       = 8'h06,
                   OP_MBIST_GO   = 8'h07, OP_MBIST_STAT = 8'h08,
                   OP_CLR        = 8'h09, OP_SET_SEL    = 8'h0A;
  localparam [7:0] OP_DETAIL     = 8'h10, OP_EVT_STAT   = 8'h11,
                   OP_EVT_POP    = 8'h12, OP_EVT_CLR    = 8'h13,
                   OP_SCR_RD     = 8'h14, OP_SCR_WR     = 8'h15;

  localparam [7:0] RSP_OK        = 8'h01, RSP_CONT      = 8'h02,
                   RSP_ERR_ARG   = 8'h81, RSP_ERR_BUS   = 8'h82,
                   RSP_ERR_BUSY  = 8'h83, RSP_ERR_EMPTY = 8'h84;

  // -----------------------------------------------------------------------
  // FSM states
  // -----------------------------------------------------------------------
  localparam [3:0] S_IDLE       = 4'd0,  S_RX_POLL    = 4'd1,
                   S_EXEC       = 4'd2,  S_WB_WAIT    = 4'd3,
                   S_TX_BYTE    = 4'd4,  S_TX_WAIT    = 4'd5,
                   S_DUMP_NEXT  = 4'd6,  S_EVT_LATCH  = 4'd7,
                   S_MULTI_NEXT = 4'd8,  S_TX_CHK     = 4'd9;

  // UART WB addresses
  localparam [1:0] UART_RXREG = 2'b10, UART_TXREG = 2'b11;

  // Dump limit
  localparam [4:0] DUMP_MAX = DEBUG_LITE ? 5'd4 : 5'd16;

  // DETAIL packet count (FULL mode only)
  localparam [3:0] DETAIL_CNT = 4'd8;

  // -----------------------------------------------------------------------
  // Registers
  // -----------------------------------------------------------------------
  reg [3:0]  state;

  // RX accumulator
  reg [7:0]  rx_op;
  reg [31:0] rx_payload;
  reg [2:0]  rx_cnt;          // 0..4

  // TX response
  reg [7:0]  rsp_status;
  reg [31:0] rsp_data;
  reg [2:0]  tx_cnt;          // 0..4

  // Sticky command state
  reg [31:0] cmd_addr;
  reg [ 3:0] cmd_sel;

  // Multi-response state
  reg [4:0]  dump_rem;        // words remaining for DUMP
  reg [3:0]  multi_idx;       // index for DETAIL / EVT_POP continuation
  reg [7:0]  multi_op;        // opcode driving multi-response

  // UART WB interface
  reg        u_stb, u_cyc, u_we;
  reg [ 1:0] u_addr;
  reg [31:0] u_wdata;

  // Status tracking
  reg        trap_seen, trap_prev;
  reg [31:0] last_err_addr;
  reg        mbist_done_s, mbist_pass_s, mbist_fail_s, mbist_done_prev;
  reg        debug_entry_seen;

  // Event monitoring (FULL mode edge-detect regs)
  reg [15:0] pwr_en_prev;
  reg [ 2:0] pwr_st_prev;

  // FULL-mode only registers (scratch, trap_count, cycle ctr)
  reg [31:0] scratch_regs [0:3];
  reg [31:0] trap_count;
  reg [31:0] dbg_cycle_ctr;

  // Event FIFO interface
  reg         event_push_r;
  reg  [71:0] event_push_data_r;
  reg         event_pop_r;
  reg         event_clr_r;
  wire [71:0] event_pop_data;
  wire        event_empty, event_full;
  wire [ 5:0] event_count;
  wire        event_overflow;

  // Latched event data for EVT_POP response
  reg [71:0]  evt_latch;

  // UART wires
  wire [31:0] uart_rdata;
  wire        uart_ack, uart_stall_w;
  wire        uart_rx_int, uart_tx_int, uart_rxf_int, uart_txf_int;

  integer k;

  // -----------------------------------------------------------------------
  // Assigns
  // -----------------------------------------------------------------------
  assign mbist_enable_o = dbg_mode_i;

  // -----------------------------------------------------------------------
  // SRAM address check (MBIST guard)
  // -----------------------------------------------------------------------
  function is_sram_addr;
    input [31:0] addr;
    begin
      is_sram_addr = ((addr & `QOSOC_ADDR_SRAM_MASK) == `QOSOC_ADDR_SRAM_BASE);
    end
  endfunction

  // -----------------------------------------------------------------------
  // TX byte select — replaces the 1400-line resp_byte_at function
  // -----------------------------------------------------------------------
  function [7:0] tx_byte_sel;
    input [2:0]  cnt;
    input [7:0]  status;
    input [31:0] data;
    begin
      case (cnt)
        3'd0: tx_byte_sel = status;
        3'd1: tx_byte_sel = data[31:24];
        3'd2: tx_byte_sel = data[23:16];
        3'd3: tx_byte_sel = data[15:8];
        3'd4: tx_byte_sel = data[7:0];
        default: tx_byte_sel = 8'h00;
      endcase
    end
  endfunction

  // -----------------------------------------------------------------------
  // Packed status word for STAT command
  // -----------------------------------------------------------------------
  wire [31:0] packed_stat = {
    dbg_mode_i,      // [31]
    boot_mode_i,     // [30]
    trap_seen,       // [29]
    mbist_busy_i,    // [28]
    mbist_done_s,    // [27]
    mbist_pass_s,    // [26]
    mbist_fail_s,    // [25]
    1'b0,            // [24]
    last_err_addr[7:0], // [23:16] (low byte of last error address)
    pwr_en_i[15:0]   // [15:0]
  };

  wire [31:0] packed_mbist = {
    28'h0,
    mbist_busy_i,
    mbist_done_s,
    mbist_pass_s,
    mbist_fail_s
  };

  // -----------------------------------------------------------------------
  // Event FIFO (conditional)
  // -----------------------------------------------------------------------
  generate
    if (!DEBUG_LITE) begin : g_event_fifo
      qosoc_debug_event_fifo #(.DEPTH(32), .PTR_W(5)) u_event_fifo (
          .clk_i      (clk_i),
          .rst_i      (rst_i | ~dbg_mode_i),
          .clear_i    (event_clr_r),
          .push_i     (event_push_r),
          .push_data_i(event_push_data_r),
          .pop_i      (event_pop_r),
          .pop_data_o (event_pop_data),
          .empty_o    (event_empty),
          .full_o     (event_full),
          .count_o    (event_count),
          .overflow_o (event_overflow)
      );
    end else begin : g_event_stub
      assign event_pop_data = 72'h0;
      assign event_empty    = 1'b1;
      assign event_full     = 1'b0;
      assign event_count    = 6'd0;
      assign event_overflow = 1'b0;
    end
  endgenerate

  // -----------------------------------------------------------------------
  // Debug UART (reduced FIFO depth)
  // -----------------------------------------------------------------------
  wbuart #(
      .INITIAL_SETUP                (UART_SETUP),
      .LGFLEN                       (3),
      .HARDWARE_FLOW_CONTROL_PRESENT(1'b0)
  ) u_debug_uart (
      .clk_i            (clk_i),
      .rst_i            (rst_i | ~dbg_mode_i),
      .i_wb_cyc         (u_cyc),
      .i_wb_stb         (u_stb),
      .i_wb_we          (u_we),
      .i_wb_addr        (u_addr),
      .i_wb_data        (u_wdata),
      .o_wb_ack         (uart_ack),
      .o_wb_stall       (uart_stall_w),
      .o_wb_data        (uart_rdata),
      .i_uart_rx        (uart_rx_i),
      .o_uart_tx        (uart_tx_o),
      .i_cts_n          (1'b0),
      .o_rts_n          (),
      .o_uart_rx_int    (uart_rx_int),
      .o_uart_tx_int    (uart_tx_int),
      .o_uart_rxfifo_int(uart_rxf_int),
      .o_uart_txfifo_int(uart_txf_int)
  );

  // -----------------------------------------------------------------------
  // Main FSM
  // -----------------------------------------------------------------------
  always @(posedge clk_i) begin
    if (rst_i || !dbg_mode_i) begin
      state              <= S_IDLE;
      rx_op              <= 8'h0;
      rx_payload         <= 32'h0;
      rx_cnt             <= 3'd0;
      rsp_status         <= RSP_OK;
      rsp_data           <= 32'h0;
      tx_cnt             <= 3'd0;
      cmd_addr           <= 32'h0;
      cmd_sel            <= 4'hF;
      dump_rem           <= 5'd0;
      multi_idx          <= 4'd0;
      multi_op           <= 8'h0;
      u_stb <= 1'b0; u_cyc <= 1'b0; u_we <= 1'b0;
      u_addr <= 2'b00; u_wdata <= 32'h0;
      wb_adr_o <= 32'h0; wb_dat_o <= 32'h0;
      wb_sel_o <= 4'h0;  wb_we_o  <= 1'b0;
      wb_cyc_o <= 1'b0;  wb_stb_o <= 1'b0;
      mbist_start_o      <= 1'b0;
      trap_seen          <= 1'b0;
      trap_prev          <= 1'b0;
      last_err_addr      <= 32'h0;
      mbist_done_s       <= 1'b0;
      mbist_pass_s       <= 1'b0;
      mbist_fail_s       <= 1'b0;
      mbist_done_prev    <= 1'b0;
      debug_entry_seen   <= 1'b0;
      pwr_en_prev        <= 16'h0;
      pwr_st_prev        <= 3'h0;
      trap_count         <= 32'h0;
      dbg_cycle_ctr      <= 32'h0;
      event_push_r       <= 1'b0;
      event_push_data_r  <= 72'h0;
      event_pop_r        <= 1'b0;
      event_clr_r        <= 1'b0;
      evt_latch          <= 72'h0;
      for (k = 0; k < 4; k = k + 1) scratch_regs[k] <= 32'h0;
    end else begin
      // Default pulse signals
      mbist_start_o <= 1'b0;
      u_stb         <= 1'b0;
      u_cyc         <= 1'b0;
      event_push_r  <= 1'b0;
      event_pop_r   <= 1'b0;
      event_clr_r   <= 1'b0;

      if (!DEBUG_LITE) dbg_cycle_ctr <= dbg_cycle_ctr + 32'd1;

      // -------------------------------------------------------------------
      // Event monitoring (runs in background, independent of FSM)
      // -------------------------------------------------------------------
      if (!debug_entry_seen) begin
        debug_entry_seen <= 1'b1;
        pwr_en_prev      <= pwr_en_i;
        pwr_st_prev      <= power_state_i;
        trap_prev        <= trap_i;
        mbist_done_prev  <= mbist_done_i;
        if (!DEBUG_LITE) begin
          event_push_r     <= 1'b1;
          event_push_data_r <= {dbg_cycle_ctr, `QOSOC_DBG_EVT_DEBUG_ENTRY, {16'h0, pwr_en_i}};
        end
      end else begin
        // Trap edge
        if (trap_i && !trap_prev) begin
          trap_seen  <= 1'b1;
          trap_count <= trap_count + 32'd1;
          if (!DEBUG_LITE && !event_push_r) begin
            event_push_r      <= 1'b1;
            event_push_data_r <= {dbg_cycle_ctr, `QOSOC_DBG_EVT_TRAP, trap_count + 32'd1};
          end
        end
        trap_prev <= trap_i;

        // MBIST done edge
        if (mbist_done_i) begin
          mbist_done_s <= 1'b1;
          mbist_pass_s <= mbist_pass_i;
          mbist_fail_s <= mbist_fail_i;
        end
        if (mbist_done_i && !mbist_done_prev && !DEBUG_LITE && !event_push_r) begin
          event_push_r      <= 1'b1;
          event_push_data_r <= {dbg_cycle_ctr,
                                mbist_fail_i ? `QOSOC_DBG_EVT_MBIST_FAIL : `QOSOC_DBG_EVT_MBIST_DONE,
                                {30'h0, mbist_fail_i, mbist_pass_i}};
        end
        mbist_done_prev <= mbist_done_i;

        // Power-enable change
        if (!DEBUG_LITE && (pwr_en_i != pwr_en_prev) && !event_push_r) begin
          event_push_r      <= 1'b1;
          event_push_data_r <= {dbg_cycle_ctr, `QOSOC_DBG_EVT_PWR_EN, {16'h0, pwr_en_i}};
        end
        pwr_en_prev <= pwr_en_i;

        // Power-state change
        if (!DEBUG_LITE && (power_state_i != pwr_st_prev) && !event_push_r) begin
          event_push_r      <= 1'b1;
          event_push_data_r <= {dbg_cycle_ctr, `QOSOC_DBG_EVT_PWR_STATE, {29'h0, power_state_i}};
        end
        pwr_st_prev <= power_state_i;
      end

      // -------------------------------------------------------------------
      // Bus completion (runs whenever a WB cycle completes)
      // -------------------------------------------------------------------
      if (wb_cyc_o && (wb_ack_i || wb_err_i)) begin
        wb_cyc_o <= 1'b0;
        wb_stb_o <= 1'b0;

        if (wb_err_i) begin
          last_err_addr <= cmd_addr;
          if (!DEBUG_LITE && !event_push_r) begin
            event_push_r      <= 1'b1;
            event_push_data_r <= {dbg_cycle_ctr, `QOSOC_DBG_EVT_BUS_ERROR, cmd_addr};
          end
        end

        if (state == S_WB_WAIT) begin
          if (wb_err_i) begin
            rsp_status <= RSP_ERR_BUS;
            rsp_data   <= 32'h0;
            tx_cnt     <= 3'd0;
            state      <= S_TX_CHK;
          end else begin
            // For READ: capture data
            if (rx_op == OP_READ) begin
              rsp_data <= wb_dat_i;
            end
            // For DUMP: capture data
            if (rx_op == OP_DUMP) begin
              rsp_data <= wb_dat_i;
            end
            tx_cnt <= 3'd0;
            state  <= S_TX_CHK;
          end
        end
      end

      // -------------------------------------------------------------------
      // FSM
      // -------------------------------------------------------------------
      case (state)
        // ----- Poll UART for incoming byte -----
        S_IDLE: begin
          u_stb  <= 1'b1;
          u_cyc  <= 1'b1;
          u_we   <= 1'b0;
          u_addr <= UART_RXREG;
          state  <= S_RX_POLL;
        end

        // ----- Wait for UART RX ack -----
        S_RX_POLL: begin
          if (uart_ack) begin
            if (uart_rdata[8]) begin
              // No data available — retry
              state <= S_IDLE;
            end else begin
              // Got a byte
              if (rx_cnt == 3'd0) begin
                rx_op <= uart_rdata[7:0];
                rx_cnt <= 3'd1;
                state <= S_IDLE;
              end else if (rx_cnt == 3'd1) begin
                rx_payload[31:24] <= uart_rdata[7:0];
                rx_cnt <= 3'd2;
                state <= S_IDLE;
              end else if (rx_cnt == 3'd2) begin
                rx_payload[23:16] <= uart_rdata[7:0];
                rx_cnt <= 3'd3;
                state <= S_IDLE;
              end else if (rx_cnt == 3'd3) begin
                rx_payload[15:8] <= uart_rdata[7:0];
                rx_cnt <= 3'd4;
                state <= S_IDLE;
              end else begin
                rx_payload[7:0] <= uart_rdata[7:0];
                rx_cnt <= 3'd0;
                state <= S_EXEC;
              end
            end
          end
        end

        // ----- Execute command -----
        S_EXEC: begin
          rsp_status <= RSP_OK;
          rsp_data   <= 32'h0;
          dump_rem   <= 5'd0;
          multi_idx  <= 4'd0;
          multi_op   <= 8'h0;

          case (rx_op)
            OP_PING: begin
              rsp_data <= BUILD_ID;
              tx_cnt   <= 3'd0;
              state    <= S_TX_CHK;
            end

            OP_STAT: begin
              rsp_data <= packed_stat;
              tx_cnt   <= 3'd0;
              state    <= S_TX_CHK;
            end

            OP_SET_ADDR: begin
              cmd_addr <= rx_payload;
              rsp_data <= rx_payload;
              tx_cnt   <= 3'd0;
              state    <= S_TX_CHK;
            end

            OP_SET_SEL: begin
              cmd_sel  <= rx_payload[3:0];
              rsp_data <= {28'h0, rx_payload[3:0]};
              tx_cnt   <= 3'd0;
              state    <= S_TX_CHK;
            end

            OP_READ: begin
              if (mbist_busy_i && is_sram_addr(cmd_addr)) begin
                rsp_status <= RSP_ERR_BUSY;
                tx_cnt <= 3'd0;
                state  <= S_TX_CHK;
              end else begin
                wb_adr_o <= cmd_addr;
                wb_dat_o <= 32'h0;
                wb_sel_o <= 4'hF;
                wb_we_o  <= 1'b0;
                wb_cyc_o <= 1'b1;
                wb_stb_o <= 1'b1;
                rsp_status <= RSP_OK;
                state <= S_WB_WAIT;
              end
            end

            OP_WRITE: begin
              if (mbist_busy_i && is_sram_addr(cmd_addr)) begin
                rsp_status <= RSP_ERR_BUSY;
                tx_cnt <= 3'd0;
                state  <= S_TX_CHK;
              end else begin
                wb_adr_o <= cmd_addr;
                wb_dat_o <= rx_payload;
                wb_sel_o <= cmd_sel;
                wb_we_o  <= 1'b1;
                wb_cyc_o <= 1'b1;
                wb_stb_o <= 1'b1;
                rsp_status <= RSP_OK;
                state <= S_WB_WAIT;
              end
            end

            OP_DUMP: begin
              if (rx_payload[4:0] == 5'd0 || rx_payload[4:0] > DUMP_MAX) begin
                rsp_status <= RSP_ERR_ARG;
                tx_cnt <= 3'd0;
                state  <= S_TX_CHK;
              end else if (mbist_busy_i && is_sram_addr(cmd_addr)) begin
                rsp_status <= RSP_ERR_BUSY;
                tx_cnt <= 3'd0;
                state  <= S_TX_CHK;
              end else begin
                dump_rem <= rx_payload[4:0];
                wb_adr_o <= cmd_addr;
                wb_dat_o <= 32'h0;
                wb_sel_o <= 4'hF;
                wb_we_o  <= 1'b0;
                wb_cyc_o <= 1'b1;
                wb_stb_o <= 1'b1;
                rsp_status <= RSP_OK;
                state <= S_WB_WAIT;
              end
            end

            OP_MBIST_GO: begin
              if (mbist_busy_i) begin
                rsp_status <= RSP_ERR_BUSY;
              end else begin
                mbist_done_s  <= 1'b0;
                mbist_pass_s  <= 1'b0;
                mbist_fail_s  <= 1'b0;
                mbist_start_o <= 1'b1;
                if (!DEBUG_LITE && !event_push_r) begin
                  event_push_r      <= 1'b1;
                  event_push_data_r <= {dbg_cycle_ctr, `QOSOC_DBG_EVT_MBIST_START, 32'h0};
                end
              end
              tx_cnt <= 3'd0;
              state  <= S_TX_CHK;
            end

            OP_MBIST_STAT: begin
              rsp_data <= packed_mbist;
              tx_cnt   <= 3'd0;
              state    <= S_TX_CHK;
            end

            OP_CLR: begin
              last_err_addr <= 32'h0;
              mbist_done_s  <= 1'b0;
              mbist_pass_s  <= 1'b0;
              mbist_fail_s  <= 1'b0;
              tx_cnt <= 3'd0;
              state  <= S_TX_CHK;
            end

            // --- FULL mode opcodes ---
            OP_DETAIL: begin
              if (DEBUG_LITE) begin
                rsp_status <= RSP_ERR_ARG;
                tx_cnt <= 3'd0;
                state  <= S_TX_CHK;
              end else begin
                multi_op  <= OP_DETAIL;
                multi_idx <= 4'd0;
                rsp_data  <= BUILD_ID;
                tx_cnt    <= 3'd0;
                state     <= S_TX_CHK;
              end
            end

            OP_EVT_STAT: begin
              if (DEBUG_LITE) begin
                rsp_status <= RSP_ERR_ARG;
              end else begin
                rsp_data <= {event_overflow, event_full, event_empty, 23'h0, event_count};
              end
              tx_cnt <= 3'd0;
              state  <= S_TX_CHK;
            end

            OP_EVT_POP: begin
              if (DEBUG_LITE || event_empty) begin
                rsp_status <= DEBUG_LITE ? RSP_ERR_ARG : RSP_ERR_EMPTY;
                tx_cnt <= 3'd0;
                state  <= S_TX_CHK;
              end else begin
                event_pop_r <= 1'b1;
                state <= S_EVT_LATCH;
              end
            end

            OP_EVT_CLR: begin
              if (DEBUG_LITE) begin
                rsp_status <= RSP_ERR_ARG;
              end else begin
                event_clr_r <= 1'b1;
              end
              tx_cnt <= 3'd0;
              state  <= S_TX_CHK;
            end

            OP_SCR_RD: begin
              if (DEBUG_LITE) begin
                rsp_status <= RSP_ERR_ARG;
              end else begin
                case (rx_payload[1:0])
                  2'd0: rsp_data <= scratch_regs[0];
                  2'd1: rsp_data <= scratch_regs[1];
                  2'd2: rsp_data <= scratch_regs[2];
                  default: rsp_data <= scratch_regs[3];
                endcase
              end
              tx_cnt <= 3'd0;
              state  <= S_TX_CHK;
            end

            OP_SCR_WR: begin
              if (DEBUG_LITE) begin
                rsp_status <= RSP_ERR_ARG;
              end else begin
                scratch_regs[cmd_addr[1:0]] <= rx_payload;
              end
              tx_cnt <= 3'd0;
              state  <= S_TX_CHK;
            end

            default: begin
              rsp_status <= RSP_ERR_ARG;
              tx_cnt <= 3'd0;
              state  <= S_TX_CHK;
            end
          endcase
        end

        // ----- Wait for bus completion (handled above in wb_cyc_o block) -----
        S_WB_WAIT: begin
          // Handled by the wb_cyc_o completion block above
        end

        // ----- Check TX readiness before sending -----
        S_TX_CHK: begin
          if (uart_tx_int) begin
            // TX FIFO has space — send byte
            u_stb   <= 1'b1;
            u_cyc   <= 1'b1;
            u_we    <= 1'b1;
            u_addr  <= UART_TXREG;
            u_wdata <= {24'h0, tx_byte_sel(tx_cnt, rsp_status, rsp_data)};
            state   <= S_TX_WAIT;
          end
          // else stay in S_TX_CHK until TX is ready
        end

        // ----- Wait for TX ack -----
        S_TX_WAIT: begin
          if (uart_ack) begin
            if (tx_cnt == 3'd4) begin
              // All 5 bytes sent — check for continuation
              if (dump_rem > 5'd1) begin
                dump_rem   <= dump_rem - 5'd1;
                cmd_addr   <= cmd_addr + 32'd4;
                state      <= S_DUMP_NEXT;
              end else if (multi_op == OP_DETAIL && multi_idx < (DETAIL_CNT - 4'd1)) begin
                multi_idx <= multi_idx + 4'd1;
                state     <= S_MULTI_NEXT;
              end else if (multi_op == OP_EVT_POP && multi_idx == 4'd0) begin
                multi_idx <= 4'd1;
                state     <= S_MULTI_NEXT;
              end else begin
                dump_rem <= 5'd0;
                multi_op <= 8'h0;
                state    <= S_IDLE;
              end
            end else begin
              tx_cnt <= tx_cnt + 3'd1;
              state  <= S_TX_CHK;
            end
          end
        end

        // ----- Issue next DUMP bus read -----
        S_DUMP_NEXT: begin
          wb_adr_o   <= cmd_addr;
          wb_dat_o   <= 32'h0;
          wb_sel_o   <= 4'hF;
          wb_we_o    <= 1'b0;
          wb_cyc_o   <= 1'b1;
          wb_stb_o   <= 1'b1;
          rsp_status <= RSP_CONT;
          state      <= S_WB_WAIT;
        end

        // ----- Latch event FIFO output (1-cycle delay) -----
        S_EVT_LATCH: begin
          evt_latch  <= event_pop_data;
          rsp_status <= RSP_OK;
          rsp_data   <= event_pop_data[31:0]; // arg
          multi_op   <= OP_EVT_POP;
          multi_idx  <= 4'd0;
          tx_cnt     <= 3'd0;
          state      <= S_TX_CHK;
        end

        // ----- Load next multi-response packet data -----
        S_MULTI_NEXT: begin
          rsp_status <= RSP_CONT;
          tx_cnt     <= 3'd0;

          if (multi_op == OP_DETAIL) begin
            case (multi_idx)
              4'd1: rsp_data <= packed_stat;
              4'd2: rsp_data <= trap_count;
              4'd3: rsp_data <= last_err_addr;
              4'd4: rsp_data <= {pwr_en_i, 8'h0, wake_sources_i};
              4'd5: rsp_data <= {power_state_i, cpu_clk_en_i, domains_ready_i, 21'h0,
                                 event_count};
              4'd6: rsp_data <= scratch_regs[0];
              4'd7: rsp_data <= scratch_regs[1];
              default: rsp_data <= 32'h0;
            endcase
          end else if (multi_op == OP_EVT_POP) begin
            // Packet 2: {code[7:0], timestamp[23:0]}
            rsp_data <= {evt_latch[39:32], evt_latch[63:40]};
          end else begin
            rsp_data <= 32'h0;
          end

          state <= S_TX_CHK;
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule

`endif
