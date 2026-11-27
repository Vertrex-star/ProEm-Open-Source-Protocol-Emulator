// =============================================================================
// Project: ProEm - Open Source Protocol Emulator
// File: formal/uart_tx_formal.sv
// Module: uart_tx_formal
// Type: Formal harness (SymbiYosys)
// Hierarchy: uart_tx_formal
// Submodules: uart_tx
// Author: Paul Vincent Bezzina
// Language: SystemVerilog
// Description: Proves every UART frame is a start bit, eight data bits LSB first and a stop bit, each as many clocks long as
// clk_ratio was when the frame started, for every ratio from 1 to 15, with clk_ratio free to change on any clock.
// =============================================================================

module uart_tx_formal (
	input logic clk,
	input logic rst_n,
	input logic [3:0] ratio_in,
	input logic [7:0] tx_data,
	input logic tx_valid
);

// The divider may change on any clock, as LINK can rewrite it at any time; each frame must use the value taken at its start.
logic [3:0] ratio;
logic [3:0] frameRatio;

logic tx_serial;
logic tx_ready;

uart_tx #(
	.RATIO_WIDTH(4)
) dut (
	.clk(clk),
	.rst_n(rst_n),
	.clk_ratio(ratio),
	.tx_data(tx_data),
	.tx_valid(tx_valid),
	.tx_serial(tx_serial),
	.tx_ready(tx_ready)
);

logic started;
logic active;
logic [3:0] bitNum;
logic [3:0] cycle;
logic [7:0] sent;
logic expected;

assign ratio = ratio_in;

// Only the value taken at the start of a frame matters; it is never 0 (LINK 0 selects the auto-baud rate, at least 1).
always_comb begin
	if (tx_valid && tx_ready) begin
		assume (ratio != 0);
	end
end

initial assume (!rst_n);
initial started = 1'b0;

always_ff @(posedge clk) begin
	started <= 1'b1;
end

always_ff @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		active <= 1'b0;
		bitNum <= '0;
		cycle <= '0;
		sent <= '0;
		frameRatio <= 4'd1;
	end else if (!active) begin
		if (tx_valid && tx_ready) begin
			active <= 1'b1;
			bitNum <= '0;
			cycle <= '0;
			sent <= tx_data;
			frameRatio <= ratio;
		end
	end else if (cycle == frameRatio - 1'b1) begin
		cycle <= '0;
		if (bitNum == 4'd9) begin
			active <= 1'b0;
		end else begin
			bitNum <= bitNum + 1'b1;
		end
	end else begin
		cycle <= cycle + 1'b1;
	end
end

always_comb begin
	if (bitNum == 0) begin
		expected = 1'b0;
	end else if (bitNum == 4'd9) begin
		expected = 1'b1;
	end else begin
		expected = sent[bitNum - 1'b1];
	end
end

always_comb begin
	if (started && rst_n) begin
		assert (tx_ready == !active);
		if (active) begin
			assert (tx_serial == expected);
			assert (bitNum <= 4'd9);
			assert (cycle < frameRatio);
		end else begin
			assert (tx_serial == 1'b1);
		end
	end
end

always_comb begin
	if (started && rst_n) begin
		cover (active && bitNum == 4'd9 && cycle == frameRatio - 1'b1 && frameRatio == 4'd3 && ratio == 4'd1 && sent == 8'hA5);
	end
end

endmodule
