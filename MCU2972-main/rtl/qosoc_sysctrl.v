// =============================================================================
// QoSoC System Controller
// =============================================================================
//
// OVERVIEW:
// Central bus fabric and glue logic for the SoC. Handles:
// - Power management register access
// - Sleep/wake control
// - Boot mode sampling
// - Interrupt aggregation for wakeup
//
// BUS DECODE SAFETY:
// - One-hot peripheral selection is enforced in simulation
// - Unmapped reads return 0x00000000
// - Unmapped writes are silently ignored (no bus error)
// - Optional: Can be configured to assert wb_err_o on invalid access
//
// RESET DOMAINS:
// - SYSCTRL is in the core (bus) power domain
// - If PMU powers down bus domain, SYSCTRL stops toggling
// - Boot mode is sampled on reset and held (read-only register)
//
// CDC NOTES:
// - wake_sources input is assumed synchronized by source peripherals
// - cpu_sleep_ack is assumed synchronized from CPU
// - Outputs to PMU (pwr_en_write, pwr_ctrl_write) are single-cycle pulses
//
// =============================================================================

`include "qosoc_defs.vh"

module qosoc_sysctrl (
    input wire clk_i,
    input wire rst_i,

    // Wishbone slave interface (32-bit)
    input  wire        wb_cyc_i,
    input  wire        wb_stb_i,
    input  wire        wb_we_i,
    input  wire [ 3:0] wb_sel_i,
    input  wire [31:0] wb_adr_i,
    input  wire [31:0] wb_dat_i,
    output reg  [31:0] wb_dat_o,
    output reg         wb_ack_o,
    output reg         wb_err_o,  // Error output for invalid access

    // Power control interface to PMU
    input  wire [15:0] pmu_pwr_en,
    output reg         pwr_en_write,
    output reg  [15:0] pwr_en_wdata,
    output reg         pwr_ctrl_write,
    output reg  [31:0] pwr_ctrl_wdata,

    // Sleep control
    output reg  cpu_sleep_req,
    input  wire cpu_sleep_ack,
    input  wire wake_event,

    // Interrupt aggregation inputs (for wake status)
    input  wire [7:0] wake_sources,
    output reg  [7:0] wake_mask,

    // Boot mode input (sampled at reset)
    input  wire       boot_mode_i
);

    // =========================================================================
    // Register Map (Word-Aligned Offsets)
    // =========================================================================
    // REG_SLEEP_CTRL bits:
    // [0] cpu_sleep_req, [1] cpu_sleep_ack (read-only), [2] wake_event (read-only)
    localparam [2:0] REG_PWR_CTRL  = 3'h0;  // 0x00: Power control
    localparam [2:0] REG_SLEEP_CTRL = 3'h1;  // 0x04: Sleep control
    localparam [2:0] REG_WAKE_MASK = 3'h2;  // 0x08: Wakeup mask
    localparam [2:0] REG_WAKE_STAT = 3'h3;  // 0x0C: Wakeup status
    localparam [2:0] REG_BOOT_MODE = 3'h4;  // 0x10: Boot mode (read-only)

    // =========================================================================
    // Internal Registers
    // =========================================================================
    reg [7:0] wake_status;
    reg       boot_mode_latched;
    // Initialization moved to reset logic


    // =========================================================================
    // Wishbone Access Decode
    // =========================================================================
    wire access = wb_cyc_i & wb_stb_i;
    wire write = access & wb_we_i;
    wire read = access & !wb_we_i;

    // Full word select (all 4 bytes)
    wire sel_word = &wb_sel_i;

    // Register address decode
    wire [2:0] reg_idx = wb_adr_i[4:2];
    
    // Individual register write strobes
    wire wr_pwr   = write & sel_word & (reg_idx == REG_PWR_CTRL);
    wire wr_sleep = write & sel_word & (reg_idx == REG_SLEEP_CTRL);
    wire wr_wmask = write & sel_word & (reg_idx == REG_WAKE_MASK);
    wire wr_wstat = write & sel_word & (reg_idx == REG_WAKE_STAT);

    // Detect invalid access (out of range or partial write)
    wire invalid_addr = (reg_idx > REG_BOOT_MODE);
    wire invalid_write = write & !sel_word;  // Partial writes not supported
    wire invalid_access = access & (invalid_addr | invalid_write);

    // =========================================================================
    // One-Hot Decode Safety Check (Simulation Only)
    // =========================================================================
    `ifdef SIMULATION
    always @(posedge clk_i) begin
        if (access && !rst_i) begin
            // Verify at most one register is selected
            if ($countones({wr_pwr, wr_sleep, wr_wmask, wr_wstat}) > 1) begin
                $error("SYSCTRL: Multiple register selects active! addr=0x%h", wb_adr_i);
            end
        end
    end
    `endif

    // =========================================================================
    // Power Enable Write Handshake to PMU
    // =========================================================================
    always @(posedge clk_i) begin
        if (rst_i) begin
            pwr_en_write <= 1'b0;
            pwr_en_wdata <= `QOSOC_PWR_DEFAULT;
        end else begin
            pwr_en_write <= 1'b0;  // Default: no write
            if (wr_pwr) begin
                pwr_en_write <= 1'b1;
                pwr_en_wdata <= wb_dat_i[15:0];
            end
        end
    end

    // =========================================================================
    // Sleep Request and Power Control Write Handshake to PMU
    // =========================================================================
    always @(posedge clk_i) begin
        if (rst_i) begin
            cpu_sleep_req <= 1'b0;
            pwr_ctrl_write <= 1'b0;
            pwr_ctrl_wdata <= 32'd0;
        end else begin
            pwr_ctrl_write <= 1'b0;  // Default: no write
            
            if (wr_sleep) begin
                cpu_sleep_req <= wb_dat_i[0];
                // Propagate to PMU for consistent state
                pwr_ctrl_write <= 1'b1;
                pwr_ctrl_wdata <= wb_dat_i;
            end else if (wake_event) begin
                // Clear sleep request on wakeup
                cpu_sleep_req <= 1'b0;
            end
        end
    end

    // =========================================================================
    // Wake Mask Register
    // =========================================================================
    always @(posedge clk_i) begin
        if (rst_i)
            wake_mask <= 8'h00;  // All sources disabled by default
        else if (wr_wmask)
            wake_mask <= wb_dat_i[7:0];
    end

    // =========================================================================
    // Wake Status Register (Sticky, Write-1-to-Clear)
    // =========================================================================
    always @(posedge clk_i) begin
        if (rst_i) begin
            wake_status <= 8'h00;
        end else begin
            // Set bits for active masked wakeup sources
            if (wake_event)
                wake_status <= wake_status | (wake_sources & wake_mask);
            
            // Write-1-to-clear
            if (wr_wstat)
                wake_status <= wake_status & ~wb_dat_i[7:0];
        end
    end

    // =========================================================================
    // Boot Mode Register (Sampled at Reset, Read-Only)
    // =========================================================================
    always @(posedge clk_i) begin
        if (rst_i)
            boot_mode_latched <= boot_mode_i;  // Sample on reset (synchronous)
        // Else: hold value (read-only)
    end

    // =========================================================================
    // Wishbone Read Multiplexer
    // =========================================================================
    always @(*) begin
        case (reg_idx)
            REG_PWR_CTRL:  wb_dat_o = {16'h0000, pmu_pwr_en};
            REG_SLEEP_CTRL: wb_dat_o = {29'h0, wake_event, cpu_sleep_ack, cpu_sleep_req};
            REG_WAKE_MASK: wb_dat_o = {24'h0, wake_mask};
            REG_WAKE_STAT: wb_dat_o = {24'h0, wake_status};
            REG_BOOT_MODE: wb_dat_o = {31'h0, boot_mode_latched};
            default:       wb_dat_o = 32'h0000_0000;  // Unmapped reads return 0
        endcase
    end

    // =========================================================================
    // Wishbone Acknowledge and Error Generation
    // =========================================================================
    always @(posedge clk_i) begin
        if (rst_i) begin
            wb_ack_o <= 1'b0;
            wb_err_o <= 1'b0;
        end else begin
            // Single-cycle acknowledge for ALL accesses (valid and invalid)
            // Invalid accesses return 0 and optionally assert error
            wb_ack_o <= access & ~wb_ack_o;
            
            // Assert error on invalid access
            wb_err_o <= invalid_access & ~wb_err_o;
        end
    end

    // =========================================================================
    // Debug Logging (Simulation Only)
    // =========================================================================
    `ifdef SIMULATION
    always @(posedge clk_i) begin
        if (access && wb_ack_o && !rst_i) begin
            if (wb_we_i)
                $display("[SYSCTRL] WRITE: addr=0x%h, data=0x%h, sel=%b", 
                         wb_adr_i, wb_dat_i, wb_sel_i);
            else
                $display("[SYSCTRL] READ:  addr=0x%h, data=0x%h", 
                         wb_adr_i, wb_dat_o);
        end
        
        if (invalid_access && !rst_i) begin
            $warning("SYSCTRL: Invalid access! addr=0x%h, we=%b, sel=%b", 
                     wb_adr_i, wb_we_i, wb_sel_i);
        end
    end
    `endif

endmodule
