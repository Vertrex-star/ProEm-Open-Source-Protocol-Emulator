// =============================================================================
// Project: ProEm - Open Source Protocol Emulator
// File: formal/first_counter_formal.sv
// Module: first_counter_formal
// Type: Formal harness (SymbiYosys)
// Hierarchy: first_counter_formal
// Submodules: first_counter
// Author: Paul Vincent Bezzina
// Language: SystemVerilog
// Description: Proves START end to end from the instruction: with VALUE aligned as the control unit aligns it, START succeeds
// exactly when the last CYC bits on its pin equal VALUE in the chain's bit order. Also proves the condition START, the write
// START, the reported value and the push.
// =============================================================================

module first_counter_formal (
	input logic clk,
	input logic rst_n,
	input logic tick,
	input logic configuration,
	input logic [7:0] value,
	input logic [3:0] cyc,
	input logic [2:0] pin_select,
	input logic capture,
	input logic write_config,
	input logic [7:0] pins,
	input logic msb,
	input logic enable,
	input logic event_mode,
	input logic start_event,
	input logic complete,
	input logic abort
);

logic success;
logic writing;
logic [7:0] compare_out;
logic push;
logic [3:0] push_len;
logic [7:0] compare_bit;

// The control unit's alignment of START's VALUE (control_unit.sv, startValue); control_unit_formal proves cfg_compare is this.
assign compare_bit = (!msb && cyc != 4'd0 && cyc < 4'd8) ? (value << (4'd8 - cyc)) : value;

first_counter dut (
	.clk(clk),
	.rst_n(rst_n),
	.tick(tick),
	.configuration(configuration),
	.compare_bit(compare_bit),
	.clock_cycles({4'd0, cyc}),
	.pin_select(pin_select),
	.capture(capture),
	.write_config(write_config),
	.pins(pins),
	.msb(msb),
	.enable(enable),
	.event_mode(event_mode),
	.start_event(start_event),
	.complete(complete),
	.abort(abort),
	.success(success),
	.writing(writing),
	.compare_out(compare_out),
	.push(push),
	.push_len(push_len)
);

logic started;
logic configured;
logic order;
logic [7:0] refValue;
logic [3:0] refCyc;
logic [3:0] len;
logic [2:0] refPin;
logic refCapture;
logic refWrite;
logic [7:0] history;
logic [7:0] nextHistory;
logic [3:0] count;
logic [3:0] nextCount;
logic bitIn;
logic matchNext;
logic expectSuccess;
logic expectPush;
logic [7:0] lenMask;

always_comb begin
	if (configured && !configuration) begin
		assume (msb == order);
	end
end

initial assume (!rst_n);
initial started = 1'b0;

always_ff @(posedge clk) begin
	started <= 1'b1;
end

assign len = (refCyc >= 4'd8) ? 4'd8 : refCyc;
assign lenMask = ~(8'hFF << len);
assign bitIn = pins[refPin];
assign nextHistory = {history[6:0], bitIn};
assign nextCount = (count == 4'd15) ? count : count + 1'b1;

// history[k] is the bit seen k ticks ago; the last len bits must equal VALUE sent in the chain's order.
always_comb begin
	matchNext = 1'b1;
	for (int k = 0; k < 8; k++) begin
		if (k < len) begin
			if (order) begin
				if (nextHistory[k] != refValue[k]) matchNext = 1'b0;
			end else begin
				if (nextHistory[k] != refValue[len - 1 - k]) matchNext = 1'b0;
			end
		end
	end
end

always_ff @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		configured <= 1'b0;
		order <= 1'b0;
		refValue <= '0;
		refCyc <= '0;
		refPin <= '0;
		refCapture <= 1'b0;
		refWrite <= 1'b0;
		history <= '0;
		count <= '0;
		expectSuccess <= 1'b0;
		expectPush <= 1'b0;
	end else begin
		expectPush <= 1'b0;
		if (configuration) begin
			configured <= 1'b1;
			order <= msb;
			refValue <= value;
			refCyc <= cyc;
			refPin <= pin_select;
			refCapture <= capture;
			refWrite <= write_config;
			history <= '0;
			count <= '0;
			expectSuccess <= 1'b0;
		end else if (complete || abort) begin
			history <= '0;
			count <= '0;
			expectSuccess <= 1'b0;
		end else if (refWrite) begin
			// Write START: succeeds on the first tick and hands its bits to the sender.
			if (tick && !expectSuccess) begin
				expectSuccess <= 1'b1;
				expectPush <= (len != 4'd0);
			end
		end else if (refCyc == 4'd0) begin
			// Condition START: no tick needed.
			if (enable && !expectSuccess && (event_mode ? start_event : (bitIn == refValue[0]))) begin
				expectSuccess <= 1'b1;
			end
		end else if (tick && !expectSuccess) begin
			history <= nextHistory;
			count <= nextCount;
			if (nextCount >= refCyc && matchNext) begin
				expectSuccess <= 1'b1;
				expectPush <= refCapture;
			end
		end
	end
end

always_comb begin
	if (started && rst_n && configured) begin
		assert (success == expectSuccess);
		assert (push == expectPush);
		assert (writing == refWrite);
		assert (push_len == len);
		// The value reported to the host and to BRANCH is VALUE as a plain number in its bottom CYC bits. (On the clock a new
		// configuration is written, ORDER may already be the new one while the stored value is the old one, so that clock is skipped.)
		if (msb == order) begin
			assert (compare_out == (refValue & lenMask));
		end
	end
end

always_comb begin
	if (started && rst_n && configured) begin
		cover (success && !refWrite && refCyc == 4'd5 && !order && refValue[4:0] == 5'b10011);
		cover (success && !refWrite && refCyc == 4'd0);
		cover (push && refWrite);
	end
end

endmodule
