// =============================================================================
// QoSoC Integration Note: Third-Party IP
// =============================================================================
//
// OVERVIEW:
// This file is imported IP and is intentionally kept close to upstream
// source code for easier diff/merge against future vendor updates.
//
// LOCAL USAGE:
// OpenCores I2C byte controller used by i2c_master_top.
//
// NOTE:
// Upstream license and attribution comments below are preserved verbatim.
// =============================================================================
/////////////////////////////////////////////////////////////////////
////                                                             ////
////  WISHBONE rev.B2 compliant I2C Master byte-controller       ////
////                                                             ////
////                                                             ////
////  Author: Richard Herveille                                  ////
////          richard@asics.ws                                   ////
////          www.asics.ws                                       ////
////                                                             ////
////  Downloaded from: http://www.opencores.org/projects/i2c/    ////
////                                                             ////
/////////////////////////////////////////////////////////////////////
////                                                             ////
//// Copyright (C) 2001 Richard Herveille                        ////
////                    richard@asics.ws                         ////
////                                                             ////
//// This source file may be used and distributed without        ////
//// restriction provided that this copyright statement is not   ////
//// removed from the file and that any derivative work contains ////
//// the original copyright notice and the associated disclaimer.////
////                                                             ////
////     THIS SOFTWARE IS PROVIDED ``AS IS'' AND WITHOUT ANY     ////
//// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED   ////
//// TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS   ////
//// FOR A PARTICULAR PURPOSE. IN NO EVENT SHALL THE AUTHOR      ////
//// OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,         ////
//// INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES    ////
//// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE   ////
//// GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR        ////
//// BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF  ////
//// LIABILITY, WHETHER IN  CONTRACT, STRICT LIABILITY, OR TORT  ////
//// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT  ////
//// OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE         ////
//// POSSIBILITY OF SUCH DAMAGE.                                 ////
////                                                             ////
/////////////////////////////////////////////////////////////////////

// synopsys translate_off
`include "timescale.v"
// synopsys translate_on

`include "i2c_master_defines.v"

