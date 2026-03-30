// =============================================================================
// QoSoC Reset Synchronizer
// =============================================================================
//
// OVERVIEW:
// Two-flop synchronizer that converts asynchronous active-low reset input
// (`rst_ni`) into a clock-domain-local active-high reset output.
//
// =============================================================================
module qosoc_reset_sync (
    input  wire clk_i,
    input  wire rst_ni,
    output wire rst_sync_o
);
  reg [1:0] sync_ff;
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sync_ff <= 2'b00;
    end else begin
      sync_ff <= {sync_ff[0], 1'b1};
    end
  end
  assign rst_sync_o = ~sync_ff[1];
endmodule
