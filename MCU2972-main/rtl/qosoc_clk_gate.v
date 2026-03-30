// =============================================================================
// QoSoC Clock-Gate Wrapper
// =============================================================================
//
// OVERVIEW:
// Thin wrapper around the IHP SG13G2 integrated clock-gate cell
// (`sg13g2_lgcp_1`).
//
// =============================================================================
module qosoc_clk_gate (
    input  wire clk_in,
    input  wire rst_n,
    input  wire enable,
    output wire clk_out
);
    // Function enable drives the ICG gate pin.
    wire enable_combined = enable;
    reg enable_sync;

    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            enable_sync <= 1'b0;
        end else begin
            enable_sync <= enable_combined;
        end
    end

    // IHP SG13G2 integrated clock-gating cell.
    sg13g2_lgcp_1 u_lgcp (
        .CLK  (clk_in),
        .GATE (enable_sync),
        .GCLK (clk_out)
    );
endmodule
