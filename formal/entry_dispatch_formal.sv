// =============================================================================
// Project: ProEm - Open Source Protocol Emulator
// File: formal/entry_dispatch_formal.sv
// Module: entry_dispatch_formal
// Type: Formal harness (SymbiYosys)
// Hierarchy: entry_dispatch_formal
// Submodules: frame_buffer, entry_dispatch
// Author: Paul Vincent Bezzina
// Language: SystemVerilog
// Description: Proves the frame buffer and the entry dispatcher together, wired as in the channel: every committed entry leaves
// exactly once, unchanged and in order, on the right port. Every status entry raises frame_mark exactly once, and a flush
// discards wire entries until it.
// =============================================================================

module entry_dispatch_formal (
	input logic clk,
	input logic rst_n,
	input logic wr_en,
	input logic [12:0] din,
	input logic commit,
	input logic commit_all,
	input logic rollback,
	input logic tx_ready,
	input logic host_ready,
	input logic flush,
	input logic pick
);

localparam int DEPTH = 4;

logic full;
logic almost_full;
logic out_empty;
logic [7:0] out_data;
logic [3:0] out_len;
logic out_wire;
logic out_rd_en;
logic tx_valid;
logic [3:0] tx_len;
logic [7:0] tx_data;
logic host_valid;
logic [3:0] host_len;
logic [7:0] host_data;
logic frame_mark;
logic discard;

frame_buffer #(
	.depth(DEPTH),
	.width(13)
) buffer (
	.clk(clk),
	.rst_n(rst_n),
	.wr_en(wr_en),
	.din(din),
	.commit(commit),
	.commit_all(commit_all),
	.rollback(rollback),
	.rd_en(out_rd_en),
	.full(full),
	.almost_full(almost_full),
	.empty(out_empty),
	.dout({out_wire, out_len, out_data})
);

entry_dispatch dut (
	.clk(clk),
	.rst_n(rst_n),
	.out_empty(out_empty),
	.out_data(out_data),
	.out_len(out_len),
	.out_wire(out_wire),
	.tx_ready(tx_ready),
	.host_ready(host_ready),
	.flush(flush),
	.out_rd_en(out_rd_en),
	.tx_valid(tx_valid),
	.tx_len(tx_len),
	.tx_data(tx_data),
	.host_valid(host_valid),
	.host_len(host_len),
	.host_data(host_data),
	.frame_mark(frame_mark),
	.discard(discard)
);

logic started;
logic [3:0] total;
logic [3:0] committed;
logic wrFire;
logic rdFire;
logic routed;
logic held;
logic [1:0] inFlight;
logic flushing;
logic [1:0] marks;

// Tracking one entry from the moment it is written until it leaves the dispatcher.
logic tracking;
logic inBuffer;
logic [12:0] trackedValue;
logic [3:0] trackedPos;
logic [1:0] trackedStage;

assign wrFire = wr_en && !full && !rollback;
assign rdFire = out_rd_en && !out_empty;
assign held = tx_valid || host_valid || discard;
assign routed = (tx_valid && tx_ready) || (host_valid && host_ready) || discard;

initial assume (!rst_n);
initial started = 1'b0;

always_ff @(posedge clk) begin
	started <= 1'b1;
end

// The buffer's own counts (as in frame_buffer_formal), the dispatcher's entries in flight, and the flush window.
always_ff @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		total <= '0;
		committed <= '0;
		inFlight <= '0;
		flushing <= 1'b0;
		marks <= '0;
	end else begin
		total <= (rollback ? committed : total + wrFire) - rdFire;
		if (rollback) begin
			committed <= committed - rdFire;
		end else if (commit_all) begin
			committed <= total + wrFire - rdFire;
		end else if (commit) begin
			committed <= total - rdFire;
		end else begin
			committed <= committed - rdFire;
		end
		inFlight <= inFlight + rdFire - routed;
		if (flush) begin
			flushing <= 1'b1;
		end else if (frame_mark) begin
			flushing <= 1'b0;
		end
		if (routed) begin
			marks <= '0;
		end else if (frame_mark) begin
			marks <= marks + 1'b1;
		end
	end
end

// trackedStage: 0 waiting in the buffer, 1 read and on its way to the dispatcher, 2 held by the dispatcher.
always_ff @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		tracking <= 1'b0;
		trackedValue <= '0;
		trackedPos <= '0;
		trackedStage <= '0;
	end else if (tracking) begin
		case (trackedStage)
			2'd0: begin
				if (rdFire && trackedPos == 0) begin
					trackedStage <= 2'd1;
				end else if (rollback && trackedPos >= committed) begin
					tracking <= 1'b0;
				end else if (rdFire) begin
					trackedPos <= trackedPos - 1'b1;
				end
			end
			2'd1: begin
				trackedStage <= 2'd2;
			end
			default: begin
				if (routed) begin
					tracking <= 1'b0;
				end
			end
		endcase
	end else if (wrFire && pick) begin
		tracking <= 1'b1;
		trackedValue <= din;
		trackedPos <= total - rdFire;
		trackedStage <= 2'd0;
	end
end

assign inBuffer = tracking && trackedStage == 2'd0;

always_comb begin
	if (started && rst_n) begin
		// The buffer behaves as proved on its own.
		assert (committed <= total);
		assert (total <= DEPTH);
		assert (out_empty == (committed == 0));
		// One entry at a time, and one port at a time.
		assert (inFlight <= 2'd1);
		assert ((tx_valid + host_valid + discard) <= 1);
		assert (!(out_rd_en && held));
		if (out_rd_en) begin
			assert (inFlight == 2'd0);
		end
		// No stall: an idle dispatcher reads as soon as a committed entry is waiting.
		if (inFlight == 2'd0 && !out_empty) begin
			assert (out_rd_en);
		end
		// Wire entries go to the sender unless a flush is open, then they are discarded; host entries always go to the host.
		assert (!(tx_valid && flushing));
		assert (!(discard && !flushing));
		// A status entry raises frame_mark exactly once, on the first clock it is held, and frame_mark is never raised otherwise.
		if (frame_mark) begin
			assert (host_valid && host_len == 4'hF);
			assert (marks == 2'd0);
		end
		if (host_valid && host_len == 4'hF && !frame_mark) begin
			assert (marks == 2'd1);
		end
		// The tracked entry leaves unchanged, in order (it is the entry held when it reaches stage 2), on its port.
		if (inBuffer) begin
			assert (trackedPos < total);
		end
		if (tracking && trackedStage == 2'd2) begin
			assert (held);
			if (trackedValue[12]) begin
				assert (tx_valid || discard);
				assert ({tx_len, tx_data} == trackedValue[11:0]);
			end else begin
				assert (host_valid);
				assert ({host_len, host_data} == trackedValue[11:0]);
			end
		end
		if (tracking && trackedStage == 2'd1) begin
			assert (!held);
		end
	end
end

always_comb begin
	if (started && rst_n) begin
		cover (tracking && trackedStage == 2'd2 && discard);
		cover (tracking && trackedStage == 2'd2 && host_valid && host_ready && trackedValue[11:8] == 4'hF);
		cover (tracking && trackedStage == 2'd2 && tx_valid && tx_ready && total == 4'd3);
	end
end

endmodule
