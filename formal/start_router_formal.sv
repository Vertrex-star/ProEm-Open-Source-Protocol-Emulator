// =============================================================================
// Project: ProEm - Open Source Protocol Emulator
// File: formal/start_router_formal.sv
// Module: start_router_formal
// Type: Formal harness (SymbiYosys)
// Hierarchy: start_router_formal
// Submodules: start_router
// Author: Paul Vincent Bezzina
// Language: SystemVerilog
// Description: Proves the router against a reference written from the ISA: headers run in order from 1, the first unconfigured
// header ends the list, and headers outside the group are skipped. Under in-order success, at most one running block is ever
// waiting.
// =============================================================================

module start_router_formal (
	input logic [6:0] block_success,
	input logic [6:0] block_configured,
	input logic [6:0] block_active
);

logic [6:0] block_enable;
logic main_enable;

start_router #(
	.blocks(7)
) dut (
	.block_success(block_success),
	.block_configured(block_configured),
	.block_active(block_active),
	.block_enable(block_enable),
	.main_enable(main_enable)
);

logic [6:0] listed;
logic [6:0] runs;
logic [6:0] expectEnable;
logic expectMain;
logic ordered;
logic allDone;
logic [3:0] waiting;
logic lastOk;

// The reference, written from the ISA: a block runs when it is in the header list and in the run's group. Each running block
// is enabled when the running block before it (START for header 1) has succeeded; MAIN when the last running block has.
always_comb begin
	listed[0] = 1'b1;
	runs[0] = 1'b1;
	for (int i = 1; i < 7; i++) begin
		listed[i] = listed[i-1] && block_configured[i];
		runs[i] = listed[i] && block_active[i];
	end
	lastOk = block_success[0];
	expectEnable[0] = 1'b1;
	for (int i = 1; i < 7; i++) begin
		expectEnable[i] = runs[i] && lastOk;
		if (runs[i]) begin
			lastOk = block_success[i];
		end
	end
	expectMain = lastOk;
end

// A frame in progress: a running block has only succeeded if every running block before it has. Under that, at most one
// running block is enabled and still waiting, and MAIN is enabled exactly when every running block has succeeded.
always_comb begin
	ordered = 1'b1;
	allDone = 1'b1;
	waiting = '0;
	for (int i = 0; i < 7; i++) begin
		if (runs[i]) begin
			if (block_success[i] && !allDone) begin
				ordered = 1'b0;
			end
			allDone = allDone && block_success[i];
			if (block_enable[i] && !block_success[i]) begin
				waiting = waiting + 1'b1;
			end
		end
	end
end

always_comb begin
	assert (block_enable == expectEnable);
	assert (main_enable == expectMain);
	// Skipped and unlisted headers are never enabled.
	for (int i = 1; i < 7; i++) begin
		if (!runs[i]) begin
			assert (!block_enable[i]);
		end
	end
	if (ordered) begin
		assert (waiting <= 4'd1);
		assert (main_enable == allDone);
		assert ((waiting == 4'd0) == allDone);
	end
end

always_comb begin
	cover (ordered && block_enable[3] && !block_success[3] && !block_active[2] && block_configured[2]);
	cover (main_enable && !block_configured[2] && block_configured[3]);
end

endmodule
