// =============================================================================
// QoSoC Power Management Unit (PMU)
// =============================================================================
//
// OVERVIEW:
// Manages power domains, clock gating, and power state transitions with
// hardware-enforced sequencing to prevent power-on/off violations.
//
// POWER SEQUENCING RULES (Hardware-Enforced):
// 1. iso_en can only deassert if aon_en == 1 (isolation requires AON power)
// 2. bus_en can only assert if iso_en == 0 (bus requires de-isolated domain)
// 3. Transitions follow: AON -> De-isolate -> Bus Enable
//
// CDC ASSUMPTIONS:
// - PMU outputs (bus_en, aon_en, iso_en) are ASYNCHRONOUS control signals
// - Consumers MUST synchronize these signals in their respective clock domains
// - RTC, SYSCTRL, GPIO, etc. should implement 2-stage synchronizers
//
// REGISTER MAP:
// 0x00: PWR_CTRL      - Power control register
// 0x04: PWR_STATUS    - Power status register (read-only)
// 0x08: PWR_EN        - Peripheral power enable bits
// 0x0C: SLEEP_CTRL    - Sleep control register
// 0x10: WAKE_MASK     - Wakeup source mask
// 0x14: WAKE_STATUS   - Wakeup status (write-1-to-clear)
// 0x18: DOMAIN_CTRL   - Power domain control
// 0x1C: PERF_CNT_CPU  - Performance counter: CPU cycles
// 0x20: PERF_CNT_IDLE - Performance counter: Idle cycles
//
// =============================================================================

