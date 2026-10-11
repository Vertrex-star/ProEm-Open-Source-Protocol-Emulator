// =============================================================================
// Project: ProEm - Open Source Protocol Emulator
// File: src/core/frame_chain/crc_unit.sv
// Module: crc_unit
// Type: RTL, core (frame chain)
// Hierarchy: tt_um_vertrex_star_proem > protocol_emulator > emulator_channel > frame_chain > crc_unit
// Submodules: none
// Author: Paul Vincent Bezzina
// Language: SystemVerilog
// Description:
// =============================================================================

module crc_unit (
	input logic clk,
	input logic rst_n,
	input logic cfg_we,
	input logic[3:0] cfg_sel,
	input logic[7:0] cfg_rule,
	input logic[7:0] cfg_high,
	input logic[7:0] cfg_low,
	input logic restart,
	input logic feed,
	input logic[7:0] feed_bits,
	input logic[3:0] feed_len,

	output logic enabled,
	output logic check,
	output logic append,
	output logic[2:0] cover_from,
	output logic[4:0] width,
	output logic good,
	output logic[15:0] crc_out
);

logic[15:0] crc;
logic[15:0] poly;
logic[15:0] residue;
logic[15:0] polyAligned;
logic[15:0] initAligned;
logic[15:0] residueAligned;
logic[15:0] stepped;
logic[3:0] widthLess;
logic[3:0] shift;
logic[2:0] coverFrom;
logic initOnes;
logic crcOn;
logic checkOn;
logic appendOn;
logic invertOn;
logic feedback;
logic reload;

assign shift = 4'd15 - widthLess;
assign polyAligned = poly << shift;
assign initAligned = initOnes ? (16'hFFFF << shift) : 16'h0000;
assign residueAligned = residue << shift;

always_comb begin
	stepped = crc;
	feedback = 1'b0;
	for (int i = 0; i < 8; i++) begin
		if (i < feed_len) begin
			feedback = stepped[15] ^ feed_bits[i];
			stepped = {stepped[14:0], 1'b0} ^ (feedback ? polyAligned : 16'h0000);
		end
	end
end

always_ff@(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		crc <= '0;
		poly <= '0;
		residue <= '0;
		widthLess <= 4'd15;
		coverFrom <= 3'd7;
		initOnes <= 1'b0;
		crcOn <= 1'b0;
		checkOn <= 1'b0;
		appendOn <= 1'b0;
		invertOn <= 1'b0;
		reload <= 1'b0;
	end else begin
		reload <= cfg_we && (cfg_sel == 4'd10 || cfg_sel == 4'd11);
		if (cfg_we && cfg_sel == 4'd10) begin
			widthLess <= cfg_rule[7:4];
			coverFrom <= cfg_rule[3:1];
			initOnes <= cfg_rule[0];
			poly <= {cfg_high, cfg_low};
		end
		if (cfg_we && cfg_sel == 4'd11) begin
			crcOn <= cfg_rule[7];
			checkOn <= cfg_rule[6];
			appendOn <= cfg_rule[5];
			invertOn <= cfg_rule[4];
			residue <= {cfg_high, cfg_low};
		end
		if (restart || reload) begin
			crc <= initAligned;
		end else if (feed && crcOn) begin
			crc <= stepped;
		end
	end
end

assign enabled = crcOn;
assign check = crcOn && checkOn;
assign append = crcOn && appendOn;
assign cover_from = coverFrom;
assign width = {1'b0, widthLess} + 5'd1;
assign good = crcOn && (crc == residueAligned);
assign crc_out = invertOn ? ~crc : crc;

endmodule
