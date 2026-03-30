// =============================================================================
// QoSoC Boot ROM
// =============================================================================
//
// OVERVIEW:
// Wishbone-read-only boot ROM used during early CPU startup. ROM contents are
// encoded as synthesizable combinational cases.
//
// BUS NOTES:
// - Writes are ignored (`wb_we_i` has no functional effect on ROM data).
// - `wb_ack_o` is generated only when `clk_en_i` is active.
// - Address is word-aligned and sized by `WORDS`.
//
// =============================================================================
`include "qosoc_defs.vh"

module qosoc_rom #(
    parameter integer WORDS = 1024
) (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        rst_ni,
    input  wire        clk_en_i,
    input  wire        wb_cyc_i,
    input  wire        wb_stb_i,
    input  wire        wb_we_i,
    input  wire [ 3:0] wb_sel_i,
    input  wire [31:0] wb_adr_i,
    input  wire [31:0] wb_dat_i,
    output reg  [31:0] wb_dat_o,
    output reg         wb_ack_o,
    output wire        wb_stall_o
);
  localparam integer ADDR_LSB = 2;
  localparam integer ADDR_MSB = $clog2(WORDS) + ADDR_LSB - 1;

  assign wb_stall_o = 1'b0;

  // Word index inside the ROM window (byte address shifted by 2).
  wire [ADDR_MSB:ADDR_LSB] addr = wb_adr_i[ADDR_MSB:ADDR_LSB];

  // ROM contents are written as a combinational case so synthesis can map
  // this block either to gates or a ROM macro depending on flow constraints.
  reg [31:0] rom_data;

  always @(*) begin
    case (addr)
      10'd0: rom_data = 32'h10001137;
      10'd1: rom_data = 32'h80010113;
      10'd2: rom_data = 32'h10000517;
      10'd3: rom_data = 32'hFF850513;
      10'd4: rom_data = 32'h10000597;
      10'd5: rom_data = 32'hFF058593;
      10'd6: rom_data = 32'h00B57663;
      10'd7: rom_data = 32'h00052023;
      10'd8: rom_data = 32'hBFDD0511;
      10'd9: rom_data = 32'hA00120FD;
      10'd10: rom_data = 32'h820017B7;
      10'd11: rom_data = 32'h80078793;
      10'd12: rom_data = 32'h169343D8;
      10'd13: rom_data = 32'hDDE300F7;
      10'd14: rom_data = 32'hC7C8FE06;
      10'd15: rom_data = 32'h11618082;
      10'd16: rom_data = 32'hC206C022;
      10'd17: rom_data = 32'h4783842A;
      10'd18: rom_data = 32'hE7890004;
      10'd19: rom_data = 32'h44024092;
      10'd20: rom_data = 32'h80820121;
      10'd21: rom_data = 32'h94634729;
      10'd22: rom_data = 32'h453500E7;
      10'd23: rom_data = 32'h450337F1;
      10'd24: rom_data = 32'h04050004;
      10'd25: rom_data = 32'hB7C537D1;
      10'd26: rom_data = 32'hCC221101;
      10'd27: rom_data = 32'h05934645;
      10'd28: rom_data = 32'h842A3B80;
      10'd29: rom_data = 32'hCE06850A;
      10'd30: rom_data = 32'h2409CA26;
      10'd31: rom_data = 32'h3B000513;
      10'd32: rom_data = 32'h44F13F7D;
      10'd33: rom_data = 32'h009457B3;
      10'd34: rom_data = 32'h07D18BBD;
      10'd35: rom_data = 32'hC503978A;
      10'd36: rom_data = 32'h14F1FEC7;
      10'd37: rom_data = 32'h57F13F51;
      10'd38: rom_data = 32'hFEF496E3;
      10'd39: rom_data = 32'h446240F2;
      10'd40: rom_data = 32'h610544D2;
      10'd41: rom_data = 32'h16378082;
      10'd42: rom_data = 32'h46818200;
      10'd43: rom_data = 32'h06134501;
      10'd44: rom_data = 32'h43258006;
      10'd45: rom_data = 32'h425C4595;
      10'd46: rom_data = 32'hDFF58B85;
      10'd47: rom_data = 32'hF713461C;
      10'd48: rom_data = 32'h02930FF7;
      10'd49: rom_data = 32'hF293FD07;
      10'd50: rom_data = 32'h6A630FF2;
      10'd51: rom_data = 32'hF7930053;
      10'd52: rom_data = 32'h05120FF7;
      10'd53: rom_data = 32'hFD078793;
      10'd54: rom_data = 32'h46858D5D;
      10'd55: rom_data = 32'h0293BFE9;
      10'd56: rom_data = 32'hF293F9F7;
      10'd57: rom_data = 32'hE8630FF2;
      10'd58: rom_data = 32'hF7930055;
      10'd59: rom_data = 32'h05120FF7;
      10'd60: rom_data = 32'hFA978793;
      10'd61: rom_data = 32'h0713B7D5;
      10'd62: rom_data = 32'h7713FBF7;
      10'd63: rom_data = 32'hE8630FF7;
      10'd64: rom_data = 32'hF79300E5;
      10'd65: rom_data = 32'h05120FF7;
      10'd66: rom_data = 32'hFC978793;
      10'd67: rom_data = 32'hD6C5B7F1;
      10'd68: rom_data = 32'h11518082;
      10'd69: rom_data = 32'hC222C406;
      10'd70: rom_data = 32'h17B7C026;
      10'd71: rom_data = 32'h07138200;
      10'd72: rom_data = 32'hA0231B20;
      10'd73: rom_data = 32'h073780E7;
      10'd74: rom_data = 32'h47BD8200;
      10'd75: rom_data = 32'h4785C71C;
      10'd76: rom_data = 32'h57B7C35C;
      10'd77: rom_data = 32'h87938200;
      10'd78: rom_data = 32'h43948007;
      10'd79: rom_data = 32'h1006E693;
      10'd80: rom_data = 32'h4B9CC394;
      10'd81: rom_data = 32'h8F638B85;
      10'd82: rom_data = 32'h478D1007;
      10'd83: rom_data = 32'h0513C35C;
      10'd84: rom_data = 32'h35F53CC0;
      10'd85: rom_data = 32'h200007B7;
      10'd86: rom_data = 32'h373947C8;
      10'd87: rom_data = 32'h3E800513;
      10'd88: rom_data = 32'h17B73DF9;
      10'd89: rom_data = 32'h87938200;
      10'd90: rom_data = 32'h43D88007;
      10'd91: rom_data = 32'hDF758B05;
      10'd92: rom_data = 32'h74134780;
      10'd93: rom_data = 32'h85220FF4;
      10'd94: rom_data = 32'h07933D45;
      10'd95: rom_data = 32'h03630520;
      10'd96: rom_data = 32'hE0630CF4;
      10'd97: rom_data = 32'h07930487;
      10'd98: rom_data = 32'h07630450;
      10'd99: rom_data = 32'hEF6308F4;
      10'd100: rom_data = 32'h47B50087;
      10'd101: rom_data = 32'hFCF404E3;
      10'd102: rom_data = 32'h03F00793;
      10'd103: rom_data = 32'h0CF40163;
      10'd104: rom_data = 32'h0DE347A9;
      10'd105: rom_data = 32'h0513FAF4;
      10'd106: rom_data = 32'hA84140C0;
      10'd107: rom_data = 32'h04800793;
      10'd108: rom_data = 32'h0AF40763;
      10'd109: rom_data = 32'h04A00793;
      10'd110: rom_data = 32'hFEF417E3;
      10'd111: rom_data = 32'h950235ED;
      10'd112: rom_data = 32'h0793BF71;
      10'd113: rom_data = 32'h0BE306A0;
      10'd114: rom_data = 32'hE063FEF4;
      10'd115: rom_data = 32'h07930487;
      10'd116: rom_data = 32'h03630650;
      10'd117: rom_data = 32'h079304F4;
      10'd118: rom_data = 32'h02630680;
      10'd119: rom_data = 32'h079308F4;
      10'd120: rom_data = 32'h12E30570;
      10'd121: rom_data = 32'h35C1FCF4;
      10'd122: rom_data = 32'h3D75842A;
      10'd123: rom_data = 32'h68636785;
      10'd124: rom_data = 32'h07B704F4;
      10'd125: rom_data = 32'h07372000;
      10'd126: rom_data = 32'h98711000;
      10'd127: rom_data = 32'h943EC398;
      10'd128: rom_data = 32'h4398C008;
      10'd129: rom_data = 32'hFE074FE3;
      10'd130: rom_data = 32'h0793A03D;
      10'd131: rom_data = 32'h0B630720;
      10'd132: rom_data = 32'h079302F4;
      10'd133: rom_data = 32'hB7F10770;
      10'd134: rom_data = 32'h77C13579;
      10'd135: rom_data = 32'h07B78D7D;
      10'd136: rom_data = 32'h43982000;
      10'd137: rom_data = 32'hFE074FE3;
      10'd138: rom_data = 32'h90000737;
      10'd139: rom_data = 32'hC3888D59;
      10'd140: rom_data = 32'h4FE34398;
      10'd141: rom_data = 32'h0513FE07;
      10'd142: rom_data = 32'h35113EC0;
      10'd143: rom_data = 32'h0513B705;
      10'd144: rom_data = 32'hBFE53F40;
      10'd145: rom_data = 32'h6785358D;
      10'd146: rom_data = 32'hFEF56BE3;
      10'd147: rom_data = 32'h200007B7;
      10'd148: rom_data = 32'h953E9971;
      10'd149: rom_data = 32'h3D094108;
      10'd150: rom_data = 32'h3FC00513;
      10'd151: rom_data = 32'h0513BFF9;
      10'd152: rom_data = 32'hBFE14000;
      10'd153: rom_data = 32'hC35C4795;
      10'd154: rom_data = 32'h41000513;
      10'd155: rom_data = 32'h44123BC9;
      10'd156: rom_data = 32'h448240A2;
      10'd157: rom_data = 32'h200017B7;
      10'd158: rom_data = 32'h87820131;
      10'd159: rom_data = 32'h00A5C7B3;
      10'd160: rom_data = 32'h02B38B8D;
      10'd161: rom_data = 32'hE7B100C5;
      10'd162: rom_data = 32'hF463478D;
      10'd163: rom_data = 32'h779304C7;
      10'd164: rom_data = 32'h872A0035;
      10'd165: rom_data = 32'hF613EBB9;
      10'd166: rom_data = 32'h06B3FFC2;
      10'd167: rom_data = 32'h079340E6;
      10'd168: rom_data = 32'hC8630200;
      10'd169: rom_data = 32'h86AE06D7;
      10'd170: rom_data = 32'h716387BA;
      10'd171: rom_data = 32'hA30302C7;
      10'd172: rom_data = 32'h07910006;
      10'd173: rom_data = 32'hAE230691;
      10'd174: rom_data = 32'hEAE3FE67;
      10'd175: rom_data = 32'h167DFEC7;
      10'd176: rom_data = 32'h9A718E19;
      10'd177: rom_data = 32'h07110591;
      10'd178: rom_data = 32'h973295B2;
      10'd179: rom_data = 32'h00576663;
      10'd180: rom_data = 32'h872A8082;
      10'd181: rom_data = 32'h02557E63;
      10'd182: rom_data = 32'h0005C783;
      10'd183: rom_data = 32'h05850705;
      10'd184: rom_data = 32'hFEF70FA3;
      10'd185: rom_data = 32'hFEE29AE3;
      10'd186: rom_data = 32'hC6838082;
      10'd187: rom_data = 32'h07050005;
      10'd188: rom_data = 32'h00377793;
      10'd189: rom_data = 32'hFED70FA3;
      10'd190: rom_data = 32'hDFD10585;
      10'd191: rom_data = 32'h0005C683;
      10'd192: rom_data = 32'h77930705;
      10'd193: rom_data = 32'h0FA30037;
      10'd194: rom_data = 32'h0585FED7;
      10'd195: rom_data = 32'hB761FFF9;
      10'd196: rom_data = 32'h11718082;
      10'd197: rom_data = 32'h4194C022;
      10'd198: rom_data = 32'h0085A383;
      10'd199: rom_data = 32'h00C5A303;
      10'd200: rom_data = 32'hC31441C0;
      10'd201: rom_data = 32'hC3404994;
      10'd202: rom_data = 32'h00772423;
      10'd203: rom_data = 32'hA38349C0;
      10'd204: rom_data = 32'h26230185;
      10'd205: rom_data = 32'hCB140067;
      10'd206: rom_data = 32'h01C5A303;
      10'd207: rom_data = 32'h07135194;
      10'd208: rom_data = 32'h28230247;
      10'd209: rom_data = 32'h2E23FE87;
      10'd210: rom_data = 32'h2A23FED7;
      10'd211: rom_data = 32'h06B3FE77;
      10'd212: rom_data = 32'h2C2340E6;
      10'd213: rom_data = 32'h8593FE67;
      10'd214: rom_data = 32'hCEE30245;
      10'd215: rom_data = 32'h86AEFAD7;
      10'd216: rom_data = 32'h716387BA;
      10'd217: rom_data = 32'hA30302C7;
      10'd218: rom_data = 32'h07910006;
      10'd219: rom_data = 32'hAE230691;
      10'd220: rom_data = 32'hEAE3FE67;
      10'd221: rom_data = 32'h167DFEC7;
      10'd222: rom_data = 32'h9A718E19;
      10'd223: rom_data = 32'h07110591;
      10'd224: rom_data = 32'h973295B2;
      10'd225: rom_data = 32'h00576563;
      10'd226: rom_data = 32'h01114402;
      10'd227: rom_data = 32'hC7838082;
      10'd228: rom_data = 32'h07050005;
      10'd229: rom_data = 32'h0FA30585;
      10'd230: rom_data = 32'h87E3FEF7;
      10'd231: rom_data = 32'hC783FEE2;
      10'd232: rom_data = 32'h07050005;
      10'd233: rom_data = 32'h0FA30585;
      10'd234: rom_data = 32'h92E3FEF7;
      10'd235: rom_data = 32'hBFE9FEE2;
      10'd236: rom_data = 32'h00007830;
      10'd237: rom_data = 32'h00000000;
      10'd238: rom_data = 32'h33323130;
      10'd239: rom_data = 32'h37363534;
      10'd240: rom_data = 32'h42413938;
      10'd241: rom_data = 32'h46454443;
      10'd242: rom_data = 32'h00000000;
      10'd243: rom_data = 32'h536F510A;
      10'd244: rom_data = 32'h4220436F;
      10'd245: rom_data = 32'h202D204C;
      10'd246: rom_data = 32'h6D204C44;
      10'd247: rom_data = 32'h0A65646F;
      10'd248: rom_data = 32'h4544454A;
      10'd249: rom_data = 32'h00203A43;
      10'd250: rom_data = 32'h00203E0A;
      10'd251: rom_data = 32'h0A4B4F0A;
      10'd252: rom_data = 32'h00000000;
      10'd253: rom_data = 32'h5252450A;
      10'd254: rom_data = 32'h0000000A;
      10'd255: rom_data = 32'h0000000A;
      10'd256: rom_data = 32'h5720450A;
      10'd257: rom_data = 32'h4A205220;
      10'd258: rom_data = 32'h000A4820;
      10'd259: rom_data = 32'h000A3F0A;
      10'd260: rom_data = 32'h4F4F420A;
      10'd261: rom_data = 32'h00000A54;
      default: rom_data = 32'h00000000;
    endcase
  end

  // Wishbone response policy:
  // - Read-only: writes are acknowledged but ignored.
  // - Single-cycle ACK pulse while `clk_en_i` is high.
  // - Output data is only updated on read transfers.
  always @(posedge clk_i) begin
    if (rst_i) begin
      wb_ack_o <= 1'b0;
      wb_dat_o <= 32'h0;
    end else if (clk_en_i) begin
      wb_ack_o <= wb_cyc_i && wb_stb_i && !wb_ack_o;
      if (wb_cyc_i && wb_stb_i && !wb_we_i) begin
        wb_dat_o <= rom_data;
      end
    end else begin
      wb_ack_o <= 1'b0;
      wb_dat_o <= 32'h0;
    end
  end

endmodule