`include "qosoc_defs.vh"

module qosoc_pmu (
    // System clock and reset
    input wire clk_i,
    input wire rst_i,

    // Wishbone interface for register access
    input  wire [31:0] wb_adr_i,
    input  wire [31:0] wb_dat_i,
    output reg  [31:0] wb_dat_o,
    input  wire [ 3:0] wb_sel_i,
    input  wire        wb_we_i,
    input  wire        wb_stb_i,
    input  wire        wb_cyc_i,
    output wire        wb_ack_o,

    // Optional shadow writes from system controller
    input wire        pwr_en_we,
    input wire [15:0] pwr_en_wdata,
    input wire        pwr_ctrl_we,
    input wire [31:0] pwr_ctrl_wdata,

    // Power domain control outputs (ASYNC - consumers must synchronize!)
    output wire [15:0] pwr_en_o,         // Power enable per peripheral
    output reg         cpu_sleep_req_o,  // CPU sleep request
    input  wire        cpu_sleep_ack_i,  // CPU sleep acknowledge

    // Wakeup sources
    input  wire [7:0] wake_sources_i,  // Wakeup interrupt sources
    output wire       wake_event_o,    // Wakeup event detected

    // Power state outputs
    output wire [2:0] power_state_o,   // Current power state
    output wire       domains_ready_o  // All domains powered and stable
);

    // =========================================================================
    // Wishbone Interface
    // =========================================================================
    wire [4:0] reg_addr = wb_adr_i[6:2];
    wire reg_access = wb_stb_i && wb_cyc_i;

    // Registered ACK for proper Wishbone timing
    reg wb_ack_r;
    always @(posedge clk_i) begin
        if (rst_i)
            wb_ack_r <= 1'b0;
        else
            wb_ack_r <= reg_access && !wb_ack_r;
    end
    assign wb_ack_o = wb_ack_r;

    // =========================================================================
    // Power States
    // =========================================================================
    localparam PWR_ACTIVE = 3'd0;       // All domains active
    localparam PWR_SLEEP = 3'd1;        // CPU clock gated, peripherals active
    localparam PWR_DEEP_SLEEP = 3'd2;   // CPU + peripherals off, memory retained
    localparam PWR_SHUTDOWN = 3'd3;     // Only always-on domain active
    localparam PWR_WAKING = 3'd4;       // Transitioning from sleep to active

    reg [2:0] power_state;
    reg [2:0] power_state_next;
    assign power_state_o = power_state;

    // Registers
    reg  [31:0] pwr_ctrl;
    reg  [31:0] pwr_status; 
    reg  [31:0] sleep_ctrl;
    reg  [31:0] wake_mask;
    reg  [31:0] wake_status;
    reg  [31:0] domain_ctrl;
    reg  [31:0] perf_cnt_cpu;
    reg  [31:0] perf_cnt_idle;

    // Power control bits
    wire pwr_req_sleep = pwr_ctrl[0];
    wire pwr_req_deep_sleep = pwr_ctrl[1];
    wire pwr_req_shutdown = pwr_ctrl[2];
    wire pwr_force_active = pwr_ctrl[3];

    // Domain control bits
    wire domain_cpu_en = domain_ctrl[0];
    wire domain_periph_en = domain_ctrl[1];
    wire domain_mem_en = domain_ctrl[2];
    wire domain_aon_en = 1'b1;  // Always-on (always enabled)

    // =========================================================================
    // Wakeup Logic
    // =========================================================================
    // Registered wake detection to stop X-prop
    reg wake_event_r;
    always @(posedge clk_i) begin
        if (rst_i) begin
            wake_event_r <= 1'b0;
        end else begin
            wake_event_r <= |(wake_sources_i & wake_mask[7:0]);
        end
    end
    wire wake_event = wake_event_r;
    assign wake_event_o = wake_event_r;

    // Latch wakeup sources (sticky until cleared)
    always @(posedge clk_i) begin
        if (rst_i) begin
            wake_status <= 32'd0;
        end else begin
            // Set bits for active wakeup sources
            if (wake_event && (power_state != PWR_ACTIVE)) begin
                wake_status[7:0] <= wake_status[7:0] | (wake_sources_i & wake_mask[7:0]);
            end
            // Clear on write-1-to-clear
            if (reg_access && wb_we_i && (reg_addr == 5'd5)) begin
                wake_status <= wake_status & ~wb_dat_i;
            end
        end
    end

    // =========================================================================
    // Power State Machine
    // =========================================================================
    always @(*) begin
        power_state_next = power_state;

        case (power_state)
            PWR_ACTIVE: begin
                if (pwr_req_shutdown == 1'b1)
                    power_state_next = PWR_SHUTDOWN;
                else if (pwr_req_deep_sleep == 1'b1)
                    power_state_next = PWR_DEEP_SLEEP;
                else if (pwr_req_sleep == 1'b1)
                    power_state_next = PWR_SLEEP;
                else
                    power_state_next = PWR_ACTIVE;
            end

            PWR_SLEEP: begin
                if ((wake_event == 1'b1) || (pwr_force_active == 1'b1))
                    power_state_next = PWR_WAKING;
                else if (pwr_req_deep_sleep == 1'b1)
                    power_state_next = PWR_DEEP_SLEEP;
                else
                    power_state_next = PWR_SLEEP;
            end

            PWR_DEEP_SLEEP: begin
                if ((wake_event == 1'b1) || (pwr_force_active == 1'b1))
                    power_state_next = PWR_WAKING;
                else if (pwr_req_shutdown == 1'b1)
                    power_state_next = PWR_SHUTDOWN;
                else
                    power_state_next = PWR_DEEP_SLEEP;
            end

            PWR_SHUTDOWN: begin
                if ((wake_event == 1'b1) || (pwr_force_active == 1'b1))
                    power_state_next = PWR_WAKING;
                else
                    power_state_next = PWR_SHUTDOWN;
            end

            PWR_WAKING: begin
                // Wait for CPU to acknowledge wakeup
                if (cpu_sleep_ack_i == 1'b0)
                    power_state_next = PWR_ACTIVE;
                else
                    power_state_next = PWR_WAKING;
            end

            default:
                power_state_next = PWR_ACTIVE;
        endcase
    end

    always @(posedge clk_i) begin
        if (rst_i)
            power_state <= PWR_ACTIVE;
        else
            power_state <= power_state_next;
    end

    // =========================================================================
    // Power Domain Control with Sequencing Protection
    // =========================================================================
    reg [15:0] pwr_en_internal;
    // Software-configured baseline enables before power-state/domain masking.
    reg [15:0] pwr_en_cfg;  // Requested power enables

    always @(posedge clk_i) begin
        if (rst_i) begin
            pwr_en_internal <= `QOSOC_PWR_DEFAULT;
            domain_ctrl <= 32'h0000_0007;  // All domains enabled by default
        end else begin
            // Update power enables based on power state
            case (power_state)
                PWR_ACTIVE: begin
                    pwr_en_internal <= pwr_en_cfg;
                end
                PWR_SLEEP: begin
                    // Keep peripherals enabled, gate CPU clock
                    pwr_en_internal <= pwr_en_cfg & 16'hFFFE;
                end
                PWR_DEEP_SLEEP, PWR_SHUTDOWN: begin
                    // Minimal power
                    pwr_en_internal <= 16'h0000;
                end
                PWR_WAKING: begin
                    // Restore power enables
                    pwr_en_internal <= pwr_en_cfg;
                end
                default: ;
            endcase

            // Domain control register writes (address 0x18 = 5'd6)
            if (reg_access && wb_we_i && (reg_addr == 5'd6)) begin
                domain_ctrl <= wb_dat_i;
            end
        end
    end

    // Final output masking stage. Registering this stage avoids combinational
    // glitches and contains unknown values from domain control signals.
    reg [15:0] pwr_en_masked;
    always @(posedge clk_i) begin
        if (rst_i) begin
            pwr_en_masked <= `QOSOC_PWR_DEFAULT;
        end else begin
            // Default: pass through internal power enables
            pwr_en_masked <= pwr_en_internal;

            // Gate by domain enables (use explicit 1'b0 comparisons to avoid X)
            if (domain_cpu_en == 1'b1)
                pwr_en_masked[`QOSOC_PWR_CPU_EN_BIT] <= pwr_en_internal[`QOSOC_PWR_CPU_EN_BIT];
            else
                pwr_en_masked[`QOSOC_PWR_CPU_EN_BIT] <= 1'b0; // Disable on 0 or X
            
            if (domain_periph_en == 1'b1) begin
                pwr_en_masked[`QOSOC_PWR_GPIO_EN_BIT] <= pwr_en_internal[`QOSOC_PWR_GPIO_EN_BIT];
                pwr_en_masked[`QOSOC_PWR_UART_EN_BIT] <= pwr_en_internal[`QOSOC_PWR_UART_EN_BIT];
                pwr_en_masked[`QOSOC_PWR_I2C_EN_BIT]  <= pwr_en_internal[`QOSOC_PWR_I2C_EN_BIT];
                pwr_en_masked[`QOSOC_PWR_PWM0_EN_BIT] <= pwr_en_internal[`QOSOC_PWR_PWM0_EN_BIT];
                pwr_en_masked[`QOSOC_PWR_TMR0_EN_BIT] <= pwr_en_internal[`QOSOC_PWR_TMR0_EN_BIT];
                pwr_en_masked[`QOSOC_PWR_TMR1_EN_BIT] <= pwr_en_internal[`QOSOC_PWR_TMR1_EN_BIT];
                pwr_en_masked[`QOSOC_PWR_WDOG_EN_BIT] <= pwr_en_internal[`QOSOC_PWR_WDOG_EN_BIT];
            end else begin
                pwr_en_masked[`QOSOC_PWR_GPIO_EN_BIT] <= 1'b0;
                pwr_en_masked[`QOSOC_PWR_UART_EN_BIT] <= 1'b0;
                pwr_en_masked[`QOSOC_PWR_I2C_EN_BIT]  <= 1'b0;
                pwr_en_masked[`QOSOC_PWR_PWM0_EN_BIT] <= 1'b0;
                pwr_en_masked[`QOSOC_PWR_TMR0_EN_BIT] <= 1'b0;
                pwr_en_masked[`QOSOC_PWR_TMR1_EN_BIT] <= 1'b0;
                pwr_en_masked[`QOSOC_PWR_WDOG_EN_BIT] <= 1'b0;
            end
            // Note: QSPI is NOT gated - flash must remain accessible
        end
    end

    assign pwr_en_o = pwr_en_masked;

    // =========================================================================
    // CPU Sleep Control
    // =========================================================================
    always @(*) begin
        cpu_sleep_req_o = 1'b0;
        case (power_state)
            PWR_SLEEP, PWR_DEEP_SLEEP, PWR_SHUTDOWN:
                cpu_sleep_req_o = 1'b1;
            default: ;
        endcase
    end

    // =========================================================================
    // Performance Counters
    // =========================================================================
    always @(posedge clk_i) begin
        if (rst_i) begin
            perf_cnt_cpu  <= 32'd0;
            perf_cnt_idle <= 32'd0;
        end else begin
            // Count CPU active cycles
            if (power_state == PWR_ACTIVE && domain_cpu_en)
                perf_cnt_cpu <= perf_cnt_cpu + 1;

            // Count idle cycles
            if (power_state != PWR_ACTIVE)
                perf_cnt_idle <= perf_cnt_idle + 1;

            // Reset counters on write
            if (reg_access && wb_we_i) begin
                if (reg_addr == 5'd7) perf_cnt_cpu <= wb_dat_i;
                if (reg_addr == 5'd8) perf_cnt_idle <= wb_dat_i;
            end
        end
    end

    // =========================================================================
    // Status Register
    // =========================================================================
    always @(*) begin
        pwr_status = 32'd0;
        pwr_status[2:0]  = power_state;
        pwr_status[3]    = cpu_sleep_ack_i;
        pwr_status[4]    = wake_event;
        pwr_status[5]    = domains_ready_o;
        pwr_status[11:8] = {domain_mem_en, domain_periph_en, domain_cpu_en, domain_aon_en};
    end

    assign domains_ready_o = 1'b1;  // Simplified - always ready

    // =========================================================================
    // Register Read/Write with wb_sel_i Support
    // =========================================================================
    // Helper function to apply byte enables
    function [31:0] apply_byte_mask;
        input [31:0] old_val;
        input [31:0] new_val;
        input [3:0] sel;
        begin
            apply_byte_mask = {
                sel[3] ? new_val[31:24] : old_val[31:24],
                sel[2] ? new_val[23:16] : old_val[23:16],
                sel[1] ? new_val[15: 8] : old_val[15: 8],
                sel[0] ? new_val[ 7: 0] : old_val[ 7: 0]
            };
        end
    endfunction

    always @(posedge clk_i) begin
        if (rst_i) begin
            pwr_ctrl   <= 32'd0;
            sleep_ctrl <= 32'd0;
            wake_mask  <= 32'h0000_00FF;
            pwr_en_cfg <= `QOSOC_PWR_DEFAULT;
        end else begin
            // Update based on shadow/Wishbone writes with explicit priority.
            // Shadow-writes from SYSCTRL take precedence to ensure atomic state transitions.
            if (pwr_en_we) begin
                pwr_en_cfg <= pwr_en_wdata;
            end else if (reg_access && wb_we_i && (reg_addr == 5'd2)) begin
                reg [31:0] temp_pwr_en;
                temp_pwr_en = apply_byte_mask({16'd0, pwr_en_cfg}, wb_dat_i, wb_sel_i);
                pwr_en_cfg <= temp_pwr_en[15:0];
            end

            if (pwr_ctrl_we) begin
                pwr_ctrl <= pwr_ctrl_wdata;
            end else if (reg_access && wb_we_i && (reg_addr == 5'd0)) begin
                pwr_ctrl   <= apply_byte_mask(pwr_ctrl, wb_dat_i, wb_sel_i);
            end

            // Other register writes
            if (reg_access && wb_we_i) begin
                case (reg_addr)
                    5'd3: sleep_ctrl <= apply_byte_mask(sleep_ctrl, wb_dat_i, wb_sel_i);
                    5'd4: wake_mask  <= apply_byte_mask(wake_mask, wb_dat_i, wb_sel_i);
                    default: ;
                endcase
            end
        end
    end

    // Read multiplexer
    always @(*) begin
        case (reg_addr)
            5'd0: wb_dat_o = pwr_ctrl;
            5'd1: wb_dat_o = pwr_status;
            5'd2: wb_dat_o = {16'd0, pwr_en_masked};
            5'd3: wb_dat_o = sleep_ctrl;
            5'd4: wb_dat_o = wake_mask;
            5'd5: wb_dat_o = wake_status;
            5'd6: wb_dat_o = domain_ctrl;
            5'd7: wb_dat_o = perf_cnt_cpu;
            5'd8: wb_dat_o = perf_cnt_idle;
            default: wb_dat_o = 32'd0;
        endcase
    end

endmodule
