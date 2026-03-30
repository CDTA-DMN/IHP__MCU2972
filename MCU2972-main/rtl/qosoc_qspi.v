// =============================================================================
// QoSoC QSPI Wrapper
// =============================================================================
//
// OVERVIEW:
// Integrates the QSPI flash controller into the QoSoC Wishbone map. Handles
// local clock gating and exports quad-SPI pad signals and interrupt.
//
// ADDRESSING NOTES:
// - `ADDRESS_WIDTH` controls the exposed flash window depth.
// - `CTRL_REGION` selects the internal control subregion decode.
//
// =============================================================================
`include "qosoc_defs.vh"

module qosoc_qspi #(
    parameter integer ADDRESS_WIDTH = 24,
    parameter integer CTRL_REGION   = 4'h0
) (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        rst_ni,
    input  wire        clk_en_i,

    // Wishbone slave interface
    input  wire        wb_cyc_i,
    input  wire        wb_stb_i,
    input  wire        wb_we_i,
    input  wire [3:0]  wb_sel_i,
    input  wire [31:0] wb_adr_i,
    input  wire [31:0] wb_dat_i,
    output wire [31:0] wb_dat_o,
    output wire        wb_ack_o,
    output wire        wb_err_o,
    output wire        wb_stall_o,

    // Interrupt
    output wire        irq_o,

    // External QSPI interface
    output wire        qspi_sck,
    output wire        qspi_cs_n,
    output wire [3:0]  qspi_dat_o,
    output wire [3:0]  qspi_dat_oe,
    input  wire [3:0]  qspi_dat_i,
    output wire [1:0]  qspi_dat_mode
);
    localparam integer AW = ADDRESS_WIDTH - 2;

    // Kept for symmetry with other wrappers. The wrapped controller below
    // intentionally runs from `clk_i` so protocol/state timing stays continuous.
    wire clk_qspi;
    qosoc_clk_gate u_clk_gate (
        .clk_in      (clk_i),
        .rst_n       (rst_ni),
        .enable      (clk_en_i),
        .clk_out     (clk_qspi)
    );

    // Address split:
    // - Data region: memory-mapped XIP window.
    // - Control region: command/config/status registers inside wbqspiflash.
    wire        req        = wb_cyc_i && wb_stb_i;
    wire        ctrl_region = (wb_adr_i[23:12] == {12'h000 | CTRL_REGION});
    wire        data_region = req && !ctrl_region;

    // When power-gated, strobes are suppressed before reaching the controller.
    wire        data_stb  = clk_en_i ? (wb_stb_i && data_region) : 1'b0;
    wire        ctrl_stb  = clk_en_i ? (wb_stb_i && ctrl_region) : 1'b0;
    
    // Bring-up visibility for XIP/control traffic.
    // This trace is currently unconditional in simulation builds.
    reg prev_cyc, prev_stb;
    always @(posedge clk_i) begin
        prev_cyc <= wb_cyc_i;
        prev_stb <= wb_stb_i;
        if (!prev_cyc && wb_cyc_i) begin
            //$display("[QSPI_WB] CYC asserted @ %t", $time);
        end
        if (!prev_stb && wb_stb_i) begin
            //$display("[QSPI_WB] STB asserted @ %t, addr=%h, we=%b, data_region=%b, clk_en=%b", $time, wb_adr_i, wb_we_i, data_region, clk_en_i);
        end
        if (wb_cyc_i && wb_stb_i && wb_ack_o) begin
            //$display("[QSPI_WB] ACK @ %t, addr=%h, data=%h", $time, wb_adr_i, wb_dat_o);
        end
    end

    // Shared stall/ack/data from controller
    wire        wb_ack_raw;
    wire        wb_stall_raw;
    wire [31:0] wb_data_raw;
    wire        irq_qspi;

    wire        wb_we_int   = clk_en_i ? wb_we_i  : 1'b0;
    wire [31:0] wb_dat_int  = clk_en_i ? wb_dat_i : 32'h0;
    wire [AW-1:0] wb_addr_int = wb_adr_i[AW+1:2];

    // wbqspiflash is stateful and expects a free-running system clock.
    // Power control is handled at its bus inputs/outputs rather than by clock stop.
    wbqspiflash #(
        .ADDRESS_WIDTH(ADDRESS_WIDTH),  // ADDRESS_WIDTH=23 = 8MB for W25Q64FW
        .OPT_READ_ONLY(1'b0)            // Allow writes for programming
    ) u_qspiflash (
        .clk_i           (clk_i),  // Use ungated clock - controller needs to initialize
        .rst_i           (rst_i),  // Pass system reset
        // Wishbone interface - separate data and control strobes
        .i_wb_cyc        (wb_cyc_i),
        .i_wb_data_stb   (data_stb),    // Data region (XIP)
        .i_wb_ctrl_stb   (ctrl_stb),    // Control region (config)
        .i_wb_we         (wb_we_int),
        .i_wb_addr       (wb_addr_int),
        .i_wb_data       (wb_dat_int),
        .o_wb_stall      (wb_stall_raw),
        .o_wb_ack        (wb_ack_raw),
        .o_wb_data       (wb_data_raw),
        // QSPI interface
        .o_qspi_sck      (qspi_sck),
        .o_qspi_cs_n     (qspi_cs_n),
        .o_qspi_mod      (qspi_dat_mode),
        .o_qspi_dat      (qspi_dat_o),
        .i_qspi_dat      (qspi_dat_i),
        .o_interrupt     (irq_qspi)
    );
    
    // Translate controller IO mode into per-pin output-enable signals.
    // mode[1:0]:
    //   00 = single-bit SPI (drive IO0 only)
    //   01 = dual I/O (drive IO0..IO1)
    //   10 = quad output (drive IO0..IO3)
    //   11 = quad input  (tri-state all IOs)
    assign qspi_dat_oe[0] = (qspi_dat_mode == 2'b00) || (qspi_dat_mode == 2'b01) || (qspi_dat_mode == 2'b10);
    assign qspi_dat_oe[1] = (qspi_dat_mode == 2'b01) || (qspi_dat_mode == 2'b10);
    assign qspi_dat_oe[2] = (qspi_dat_mode == 2'b10);
    assign qspi_dat_oe[3] = (qspi_dat_mode == 2'b10);

    // Power-off policy: terminate bus cycles and suppress side effects.
    assign wb_ack_o   = clk_en_i ? wb_ack_raw   : (wb_cyc_i & wb_stb_i);
    assign wb_stall_o = clk_en_i ? wb_stall_raw : 1'b0;
    assign wb_dat_o   = clk_en_i ? wb_data_raw  : 32'h0000_0000;
    assign wb_err_o   = 1'b0;
    assign irq_o      = clk_en_i ? irq_qspi : 1'b0;
endmodule