module i2c_master_byte_ctrl (
    input clk_i,
    input rst_i,
    input rst_ni,
    input ena,
    input [15:0] clk_cnt,
    input start,
    input stop,
    input read,
    input write,
    input ack_in,
    input [7:0] din,
    output reg cmd_ack,
    output reg ack_out,
    output i2c_busy,
    output i2c_al,
    output [7:0] dout,
    input scl_i,
    output scl_o,
    output scl_oen,
    input sda_i,
    output sda_o,
    output sda_oen
);

  // signals for bit_controller
  reg [3:0] core_cmd;
  reg       core_txd;
  wire core_ack, core_rxd;

  // signals for shift register
  reg [7:0] sr;  //8bit shift register
  reg shift, ld;

  // signals for state machine
  wire       go;
  reg  [2:0] dcnt;
  wire       cnt_done;

  // hookup bit_controller
  i2c_master_bit_ctrl bit_controller (
      .clk_i  (clk_i),
      .rst_i  (rst_i),
      .rst_ni (rst_ni),
      .ena    (ena),
      .clk_cnt(clk_cnt),
      .cmd    (core_cmd),
      .cmd_ack(core_ack),
      .busy   (i2c_busy),
      .al     (i2c_al),
      .din    (core_txd),
      .dout   (core_rxd),
      .scl_i  (scl_i),
      .scl_o  (scl_o),
      .scl_oen(scl_oen),
      .sda_i  (sda_i),
      .sda_o  (sda_o),
      .sda_oen(sda_oen)
  );

  // generate go-signal
  assign go   = (read | write | stop) & ~cmd_ack;

  // assign dout output to shift-register
  assign dout = sr;

  // generate shift register
  always @(posedge clk_i or negedge rst_ni)
    if (!rst_ni) sr <= 8'h0;
    else if (rst_i) sr <= 8'h0;
    else if (ld) sr <= din;
    else if (shift) sr <= {sr[6:0], core_rxd};

  // generate counter
  always @(posedge clk_i or negedge rst_ni)
    if (!rst_ni) dcnt <= 3'h0;
    else if (rst_i) dcnt <= 3'h0;
    else if (ld) dcnt <= 3'h7;
    else if (shift) dcnt <= dcnt - 3'h1;

  assign cnt_done = ~(|dcnt);

  //
  // state machine
  //
  parameter logic [4:0] ST_IDLE  = 5'b0_0000;
  parameter logic [4:0] ST_START = 5'b0_0001;
  parameter logic [4:0] ST_READ  = 5'b0_0010;
  parameter logic [4:0] ST_WRITE = 5'b0_0100;
  parameter logic [4:0] ST_ACK   = 5'b0_1000;
  parameter logic [4:0] ST_STOP  = 5'b1_0000;

  reg [4:0] c_state;  // synopsys enum_state

  always @(posedge clk_i or negedge rst_ni)
    if (!rst_ni) begin
      core_cmd <= `I2C_CMD_NOP;
      core_txd <= 1'b0;
      shift    <= 1'b0;
      ld       <= 1'b0;
      cmd_ack  <= 1'b0;
      c_state  <= ST_IDLE;
      ack_out  <= 1'b0;
    end else if (rst_i | i2c_al) begin
      core_cmd <= `I2C_CMD_NOP;
      core_txd <= 1'b0;
      shift    <= 1'b0;
      ld       <= 1'b0;
      cmd_ack  <= 1'b0;
      c_state  <= ST_IDLE;
      ack_out  <= 1'b0;
    end else begin
      // initially reset all signals
      core_txd <= sr[7];
      shift    <= 1'b0;
      ld       <= 1'b0;
      cmd_ack  <= 1'b0;

      case (c_state)  // synopsys full_case parallel_case
        ST_IDLE : if (go) begin
          if (start) begin
            c_state  <= ST_START;
            core_cmd <= `I2C_CMD_START;
          end else if (read) begin
            c_state  <= ST_READ;
            core_cmd <= `I2C_CMD_READ;
          end else if (write) begin
            c_state  <= ST_WRITE;
            core_cmd <= `I2C_CMD_WRITE;
          end else  // stop
          begin
            c_state  <= ST_STOP;
            core_cmd <= `I2C_CMD_STOP;
          end

          ld <= 1'b1;
        end

        ST_START : if (core_ack) begin
          if (read) begin
            c_state  <= ST_READ;
            core_cmd <= `I2C_CMD_READ;
          end else begin
            c_state  <= ST_WRITE;
            core_cmd <= `I2C_CMD_WRITE;
          end

          ld <= 1'b1;
        end

        ST_WRITE : if (core_ack)
          if (cnt_done) begin
            c_state  <= ST_ACK;
            core_cmd <= `I2C_CMD_READ;
          end else begin
            c_state  <= ST_WRITE;  // stay in same state
            core_cmd <= `I2C_CMD_WRITE;  // write next bit
            shift    <= 1'b1;
          end

        ST_READ : if (core_ack) begin
          if (cnt_done) begin
            c_state  <= ST_ACK;
            core_cmd <= `I2C_CMD_WRITE;
          end else begin
            c_state  <= ST_READ;  // stay in same state
            core_cmd <= `I2C_CMD_READ;  // read next bit
          end

          shift    <= 1'b1;
          core_txd <= ack_in;
        end

        ST_ACK : if (core_ack) begin
          if (stop) begin
            c_state  <= ST_STOP;
            core_cmd <= `I2C_CMD_STOP;
          end else begin
            c_state  <= ST_IDLE;
            core_cmd <= `I2C_CMD_NOP;

            // generate command acknowledge signal
            cmd_ack  <= 1'b1;
          end

          // assign ack_out output to bit_controller_rxd (contains last received bit)
          ack_out  <= core_rxd;

          core_txd <= 1'b1;
        end else core_txd <= ack_in;

        ST_STOP : if (core_ack) begin
          c_state  <= ST_IDLE;
          core_cmd <= `I2C_CMD_NOP;

          // generate command acknowledge signal
          cmd_ack  <= 1'b1;
        end

        default: ; // lint: case-missing-default
      endcase
    end
endmodule
