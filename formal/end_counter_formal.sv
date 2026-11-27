// =============================================================================
// Project: ProEm - Open Source Protocol Emulator
// File: formal/end_counter_formal.sv
// Module: end_counter_formal
// Type: Formal harness (SymbiYosys)
// Hierarchy: end_counter_formal
// Submodules: end_counter
// Author: Paul Vincent Bezzina
// Language: SystemVerilog
// Description: Proves END succeeds on exactly the tick where the last LEN bits received equal PATTERN in the chain's bit order,
// and not before LEN bits have arrived. The reference keeps its own history of the received bits.
// =============================================================================

module end_counter_formal (
	input logic clk,
	input logic rst_n,
	input logic tick,
	input logic configuration,
	input logic [15:0] compare_bit,
	input logic [7:0] clock_cycles,
	input logic input_bit,
	input logic msb,
	input logic enable,
	input logic complete,
	input logic abort
);

logic success;

end_counter #(
	.width(16)
) dut (
	.clk(clk),
	.rst_n(rst_n),
	.tick(tick),
	.configuration(configuration),
	.compare_bit(compare_bit),
	.clock_cycles(clock_cycles),
	.input_bit(input_bit),
	.msb(msb),
	.enable(enable),
	.complete(complete),
	.abort(abort),
	.success(success)
);

logic started;
logic configured;
logic orderAtConfig;
logic [15:0] pattern;
logic [4:0] len;
logic [15:0] history;
logic [15:0] nextHistory;
logic [4:0] count;
logic [4:0] nextCount;
logic expectSuccess;
logic matchNext;

// Bit order is set by ORDER before END is written (ISA); the chain holds it still while END is configured.
always_comb begin
	if (configured && !configuration) begin
		assume (msb == orderAtConfig);
	end
end

initial assume (!rst_n);
initial started = 1'b0;

always_ff @(posedge clk) begin
	started <= 1'b1;
end

// history[k] is the bit received k ticks ago (bit 0 the newest); count is how many have arrived, saturating at 16.
assign nextHistory = {history[14:0], input_bit};
assign nextCount = (count == 5'd16) ? count : count + 1'b1;

// The spec: the last len bits match PATTERN as a plain number sent in the chain's order.
always_comb begin
	matchNext = 1'b1;
	for (int k = 0; k < 16; k++) begin
		if (k < len) begin
			if (orderAtConfig) begin
				if (nextHistory[k] != pattern[k]) matchNext = 1'b0;
			end else begin
				if (nextHistory[k] != pattern[len - 1 - k]) matchNext = 1'b0;
			end
		end
	end
end

always_ff @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		configured <= 1'b0;
		orderAtConfig <= 1'b0;
		pattern <= '0;
		len <= 5'd8;
		history <= '0;
		count <= '0;
		expectSuccess <= 1'b0;
	end else if (configuration) begin
		configured <= 1'b1;
		orderAtConfig <= msb;
		pattern <= compare_bit;
		len <= (clock_cycles >= 8'd16) ? 5'd16 : clock_cycles[4:0];
		history <= '0;
		count <= '0;
		expectSuccess <= 1'b0;
	end else if (complete || abort) begin
		history <= '0;
		count <= '0;
		expectSuccess <= 1'b0;
	end else if (enable && tick && !expectSuccess) begin
		history <= nextHistory;
		count <= nextCount;
		if ({1'b0, nextCount} >= {1'b0, len} && matchNext) begin
			expectSuccess <= 1'b1;
		end
	end else if (!enable) begin
		history <= '0;
		count <= '0;
	end
end

always_comb begin
	if (started && rst_n && configured) begin
		assert (success == expectSuccess);
	end
end

always_comb begin
	if (started && rst_n && configured) begin
		cover (success && len == 5'd5 && !orderAtConfig && pattern[4:0] == 5'b10110);
		cover (success && len == 5'd16 && orderAtConfig);
	end
end

endmodule
