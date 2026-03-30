// =============================================================================
// Module: qosoc_rtc
// Description: Real-Time Clock (RTC) with Calendar and Alarm functions
// =============================================================================
// 
// OVERVIEW:
// This module implements a full-featured Real-Time Clock with:
// - Calendar functionality (seconds, minutes, hours, day, month, year, weekday)
// - Century bit support (valid range: 2000-2199)
// - Alarm matching with per-field enable bits
// - Periodic interrupt generation
// - Clock calibration support
// - Dual clock domain architecture (system clock vs RTC clock)
//
// CLOCK DOMAINS:
// - System Clock (clk): Wishbone bus interface, CDC synchronizers
// - RTC Clock (rtc_clk): Time counters, alarm logic (typically 32.768 kHz)
//
// REGISTER MAP (Wishbone byte addresses):
// 0x00: Control/Status - [7:6]=Reserved, [5]=Century, [4]=PeriodicPending, 
//                        [3]=AlarmPending, [2]=PeriodicEn, [1]=AlarmEn, [0]=Enable
// 0x04: Seconds (0-59)
// 0x08: Minutes (0-59)
// 0x0C: Hours (0-23)
// 0x10: Day (1-31, validated against month)
// 0x14: Month (1-12)
// 0x18: Year (0-99) + Century bit [7]
// 0x1C: Weekday (0-6, 0=Sunday)
// 0x20: Alarm Seconds [6]=Enable, [5:0]=Value
// 0x24: Alarm Minutes [6]=Enable, [5:0]=Value
// 0x28: Alarm Hours [5]=Enable, [4:0]=Value
// 0x2C: Alarm Day [5]=Enable, [4:0]=Value
// 0x30: Subsecond counter (read-only)
// 0x34: Calibration (signed 9-bit adjustment)
//
// LEAP YEAR LOGIC:
// - Standard rule: Divisible by 4 = leap year
// - Century exception: Year 2100 (century=1, year=00) is NOT a leap year
// - This correctly implements the Gregorian calendar for 2000-2199
//
// CDC HANDSHAKE PROTOCOL:
// Writes from system domain to RTC domain use a 4-phase handshake:
// 1. System asserts sys_write_req with address/data
// 2. RTC domain detects request, writes register, asserts rtc_write_ack
// 3. System detects ACK, waits for sync chains to settle, then ACKs bus
// 4. System drops req, RTC drops ack, handshake complete
//
// TIMEOUT PROTECTION:
// A 16-bit watchdog timer protects against RTC clock failure. If the
// handshake doesn't complete within 65,535 system clocks, the bus cycle is
// forcibly acknowledged to prevent system hang.
//
// =============================================================================

