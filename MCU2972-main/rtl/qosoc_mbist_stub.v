// =============================================================================
// QoSoC MBIST Stub Declarations
// =============================================================================
//
// OVERVIEW:
// Provides synthesis-time blackbox declarations for SRAM/MBIST macros when
// technology models are not compiled in the current flow.
//
// NOTES:
// - Declarations are active only under `SYNTHESIS`.
// - This file is intended for elaboration compatibility, not functional sim.
//
// =============================================================================
`ifndef QOSOC_MBIST_STUB_V
`define QOSOC_MBIST_STUB_V

`ifdef SYNTHESIS
// Synthesis-time black boxes for technology-specific MBIST SRAM macros
// Keep these declarations in sync with macro pin lists so wrapper wiring
// mistakes fail at elaboration rather than later in integration.
(* blackbox *)
module RM_IHPSG13_1P_512x32_c2_bm_bist (
    input  wire        A_CLK,
    input  wire        A_MEN,
    input  wire        A_WEN,
    input  wire        A_REN,
    input  wire [ 8:0] A_ADDR,
    input  wire [31:0] A_DIN,
    input  wire        A_DLY,
    output wire [31:0] A_DOUT,
    input  wire [31:0] A_BM,
    input  wire        A_BIST_CLK,
    input  wire        A_BIST_EN,
    input  wire        A_BIST_MEN,
    input  wire        A_BIST_WEN,
    input  wire        A_BIST_REN,
    input  wire [ 8:0] A_BIST_ADDR,
    input  wire [31:0] A_BIST_DIN,
    input  wire [31:0] A_BIST_BM
);
endmodule

// Alternative SRAM model declaration used by some synthesis/sim flows.
(* blackbox *)
module SRAM_1P_behavioral_bm_bist #(
    parameter int P_DATA_WIDTH = 24,
    parameter int P_ADDR_WIDTH = 14
) (
    input  wire [P_ADDR_WIDTH-1:0] A_ADDR,
    input  wire [P_DATA_WIDTH-1:0] A_DIN,
    input  wire [P_DATA_WIDTH-1:0] A_BM,
    input  wire                    A_MEN,
    input  wire                    A_WEN,
    input  wire                    A_REN,
    input  wire                    A_CLK,
    input  wire                    A_DLY,
    output wire [P_DATA_WIDTH-1:0] A_DOUT,
    input  wire                    A_BIST_EN,
    input  wire [P_ADDR_WIDTH-1:0] A_BIST_ADDR,
    input  wire [P_DATA_WIDTH-1:0] A_BIST_DIN,
    input  wire [P_DATA_WIDTH-1:0] A_BIST_BM,
    input  wire                    A_BIST_MEN,
    input  wire                    A_BIST_WEN,
    input  wire                    A_BIST_REN,
    input  wire                    A_BIST_CLK
);
endmodule
`else
`endif

`endif  // QOSOC_MBIST_STUB_V
