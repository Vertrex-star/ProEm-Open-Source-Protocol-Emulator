// =============================================================================
// Project: ProEm - Open Source Protocol Emulator
// File: formal/watchdog_formal.sv
// Module: watchdog_formal
// Type: Formal harness (SymbiYosys)
// Hierarchy: watchdog_formal
// Submodules: watchdog
// Author: Paul Vincent Bezzina
// Language: SystemVerilog
// Description: Proves the watchdog fires exactly WDOG quiet clocks (busy, no tick, no frame reset) after the last activity or
// timeout, and never with a limit of 0. A proved helper invariant ties the internal count to the reference so k-induction
// closes.
// =============================================================================

module watchdog_formal (
	input logic clk,
	input logic rst_n,
	input logic configuration,
	input logic [15:0] clock_limit,
	input logic busy,
	input logic tick,
	input logic frame_reset
);

logic timeout;

watchdog dut (
	.clk(clk),
	.rst_n(rst_n),
	.configuration(configuration),
	.clock_limit(clock_limit),
	.busy(busy),
	.tick(tick),
	.frame_reset(frame_reset),
	.timeout(timeout)
);

logic started;
logic [15:0] limit;
logic [16:0] quiet;
logic quietNow;

// Read from inside the watchdog by the .sby script (connect after flatten). Only used for a helper invariant that is itself proved,
// so that k-induction closes in a few steps instead of walking 65,535 clocks.
logic [15:0] peek_counter;
logic [15:0] peek_limit;

// A clock is quiet when the watchdog should be counting it.
assign quietNow = !configuration && busy && !tick && !frame_reset;

initial assume (!rst_n);
initial started = 1'b0;

always_ff @(posedge clk) begin
	started <= 1'b1;
end

// limit: the last value written. quiet: quiet clocks since the last non-quiet clock or the last timeout seen at the output.
always_ff @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		limit <= '0;
		quiet <= '0;
	end else begin
		if (configuration) begin
			limit <= clock_limit;
		end
		if (!quietNow || (configuration ? clock_limit : limit) == 16'd0) begin
			quiet <= '0;
		end else if (timeout) begin
			quiet <= 17'd1;
		end else begin
			quiet <= quiet + 1'b1;
		end
	end
end

always_comb begin
	if (started && rst_n) begin
		// Never more quiet clocks than the limit without a timeout.
		if (limit != 0) begin
			assert (quiet <= {1'b0, limit});
		end
		// A timeout comes exactly one clock after the limit-th quiet clock, and at no other time.
		assert (timeout == (limit != 0 && quiet == {1'b0, limit}));
		if (limit == 0) begin
			assert (!timeout);
		end
`ifndef MUTATION
		// Helper invariants: the stored limit matches, and the internal count is the reference count (0 right after a timeout).
		// Left out of mutation runs (scripts/mutate.py), so a planted fault is only caught by the spec properties above.
		assert (peek_limit == limit);
		assert ({1'b0, peek_counter} == (timeout ? 17'd0 : quiet));
`endif
	end
end

always_comb begin
	if (started && rst_n) begin
		cover (timeout && limit == 16'd5);
		cover (timeout && limit == 16'd1 && quiet == 17'd1);
	end
end

endmodule
