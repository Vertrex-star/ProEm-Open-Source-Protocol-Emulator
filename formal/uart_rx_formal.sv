// =============================================================================
// Project: ProEm - Open Source Protocol Emulator
// File: formal/uart_rx_formal.sv
// Module: uart_rx_formal
// Type: Formal harness (SymbiYosys)
// Hierarchy: uart_rx_formal
// Submodules: uart_rx
// Author: Paul Vincent Bezzina
// Language: SystemVerilog
// Description: Proves auto-baud and reception against a reference host sending 0x55 and then any bytes, from 1 clock per bit:
// the receiver locks to the exact ratio and delivers every later byte once, unchanged and in order. With the pin left free, it
// proves events are single, separated and only come after lock.
// =============================================================================

module uart_rx_formal (
	input logic clk,
	input logic rst_n,
	input logic send,
	input logic [7:0] send_data,
	input logic free_line
);

localparam int RW = 4;

(* anyconst *) logic [RW-1:0] ratio;
(* anyconst *) logic ideal;

logic rx_serial;
logic [RW-1:0] clk_ratio;
logic locked;
logic [7:0] rx_data;
logic rx_valid;
logic frame_error;

uart_rx #(
	.RATIO_WIDTH(RW)
) dut (
	.clk(clk),
	.rst_n(rst_n),
	.rx_serial(rx_serial),
	.clk_ratio(clk_ratio),
	.locked(locked),
	.rx_data(rx_data),
	.rx_valid(rx_valid),
	.frame_error(frame_error)
);

logic started;

// Ratios proved. From v0.7.2 the receiver skips the half-bit wait at 1 clock per bit, so the range starts at 1. PDR's run time
// grows quickly with the ratio: the default task proves 1 to 4 in a few minutes, the wide task 1 to 7 in about 15 minutes.
localparam logic [RW-1:0] MIN_RATIO = 4'd1;
`ifdef WIDE
localparam logic [RW-1:0] MAX_RATIO = 4'd7;
`else
localparam logic [RW-1:0] MAX_RATIO = 4'd4;
`endif

always_comb begin
	if (ideal) begin
		assume (ratio >= MIN_RATIO && ratio <= MAX_RATIO);
	end
end

initial assume (!rst_n);
initial started = 1'b0;

always_ff @(posedge clk) begin
	started <= 1'b1;
end

// ---------------------------------------------------------------------------
// Reference host: an exact UART transmitter, ratio clocks per bit. The first frame it sends is always 0x55.
// ---------------------------------------------------------------------------
logic txActive;
logic [3:0] txBit;
logic [RW-1:0] txCycle;
logic [7:0] txByte;
logic txLine;
logic sentFirst;
logic txStart;
logic txEnd;

assign txStart = !txActive && send;
assign txEnd = txActive && txBit == 4'd9 && txCycle == ratio - 1'b1;

always_comb begin
	if (!txActive) begin
		txLine = 1'b1;
	end else if (txBit == 4'd0) begin
		txLine = 1'b0;
	end else if (txBit == 4'd9) begin
		txLine = 1'b1;
	end else begin
		txLine = txByte[txBit - 1'b1];
	end
end

assign rx_serial = ideal ? txLine : free_line;

always_ff @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		txActive <= 1'b0;
		txBit <= '0;
		txCycle <= '0;
		txByte <= '0;
		sentFirst <= 1'b0;
	end else if (txStart) begin
		txActive <= 1'b1;
		txBit <= '0;
		txCycle <= '0;
		txByte <= sentFirst ? send_data : 8'h55;
		sentFirst <= 1'b1;
	end else if (txActive) begin
		if (txCycle == ratio - 1'b1) begin
			txCycle <= '0;
			if (txBit == 4'd9) begin
				txActive <= 1'b0;
			end else begin
				txBit <= txBit + 1'b1;
			end
		end else begin
			txCycle <= txCycle + 1'b1;
		end
	end
end

// ---------------------------------------------------------------------------
// Expected bytes: every frame after the first, in order. A frame is due once its stop bit has been sent.
// ---------------------------------------------------------------------------
logic [7:0] expectQ [0:1];
logic [1:0] expected;
logic [1:0] framesDone;
logic [5:0] sinceEnd;

always_ff @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		expectQ[0] <= '0;
		expectQ[1] <= '0;
		expected <= '0;
		framesDone <= '0;
		sinceEnd <= '0;
	end else begin
		begin : update_expect
			logic [7:0] q0;
			logic [7:0] q1;
			logic [1:0] n;
			q0 = expectQ[0];
			q1 = expectQ[1];
			n = expected;
			if (rx_valid && n != 0) begin
				q0 = q1;
				n = n - 1'b1;
			end
			if (txStart && sentFirst && n != 2'd2) begin
				if (n == 0) q0 = send_data; else q1 = send_data;
				n = n + 1'b1;
			end
			expectQ[0] <= q0;
			expectQ[1] <= q1;
			expected <= n;
		end
		if (txEnd && framesDone != 2'd3) begin
			framesDone <= framesDone + 1'b1;
		end
		if (txEnd) begin
			sinceEnd <= '0;
		end else if (sinceEnd != 6'h3F) begin
			sinceEnd <= sinceEnd + 1'b1;
		end
	end
end

// Gap between receiver events, for the property that holds on any line.
logic [3:0] sinceEvent;

always_ff @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		sinceEvent <= 4'hF;
	end else if (rx_valid || frame_error) begin
		sinceEvent <= '0;
	end else if (sinceEvent != 4'hF) begin
		sinceEvent <= sinceEvent + 1'b1;
	end
end

// Lock state seen at the outputs, for the stability properties.
logic wasLocked;
logic [RW-1:0] lockedRatio;

always_ff @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		wasLocked <= 1'b0;
		lockedRatio <= '0;
	end else if (locked) begin
		wasLocked <= 1'b1;
		lockedRatio <= clk_ratio;
	end
end

always_comb begin
	if (started && rst_n) begin
		// Any line: one event at a time, never on consecutive clocks, and once locked the rate never changes.
		assert (!(rx_valid && frame_error));
		if (rx_valid || frame_error) begin
			assert (sinceEvent != 4'd0);
		end
		if (wasLocked) begin
			assert (locked);
			assert (clk_ratio == lockedRatio);
		end
		if (!locked) begin
			assert (!rx_valid && !frame_error);
		end
		if (ideal) begin
			// Locked to the exact ratio as soon as the 0x55 has been timed, and never a frame error.
			if (framesDone != 0 && sinceEnd >= 6'd4) begin
				assert (locked);
			end
			if (locked) begin
				assert (clk_ratio == ratio);
			end
			assert (!frame_error);
			// Each byte arrives once, in order, unchanged; at most one is ever waiting.
			assert (expected <= 2'd1 || txActive);
			if (txStart && sentFirst) begin
				assert (expected != 2'd2 || rx_valid);
			end
			if (rx_valid) begin
				assert (expected != 0);
				assert (rx_data == expectQ[0]);
			end
		end
	end
end

always_comb begin
	if (started && rst_n) begin
		cover (ideal && rx_valid && rx_data == 8'hA7 && ratio == MIN_RATIO);
		cover (ideal && rx_valid && framesDone == 2'd2 && ratio == MAX_RATIO);
		cover (!ideal && frame_error);
	end
end

endmodule
