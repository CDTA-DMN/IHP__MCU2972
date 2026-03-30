module qosoc_debug_event_fifo #(
    parameter integer DEPTH = 32,
    parameter integer PTR_W = 5
) (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        clear_i,
    input  wire        push_i,
    input  wire [71:0] push_data_i,
    input  wire        pop_i,
    output reg  [71:0] pop_data_o,
    output wire        empty_o,
    output wire        full_o,
    output reg  [ 5:0] count_o,
    output reg         overflow_o
);

  reg [71:0] fifo_mem [0:DEPTH-1];
  reg [PTR_W-1:0] wr_ptr;
  reg [PTR_W-1:0] rd_ptr;

  wire do_pop = pop_i && (count_o != 6'd0);
  wire do_push = push_i && ((count_o != DEPTH[5:0]) || do_pop);

  assign empty_o = (count_o == 6'd0);
  assign full_o  = (count_o == DEPTH[5:0]);

  always @(posedge clk_i) begin
    if (rst_i || clear_i) begin
      wr_ptr     <= {PTR_W{1'b0}};
      rd_ptr     <= {PTR_W{1'b0}};
      pop_data_o <= 72'h0;
      count_o    <= 6'd0;
      overflow_o <= 1'b0;
    end else begin
      if (do_pop) begin
        pop_data_o <= fifo_mem[rd_ptr];
        rd_ptr     <= rd_ptr + {{(PTR_W-1){1'b0}}, 1'b1};
      end

      if (do_push) begin
        fifo_mem[wr_ptr] <= push_data_i;
        wr_ptr <= wr_ptr + {{(PTR_W-1){1'b0}}, 1'b1};
      end else if (push_i) begin
        overflow_o <= 1'b1;
      end

      case ({do_push, do_pop})
        2'b10: count_o <= count_o + 6'd1;
        2'b01: count_o <= count_o - 6'd1;
        default: ;
      endcase
    end
  end

endmodule