module qosoc_rtc #(
    parameter SIM_SPEEDUP = 0  // When 1, use faster counters for simulation
) (
    // Clock and Reset
    input wire clk_i,              // System clock (Wishbone domain)
    input wire rtc_clk_i,          // RTC clock (typically 32.768 kHz)
    input wire rst_i,              // Synchronous reset
    input wire rst_ni,             // Asynchronous reset
    input wire clk_en_i,
    
    // Power Management
    input  wire        bus_en_i,    // Bus power enable
    input  wire        aon_en_i,    // Always-on domain enable
    input  wire        iso_en_i,    // Isolation enable (active high disables access)
    
    // Wishbone Interface
    input  wire        wb_cyc_i,    // Cycle valid
    input  wire        wb_stb_i,    // Strobe
    input  wire        wb_we_i,     // Write enable
    input  wire [ 3:0] wb_sel_i,    // Byte select (partial writes supported via masking)
    input  wire [31:0] wb_adr_i,    // Address
    input  wire [31:0] wb_dat_i,    // Write data
    output reg [31:0] wb_dat_o,    // Read data (gated)
    output reg         wb_ack_o,    // Acknowledge
    output wire        wb_err_o,    // Error (tied low)
    output wire        wb_stall_o,  // Stall (tied low)
    
    // Interrupts
    output wire alarm_irq_o,        // Alarm interrupt (level-sensitive)
    output wire periodic_irq_o      // Periodic interrupt (level-sensitive)
);

    // =========================================================================
    // Wishbone Interface Signals
    // =========================================================================
    assign wb_err_o = 1'b0;      // No error conditions in this implementation
    assign wb_stall_o = 1'b0;    // No pipeline stalls
    
    wire rtc_rst_i;
    qosoc_reset_sync u_rtc_rst_sync (
        .clk_i       (rtc_clk_i),
        .rst_ni      (rst_ni),
        .rst_sync_o  (rtc_rst_i)
    );
    
    // =========================================================================
    // RTC Time Registers (RTC Clock Domain)
    // =========================================================================
    // Synthesis attributes prevent optimization during gate-level simulation
    
    (* keep, syn_preserve = 1 *) reg [5:0] rtc_sec, rtc_min;      // 0-59
    (* keep, syn_preserve = 1 *) reg [4:0] rtc_hour;              // 0-23
    (* keep, syn_preserve = 1 *) reg [6:0] rtc_year;              // 0-99
    (* keep, syn_preserve = 1 *) reg [3:0] rtc_month;             // 1-12
    (* keep, syn_preserve = 1 *) reg [4:0] rtc_day;               // 1-31
    (* keep, syn_preserve = 1 *) reg [2:0] rtc_weekday;           // 0-6 (0=Sunday)
    (* keep, syn_preserve = 1 *) reg rtc_century;                 // 0=2000-2099, 1=2100-2199
    
    // =========================================================================
    // Control and Status Registers (RTC Clock Domain)
    // =========================================================================
    (* keep, syn_preserve = 1 *) reg rtc_enable;           // Master enable for time counting
    (* keep, syn_preserve = 1 *) reg rtc_alarm_en;         // Alarm interrupt enable
    (* keep, syn_preserve = 1 *) reg rtc_periodic_en;      // Periodic interrupt enable
    (* keep, syn_preserve = 1 *) reg rtc_alarm_pending;    // Alarm triggered (write 1 to clear)
    (* keep, syn_preserve = 1 *) reg rtc_periodic_pending; // Periodic tick occurred (write 1 to clear)
    
    // =========================================================================
    // Alarm Registers (RTC Clock Domain)
    // =========================================================================
    // Each field has an enable bit. Alarm triggers when ALL enabled fields match.
    // Disabled fields are ignored (wildcard match).
    
    (* keep, syn_preserve = 1 *) reg [ 5:0] rtc_alarm_sec, rtc_alarm_min;
    (* keep, syn_preserve = 1 *) reg [ 4:0] rtc_alarm_hour, rtc_alarm_day;
    (* keep, syn_preserve = 1 *) reg rtc_alarm_sec_en, rtc_alarm_min_en;
    (* keep, syn_preserve = 1 *) reg rtc_alarm_hour_en, rtc_alarm_day_en;
    
    // =========================================================================
    // Calibration and Subsecond Counters (RTC Clock Domain)
    // =========================================================================
    reg signed [8:0] rtc_calib;                    // Signed calibration value
    (* keep, syn_preserve = 1 *) reg [14:0] calib_counter;   // Calibration application counter
    (* keep, syn_preserve = 1 *) reg [14:0] subsec_cnt;      // Subsecond tick counter
    
    // =========================================================================
    // Rollover Flags (Combinational, used in time_counter_block)
    // =========================================================================
    // These flags are computed using blocking assignments to determine
    // cascaded rollover behavior (sec->min->hour->day->month->year)
    reg sec_rollover, min_rollover, hour_rollover, day_rollover, month_rollover;

    // =========================================================================
    // Clock Domain Crossing (CDC) Synchronizers - RTC to System Domain
    // =========================================================================
    // Three-stage synchronizer chains for metastability protection
    // Index [0] = first stage, [1] = second stage, [2] = stable output
    
    (* keep, syn_preserve = 1 *) reg [5:0] s_sec[0:2];
    (* keep, syn_preserve = 1 *) reg [5:0] s_min[0:2];
    (* keep, syn_preserve = 1 *) reg [4:0] s_hour[0:2];
    (* keep, syn_preserve = 1 *) reg [4:0] s_day[0:2];
    (* keep, syn_preserve = 1 *) reg [3:0] s_month[0:2];
    (* keep, syn_preserve = 1 *) reg [6:0] s_year[0:2];
    (* keep, syn_preserve = 1 *) reg [2:0] s_weekday[0:2];
    (* keep, syn_preserve = 1 *) reg [14:0] s_subsec[0:2];
    (* keep, syn_preserve = 1 *) reg s_century[0:2];
    
    // Interrupt and enable synchronizers (shift register style)
    (* keep, syn_preserve = 1 *) reg [2:0] s_al_p, s_pe_p;              // Alarm/Periodic pending
    (* keep, syn_preserve = 1 *) reg [1:0] rtc_al_e_sync, rtc_pe_e_sync, rtc_en_s;  // Enable syncs
    
    // =========================================================================
    // CDC Handshake Signals - System to RTC Domain Write Path
    // =========================================================================
    // Write handshake protocol:
    // sys_write_req: System asserts to request write
    // rtc_write_ack: RTC domain asserts when write complete
    // sys_write_active: System FSM state tracking
    
    reg [31:0] sys_write_data;                              // Write data (system domain)
    reg [ 3:0] sys_write_addr;                              // Write address (system domain)
    (* keep, syn_preserve = 1 *) reg sys_write_req;         // Write request (system domain)
    (* keep, syn_preserve = 1 *) reg sys_write_active;      // Write FSM active (system domain)
    (* keep, syn_preserve = 1 *) reg [1:0] sys_write_ack_sync;  // ACK synchronizer (system domain)
    (* keep, syn_preserve = 1 *) reg [1:0] rtc_write_req_sync;  // REQ synchronizer (RTC domain)
    (* keep, syn_preserve = 1 *) reg rtc_write_ack;         // Write acknowledge (RTC domain)
    reg [1:0] write_fsm_wait;                               // Wait counter for sync settling
    reg [15:0] handshake_timer;                             // Timeout watchdog (65535 cycles)

    // =========================================================================
    // Wishbone Access Decode
    // =========================================================================
    wire access = wb_cyc_i && wb_stb_i && bus_en_i && !iso_en_i;
    wire write = access && wb_we_i;
    wire read = access && !wb_we_i;

    // =========================================================================
    // Read Data Bundling (for clarity and maintainability)
    // =========================================================================
    // These wires extract the synchronized values for register reads
    wire rd_enable   = rtc_en_s[1];
    wire rd_alarm_e  = rtc_al_e_sync[1];
    wire rd_periodic_e = rtc_pe_e_sync[1];
    wire rd_al_pending = s_al_p[2];
    wire rd_pe_pending = s_pe_p[2];
    wire rd_century = s_century[2];

    integer i;  // Loop variable for synchronizer reset
    
    // =========================================================================
    // SYSTEM CLOCK DOMAIN - CDC Synchronizers
    // =========================================================================
    // This block implements three-stage synchronizers for all signals crossing
    // from the RTC clock domain to the system clock domain. The three stages
    // provide metastability protection.
    
    always @(posedge clk_i) begin : system_cdc
        if (rst_i) begin
            // Reset all synchronizer stages
            for (i=0; i<3; i=i+1) begin
                s_sec[i]<=0; s_min[i]<=0; s_hour[i]<=0; 
                s_day[i]<=1; s_month[i]<=1; s_year[i]<=0; 
                s_weekday[i]<=0; s_subsec[i]<=0;
                s_century[i]<=0;
            end
            s_al_p<=0; s_pe_p<=0; sys_write_ack_sync<=0;
            rtc_al_e_sync <= 0; rtc_pe_e_sync <= 0; rtc_en_s <= 0;
        end else begin
            // Shift register implementation for time value synchronizers
            s_sec[0] <= rtc_sec; s_sec[1] <= s_sec[0]; s_sec[2] <= s_sec[1];
            s_min[0] <= rtc_min; s_min[1] <= s_min[0]; s_min[2] <= s_min[1];
            s_hour[0] <= rtc_hour; s_hour[1] <= s_hour[0]; s_hour[2] <= s_hour[1];
            s_day[0] <= rtc_day; s_day[1] <= s_day[0]; s_day[2] <= s_day[1];
            s_month[0] <= rtc_month; s_month[1] <= s_month[0]; s_month[2] <= s_month[1];
            s_year[0] <= rtc_year; s_year[1] <= s_year[0]; s_year[2] <= s_year[1];
            s_weekday[0] <= rtc_weekday; s_weekday[1] <= s_weekday[0]; s_weekday[2] <= s_weekday[1];
            s_subsec[0] <= subsec_cnt; s_subsec[1] <= s_subsec[0]; s_subsec[2] <= s_subsec[1];
            s_century[0] <= rtc_century; s_century[1] <= s_century[0]; s_century[2] <= s_century[1];
            
            // Shift register for interrupt pending flags
            s_al_p <= {s_al_p[1:0], rtc_alarm_pending};
            s_pe_p <= {s_pe_p[1:0], rtc_periodic_pending};
            
            // Two-stage synchronizers for enable signals (system to RTC direction)
            rtc_al_e_sync <= {rtc_al_e_sync[0], rtc_alarm_en};
            rtc_pe_e_sync <= {rtc_pe_e_sync[0], rtc_periodic_en};
            rtc_en_s <= {rtc_en_s[0], rtc_enable};
            
            // Synchronize write acknowledge from RTC domain
            sys_write_ack_sync <= {sys_write_ack_sync[0], rtc_write_ack};
        end
    end

    // =========================================================================
    // SYSTEM CLOCK DOMAIN - Wishbone Bus Interface
    // =========================================================================
    // This block handles:
    // 1. Wishbone bus protocol (read/write cycles)
    // 2. Write handshake FSM to RTC domain
    // 3. Timeout watchdog for hung handshakes
    // 4. Byte-enable masking for partial writes
    
    reg wb_ack_r;  // Tracks whether we've already acknowledged this cycle
    
    always @(posedge clk_i) begin : system_bus
        if (rst_i) begin
            wb_ack_o <= 0; wb_ack_r <= 0;
            sys_write_req <= 0; sys_write_active <= 0;
            sys_write_addr <= 0; sys_write_data <= 0;
            write_fsm_wait <= 0;
            handshake_timer <= 0;
        end else begin
            // =================================================================
            // WRITE PATH - CDC Handshake FSM
            // =================================================================
            if (write) begin
                // Phase 1: Initiate write handshake
                // Wait for bridge to be idle before starting new transaction
                if (!sys_write_active && !sys_write_ack_sync[1] && !wb_ack_r) begin
                    sys_write_req <= 1;
                    sys_write_active <= 1;
                    sys_write_addr <= wb_adr_i[5:2];  // Word-aligned address
                    
                    // Mask write data based on byte enables
                    // Unselected bytes are forced to 0 (no read-modify-write)
                    sys_write_data <= {
                        (wb_sel_i[3] ? wb_dat_i[31:24] : 8'h00),
                        (wb_sel_i[2] ? wb_dat_i[23:16] : 8'h00),
                        (wb_sel_i[1] ? wb_dat_i[15: 8] : 8'h00),
                        (wb_sel_i[0] ? wb_dat_i[ 7: 0] : 8'h00)
                    };
                    write_fsm_wait <= 0;
                    handshake_timer <= 0;
                end

                // Phase 2: Timeout watchdog
                // If RTC clock is dead or handshake hangs, force ACK after timeout.
                if (sys_write_active && sys_write_req && !sys_write_ack_sync[1]) begin
                    if (handshake_timer == 16'hFFFF) begin
                        sys_write_req <= 0;  // Abort request
                        wb_ack_o <= 1;       // Force ACK to release bus
                        wb_ack_r <= 1;
                    end else begin
                        handshake_timer <= handshake_timer + 1;
                    end
                end
                
                // Phase 3: RTC domain acknowledged
                // Wait 4 system clocks for synchronizer chains to settle
                // before acknowledging the bus transaction
                if (sys_write_active && sys_write_req && sys_write_ack_sync[1] && !wb_ack_r) begin
                    if (write_fsm_wait == 2'd3) begin
                        wb_ack_o <= 1;
                        wb_ack_r <= 1;
                    end else begin
                        write_fsm_wait <= write_fsm_wait + 1'b1;
                    end
                end
            end else if (read) begin
                // Read path: Single-cycle acknowledge (data is always synchronized)
                wb_ack_o <= access && !wb_ack_r;
                wb_ack_r <= access;
            end
            
            // If a cycle arrives while access is blocked by power/isolation,
            // return an ACK so the Wishbone master does not hang.
            if (wb_cyc_i && wb_stb_i && !access && !wb_ack_o) begin
                wb_ack_o <= 1'b1;
                // wb_ack_r not needed if we ACK immediately and master drops strobe
            end
            
            // Clear ACK and tracking when bus cycle ends
            if (!access) begin
                wb_ack_o <= 0;
                wb_ack_r <= 0;
                // Phase 4: Drop request only after bus cycle completes
                if (sys_write_active && sys_write_req) sys_write_req <= 0;
            end
            
            // Phase 5: Wait for handshake bridge to fully reset
            if (sys_write_active && !sys_write_req && !sys_write_ack_sync[1]) begin
                sys_write_active <= 0;
            end
        end
    end

    // =================================================================
    // READ PATH - Register Multiplexer
    // =================================================================
    reg [31:0] wb_dat_o_reg;
    assign wb_dat_o = bus_en_i ? wb_dat_o_reg : 32'h0;

    always @(*) begin
        wb_dat_o_reg = 32'h0;
        if (read) begin
            case (wb_adr_i[5:2])
                4'd0: wb_dat_o_reg = {24'h0, 2'b0, rd_century, rd_pe_pending, 
                                  rd_al_pending, rd_periodic_e, rd_alarm_e, rd_enable};
                4'd1: wb_dat_o_reg = {26'h0, s_sec[2]};       // Seconds
                4'd2: wb_dat_o_reg = {26'h0, s_min[2]};       // Minutes
                4'd3: wb_dat_o_reg = {27'h0, s_hour[2]};      // Hours
                4'd4: wb_dat_o_reg = {27'h0, s_day[2]};       // Day
                4'd5: wb_dat_o_reg = {28'h0, s_month[2]};     // Month
                4'd6: wb_dat_o_reg = {24'h0, rd_century, s_year[2]};  // Year + Century bit
                4'd7: wb_dat_o_reg = {29'h0, s_weekday[2]};   // Weekday
                4'd8: wb_dat_o_reg = {25'h0, rtc_alarm_sec_en, rtc_alarm_sec};
                4'd9: wb_dat_o_reg = {25'h0, rtc_alarm_min_en, rtc_alarm_min};
                4'd10: wb_dat_o_reg = {26'h0, rtc_alarm_hour_en, rtc_alarm_hour};
                4'd11: wb_dat_o_reg = {26'h0, rtc_alarm_day_en, rtc_alarm_day};
                4'd12: wb_dat_o_reg = {17'h0, s_subsec[2]};   // Subsecond counter
                4'd13: wb_dat_o_reg = {{23{rtc_calib[8]}}, rtc_calib};  // Calibration (sign-extended)
                default: wb_dat_o_reg = 32'h0;
            endcase
        end
    end
    
    // =========================================================================
    // Interrupt Output Generation
    // =========================================================================
    // Level-sensitive interrupts based on enable AND pending flags
    // Hard gating with system reset to stop X-prop during boot
    assign alarm_irq_o = !rst_i && rtc_al_e_sync[1] && s_al_p[2];
    assign periodic_irq_o = !rst_i && rtc_pe_e_sync[1] && s_pe_p[2];

    // =========================================================================
    // RTC CLOCK DOMAIN - Write Request Synchronizer
    // =========================================================================
    // Two-stage synchronizer for write request from system domain
    always @(posedge rtc_clk_i or posedge rtc_rst_i) begin
        if (rtc_rst_i) begin
            rtc_write_req_sync <= 0;
        end else begin
            rtc_write_req_sync <= {rtc_write_req_sync[0], sys_write_req};
        end
    end
    
    // Detect rising edge of synchronized request (pulse generation)
    wire rtc_write_pulse = rtc_write_req_sync[1] && !rtc_write_ack;

    // =========================================================================
    // RTC CLOCK DOMAIN - Days-in-Month Calculation
    // =========================================================================
    // Combinational logic - remains as is
    
    reg [4:0] dim;  // Days in month
    
    always @(*) begin
        case (rtc_month)
            4'd4, 4'd6, 4'd9, 4'd11: dim = 30;
            4'd2: begin
                if (rtc_year[1:0] == 2'b00) begin
                    if (rtc_century == 1'b1 && rtc_year == 7'd00) 
                        dim = 28;
                    else 
                        dim = 29;
                end else 
                    dim = 28;
            end
            default: dim = 31;
        endcase
    end

    // =========================================================================
    // RTC CLOCK DOMAIN - Next State Prediction for Alarm Matching
    // =========================================================================
    // Combinational logic - remains as is
    
    reg [5:0] next_sec, next_min;
    reg [4:0] next_hour, next_day;
    
    always @(*) begin
        next_sec = rtc_sec; 
        next_min = rtc_min; 
        next_hour = rtc_hour; 
        next_day = rtc_day;
        
        if (subsec_cnt >= (SIM_SPEEDUP ? 15'd31 : 15'd32767)) begin
            if (rtc_sec >= 59) begin
                next_sec = 0;
                if (rtc_min >= 59) begin
                    next_min = 0;
                    if (rtc_hour >= 23) begin
                        next_hour = 0;
                        if (rtc_day >= dim) 
                            next_day = 1;
                        else 
                            next_day = rtc_day + 1;
                    end else 
                        next_hour = rtc_hour + 1;
                end else 
                    next_min = rtc_min + 1;
            end else 
                next_sec = rtc_sec + 1;
        end
    end

    // =========================================================================
    // RTC CLOCK DOMAIN - Configuration and Alarm Logic
    // =========================================================================
    always @(posedge rtc_clk_i or posedge rtc_rst_i) begin : rtc_bus_interface
        if (rtc_rst_i) begin
            rtc_enable <= 0; rtc_alarm_en <= 0; rtc_periodic_en <= 0;
            rtc_alarm_pending <= 0; rtc_periodic_pending <= 0;
            rtc_alarm_sec <= 0; rtc_alarm_min <= 0; rtc_alarm_hour <= 0; rtc_alarm_day <= 1;
            rtc_alarm_sec_en <= 0; rtc_alarm_min_en <= 0; 
            rtc_alarm_hour_en <= 0; rtc_alarm_day_en <= 0;
            rtc_calib <= 0; 
            rtc_write_ack <= 0;
        end else begin
            if (rtc_write_pulse) begin
                rtc_write_ack <= 1'b1;
                case (sys_write_addr)
                    4'd0: begin
                        rtc_enable <= sys_write_data[0];
                        rtc_alarm_en <= sys_write_data[1];
                        rtc_periodic_en <= sys_write_data[2];
                        if (sys_write_data[3]) rtc_alarm_pending <= 1'b0;
                        if (sys_write_data[4]) rtc_periodic_pending <= 1'b0;
                    end
                    4'd8: begin
                        if(sys_write_data[5:0] <= 6'd59) rtc_alarm_sec <= sys_write_data[5:0]; 
                        rtc_alarm_sec_en <= sys_write_data[6];
                    end
                    4'd9: begin 
                        if(sys_write_data[5:0] <= 6'd59) rtc_alarm_min <= sys_write_data[5:0]; 
                        rtc_alarm_min_en <= sys_write_data[6]; 
                    end
                    4'd10: begin 
                        if(sys_write_data[4:0] <= 5'd23) rtc_alarm_hour <= sys_write_data[4:0]; 
                        rtc_alarm_hour_en <= sys_write_data[5]; 
                    end
                    4'd11: begin 
                        if(sys_write_data[4:0] >= 5'd1 && sys_write_data[4:0] <= dim) rtc_alarm_day <= sys_write_data[4:0]; 
                        rtc_alarm_day_en <= sys_write_data[5]; 
                    end
                    4'd13: rtc_calib <= sys_write_data[8:0];
                    default: ;
                endcase
            end else if (!rtc_write_req_sync[1]) begin
                rtc_write_ack <= 1'b0;
            end
            
            if (rtc_enable && aon_en_i && (subsec_cnt >= (SIM_SPEEDUP ? 15'd31 : 15'd32767)))
                rtc_periodic_pending <= 1'b1;
                
            if (rtc_enable && aon_en_i && (subsec_cnt >= (SIM_SPEEDUP ? 15'd31 : 15'd32767))) begin
                if ((!rtc_alarm_sec_en || (next_sec == rtc_alarm_sec)) && 
                    (!rtc_alarm_min_en || (next_min == rtc_alarm_min)) && 
                    (!rtc_alarm_hour_en || (next_hour == rtc_alarm_hour)) && 
                    (!rtc_alarm_day_en || (next_day == rtc_alarm_day)))
                    rtc_alarm_pending <= 1'b1;
            end
        end
    end

    // =========================================================================
    // RTC CLOCK DOMAIN - Calibration and Subsecond Counters
    // =========================================================================
    always @(posedge rtc_clk_i or posedge rtc_rst_i) begin : counter_block
        if (rtc_rst_i) begin
            calib_counter <= 0;
            subsec_cnt <= 0;
        end else begin
            if (rtc_write_pulse && (sys_write_addr >= 4'd1 && sys_write_addr <= 4'd7)) begin
                subsec_cnt <= 0;
            end else if (rtc_enable && aon_en_i) begin
                if (calib_counter >= (SIM_SPEEDUP ? 15'd127 : 15'd32767)) begin
                    calib_counter <= 15'd0;
                    subsec_cnt <= subsec_cnt + {{6{rtc_calib[8]}}, rtc_calib};
                end else begin
                    calib_counter <= calib_counter + 1'b1;
                    if (subsec_cnt >= (SIM_SPEEDUP ? 15'd31 : 15'd32767))
                        subsec_cnt <= 15'd0;
                    else
                        subsec_cnt <= subsec_cnt + 1'b1;
                end
            end
        end
    end

    // =========================================================================
    // RTC CLOCK DOMAIN - Time Counter Logic
    // =========================================================================
    always @(posedge rtc_clk_i or posedge rtc_rst_i) begin : time_counter_block
        if (rtc_rst_i) begin
            rtc_sec <= 0; rtc_min <= 0; rtc_hour <= 0; rtc_day <= 1;
            rtc_month <= 1; rtc_year <= 0; 
            rtc_weekday <= 6;
            rtc_century <= 0;
        end else begin
            if (rtc_write_pulse) begin
                case (sys_write_addr)
                    4'd1: if (sys_write_data[5:0] <= 59) rtc_sec <= sys_write_data[5:0];
                    4'd2: if (sys_write_data[5:0] <= 59) rtc_min <= sys_write_data[5:0];
                    4'd3: if (sys_write_data[4:0] <= 23) rtc_hour <= sys_write_data[4:0];
                    4'd4: if (sys_write_data[4:0] >= 1 && sys_write_data[4:0] <= dim) 
                              rtc_day <= sys_write_data[4:0];
                    4'd5: if (sys_write_data[3:0] >= 1 && sys_write_data[3:0] <= 12) 
                              rtc_month <= sys_write_data[3:0];
                    4'd6: if (sys_write_data[6:0] <= 99) begin 
                              rtc_year <= sys_write_data[6:0]; 
                              rtc_century <= sys_write_data[7];
                          end
                    4'd7: if (sys_write_data[2:0] <= 6) rtc_weekday <= sys_write_data[2:0];
                    default: ;
                endcase
            end
            else if (rtc_enable && aon_en_i && (subsec_cnt >= (SIM_SPEEDUP ? 15'd31 : 15'd32767))) begin
                // Non-blocking update of temporary rollover flags is not allowed, 
                // but we can compute them as variables or wires.
                // For minimal change, kept logic structure but fixed sensitivity.
                if (rtc_sec >= 6'd59) begin
                    rtc_sec <= 6'd0;
                    if (rtc_min >= 6'd59) begin
                        rtc_min <= 6'd0;
                        if (rtc_hour >= 5'd23) begin
                            rtc_hour <= 5'd0;
                            rtc_weekday <= (rtc_weekday >= 6) ? 3'd0 : rtc_weekday + 1'b1;
                            if (rtc_day >= dim) begin
                                rtc_day <= 5'd1;
                                if (rtc_month >= 4'd12) begin
                                    rtc_month <= 4'd1;
                                    if (rtc_year >= 99) begin
                                        rtc_year <= 7'd0;
                                        rtc_century <= ~rtc_century;
                                    end else rtc_year <= rtc_year + 1'b1;
                                end else rtc_month <= rtc_month + 1'b1;
                            end else rtc_day <= rtc_day + 1'b1;
                        end else rtc_hour <= rtc_hour + 1'b1;
                    end else rtc_min <= rtc_min + 1'b1;
                end else rtc_sec <= rtc_sec + 1'b1;
            end
        end
    end
endmodule