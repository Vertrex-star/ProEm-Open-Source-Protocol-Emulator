// =============================================================================
// Project: ProEm - Open Source Protocol Emulator
// File: formal/header_counter_formal.sv
// Module: header_counter_formal
// Type: Formal harness (SymbiYosys)
// Hierarchy: header_counter_formal
// Submodules: header_counter
// Author: Paul Vincent Bezzina
// Language: SystemVerilog
// Description: Proves a header compares its bits one at a time against VALUE in the chain's bit order, fails on the first wrong
// bit, keeps the received number with ANY and waits out leading bits with SEEK. Success, fail and push are checked on every
// clock.
// =============================================================================

module header_counter_formal (
	input logic clk,
	input logic rst_n,
	input logic tick,
	input logic configuration,
	input logic [7:0] value,
	input logic [3:0] cyc,
	input logic capture,
	input logic write_config,
	input logic any_config,
	input logic seek_config,
	input logic input_bit,
	input logic msb,
	input logic enable,
	input logic complete,
	input logic abort
);

logic success;
logic fail;
logic configured;
logic writing;
logic [7:0] compare_out;
logic push;
logic [3:0] push_len;

header_counter dut (
	.clk(clk),
	.rst_n(rst_n),
	.tick(tick),
	.configuration(configuration),
	.compare_bit(value),
	.clock_cycles({4'd0, cyc}),
	.capture(capture),
	.write_config(write_config),
	.any_config(any_config),
	.seek_config(seek_config),
	.input_bit(input_bit),
	.msb(msb),
	.enable(enable),
	.complete(complete),
	.abort(abort),
	.success(success),
	.fail(fail),
	.configured(configured),
	.writing(writing),
	.compare_out(compare_out),
	.push(push),
	.push_len(push_len)
);

logic started;
logic refConfigured;
logic order;
logic [7:0] refValue;
logic [3:0] len;
logic refCapture;
logic refWrite;
logic refAny;
logic refSeek;
logic [3:0] idx;
logic [7:0] received;
logic [7:0] nextReceived;
logic expectBit;
logic expectSuccess;
logic expectFail;
logic expectPush;
logic [7:0] lenMask;

// CYC is 1 to 8 for a header (ISA); bit order is fixed while the header is configured.
always_comb begin
	assume (cyc >= 4'd1 && cyc <= 4'd8);
	if (refConfigured && !configuration) begin
		assume (msb == order);
	end
end

initial assume (!rst_n);
initial started = 1'b0;

always_ff @(posedge clk) begin
	started <= 1'b1;
end

assign lenMask = ~(8'hFF << len);
// The bit VALUE says should arrive next: the first bit is the top of the field when MSB first, the bottom when LSB first.
assign expectBit = order ? refValue[len - 1'b1 - idx] : refValue[idx];
// What has been received, as a plain number.
assign nextReceived = order ? {received[6:0], input_bit} : (received | ({7'd0, input_bit} << idx));

always_ff @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		refConfigured <= 1'b0;
		order <= 1'b0;
		refValue <= '0;
		len <= '0;
		refCapture <= 1'b0;
		refWrite <= 1'b0;
		refAny <= 1'b0;
		refSeek <= 1'b0;
		idx <= '0;
		received <= '0;
		expectSuccess <= 1'b0;
		expectFail <= 1'b0;
		expectPush <= 1'b0;
	end else begin
		expectFail <= 1'b0;
		expectPush <= 1'b0;
		if (configuration) begin
			refConfigured <= 1'b1;
			order <= msb;
			refValue <= value;
			len <= cyc;
			refCapture <= capture;
			refWrite <= write_config;
			refAny <= any_config && !write_config;
			refSeek <= seek_config && !write_config && !any_config;
			idx <= '0;
			received <= '0;
			expectSuccess <= 1'b0;
		end else if (complete || abort) begin
			idx <= '0;
			received <= '0;
			expectSuccess <= 1'b0;
		end else if (refWrite) begin
			if (enable && !expectSuccess) begin
				expectSuccess <= 1'b1;
				expectPush <= 1'b1;
			end
		end else if (enable && tick && !expectSuccess && !expectFail) begin
			if (refSeek && idx == 4'd0 && input_bit != expectBit) begin
				// Still waiting for the field's first bit.
			end else if (refAny || input_bit == expectBit) begin
				idx <= idx + 1'b1;
				received <= nextReceived;
				if (idx + 1'b1 == len) begin
					expectSuccess <= 1'b1;
					expectPush <= refCapture;
				end
			end else begin
				expectFail <= 1'b1;
				idx <= '0;
				received <= '0;
			end
		end
	end
end

// The last complete ANY field received, as a plain number; compare_out must show it until the next one completes.
logic [7:0] lastAny;
logic haveAny;

always_ff @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		lastAny <= '0;
		haveAny <= 1'b0;
	end else if (configuration) begin
		haveAny <= 1'b0;
	end else if (!refWrite && refAny && enable && tick && !expectSuccess && !expectFail && idx + 1'b1 == len) begin
		lastAny <= nextReceived;
		haveAny <= 1'b1;
	end
end

always_comb begin
	if (started && rst_n) begin
		assert (configured == refConfigured);
	end
	if (started && rst_n && refConfigured) begin
		assert (success == expectSuccess);
		assert (fail == expectFail);
		assert (push == expectPush);
		assert (writing == refWrite);
		assert (push_len == len);
		if (!refAny) begin
			assert (compare_out == (refValue & lenMask));
		end else if (haveAny && success) begin
			assert (compare_out == (lastAny & lenMask));
		end
	end
end

always_comb begin
	if (started && rst_n && refConfigured) begin
		cover (success && refAny && len == 4'd6 && order && compare_out == 8'h2D);
		cover (fail && idx == 4'd0 && len == 4'd8 && !order);
		cover (success && refSeek && len == 4'd3);
	end
end

endmodule
