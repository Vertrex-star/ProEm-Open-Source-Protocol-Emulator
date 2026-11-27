// =============================================================================
// Project: ProEm - Open Source Protocol Emulator
// File: formal/return_path_formal.sv
// Module: return_path_formal
// Type: Formal harness (SymbiYosys)
// Hierarchy: return_path_formal
// Submodules: return_path (with its uart_tx)
// Author: Paul Vincent Bezzina
// Language: SystemVerilog
// Description: Proves every byte handed to the return UART is the next byte of the accepted messages in the ISA's two-byte
// format, sources are served in turn so none waits behind more than two messages, and every link event is reported once. The
// line task also decodes the serial pin, bounded.
// =============================================================================

module return_path_formal (
	input logic clk,
	input logic rst_n,
	input logic a_valid,
	input logic [3:0] a_len,
	input logic [7:0] a_data,
	input logic b_valid,
	input logic [3:0] b_len,
	input logic [7:0] b_data,
	input logic [3:0] events
);

(* anyconst *) logic [3:0] ratio;

logic a_ready;
logic b_ready;
logic tx_serial;

return_path #(
	.RATIO_WIDTH(4)
) dut (
	.clk(clk),
	.rst_n(rst_n),
	.clk_ratio(ratio),
	.a_valid(a_valid),
	.a_len(a_len),
	.a_data(a_data),
	.b_valid(b_valid),
	.b_len(b_len),
	.b_data(b_data),
	.events(events),
	.a_ready(a_ready),
	.b_ready(b_ready),
	.tx_serial(tx_serial)
);

logic started;

// The byte stream between return_path and its uart_tx, read by the .sby script (connect after flatten). uart_tx_formal proves that
// every byte accepted here goes out on tx_serial exactly; this proof checks that the accepted bytes are the right ones.
logic [7:0] peek_byte;
logic peek_valid;
logic peek_ready;
logic byteTaken;

assign byteTaken = peek_valid && peek_ready;

// Both channels hold an entry steady until it is taken (entry_dispatch_formal proves the dispatcher does).
logic aHeld;
logic bHeld;
logic [11:0] aLast;
logic [11:0] bLast;

always_comb begin
	assume (ratio != 0);
`ifdef LINE_CHECK
	// The bounded line check runs fast ratios so that several whole messages fit in its depth.
	assume (ratio <= 4'd2);
`endif
	if (aHeld) begin
		assume (a_valid && {a_len, a_data} == aLast);
	end
	if (bHeld) begin
		assume (b_valid && {b_len, b_data} == bLast);
	end
end

initial assume (!rst_n);
initial started = 1'b0;

always_ff @(posedge clk) begin
	started <= 1'b1;
end

always_ff @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		aHeld <= 1'b0;
		bHeld <= 1'b0;
		aLast <= '0;
		bLast <= '0;
	end else begin
		aHeld <= a_valid && !a_ready;
		bHeld <= b_valid && !b_ready;
		aLast <= {a_len, a_data};
		bLast <= {b_len, b_data};
	end
end

// ---------------------------------------------------------------------------
// Reference receiver: samples the first clock of each bit cell (uart_tx_formal proves the cells are exact).
// ---------------------------------------------------------------------------
logic rxActive;
logic [3:0] rxBit;
logic [3:0] rxCycle;
logic [7:0] rxShift;
logic rxDone;
logic [7:0] rxByte;
logic rxStart;

assign rxStart = !rxActive && !tx_serial;

always_ff @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		rxActive <= 1'b0;
		rxBit <= '0;
		rxCycle <= '0;
		rxShift <= '0;
		rxDone <= 1'b0;
		rxByte <= '0;
	end else begin
		rxDone <= 1'b0;
		if (rxStart) begin
			rxActive <= 1'b1;
			rxBit <= '0;
			rxCycle <= (ratio == 4'd1) ? 4'd0 : 4'd1;
			if (ratio == 4'd1) begin
				rxBit <= 4'd1;
			end
		end else if (rxActive) begin
			if (rxCycle == 4'd0) begin
				if (rxBit >= 4'd1 && rxBit <= 4'd8) begin
					rxShift <= {tx_serial, rxShift[7:1]};
				end
				if (rxBit == 4'd9) begin
					rxDone <= 1'b1;
					rxByte <= rxShift;
				end
			end
			if (rxCycle == ratio - 1'b1 || ratio == 4'd1) begin
				rxCycle <= '0;
				if (rxBit == 4'd9) begin
					rxActive <= 1'b0;
				end else begin
					rxBit <= rxBit + 1'b1;
				end
			end else begin
				rxCycle <= rxCycle + 1'b1;
			end
		end
	end
end

// ---------------------------------------------------------------------------
// Reference arbiter and message queue, written from the ISA's return format.
// ---------------------------------------------------------------------------
logic [1:0] turn;
logic [3:0] owed;
logic [1:0] pick;
logic busy;
logic [1:0] startsLeft;
logic accept;
logic [7:0] firstOut;
logic [7:0] secondOut;
logic [7:0] queue [0:3];
logic [2:0] queued;
logic [1:0] aWaits;
logic [1:0] bWaits;
logic [1:0] fWaits;

always_comb begin
	pick = 2'd3;
	case (turn)
		2'd0: pick = a_valid ? 2'd0 : b_valid ? 2'd1 : (owed != 0) ? 2'd2 : 2'd3;
		2'd1: pick = b_valid ? 2'd1 : (owed != 0) ? 2'd2 : a_valid ? 2'd0 : 2'd3;
		default: pick = (owed != 0) ? 2'd2 : a_valid ? 2'd0 : b_valid ? 2'd1 : 2'd3;
	endcase
	accept = !busy && pick != 2'd3;
	case (pick)
		2'd0: begin
			firstOut = {4'b1000, a_len};
			secondOut = a_data;
		end
		2'd1: begin
			firstOut = {4'b1010, b_len};
			secondOut = b_data;
		end
		default: begin
			firstOut = 8'hC0;
			secondOut = {4'd0, owed};
		end
	endcase
end

always_ff @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		turn <= '0;
		owed <= '0;
		busy <= 1'b0;
		startsLeft <= '0;
		queued <= '0;
		for (int i = 0; i < 4; i++) begin
			queue[i] <= '0;
		end
		aWaits <= '0;
		bWaits <= '0;
		fWaits <= '0;
	end else begin
		// A message keeps the sender busy until its second byte has been handed to the UART.
		if (busy && byteTaken) begin
			startsLeft <= startsLeft - 1'b1;
			if (startsLeft == 2'd1) begin
				busy <= 1'b0;
			end
		end
		owed <= (accept && pick == 2'd2) ? events : (owed | events);
		if (accept) begin
			busy <= 1'b1;
			startsLeft <= 2'd2;
			turn <= (pick == 2'd2) ? 2'd0 : pick + 1'b1;
		end
		// Expected bytes: pushed when accepted, popped when the receiver finishes a byte.
		begin : update_queue
			logic [7:0] q [0:3];
			logic [2:0] n;
			for (int i = 0; i < 4; i++) q[i] = queue[i];
			n = queued;
			if (byteTaken && n != 0) begin
				for (int i = 0; i < 3; i++) q[i] = q[i+1];
				n = n - 1'b1;
			end
			if (accept && n <= 3'd2) begin
				q[n[1:0]] = firstOut;
				q[n[1:0] + 1'b1] = secondOut;
				n = n + 3'd2;
			end
			for (int i = 0; i < 4; i++) queue[i] <= q[i];
			queued <= n;
		end
		// How many other messages each waiting source has seen go first.
		aWaits <= (!a_valid || a_ready) ? 2'd0 : (accept ? aWaits + 1'b1 : aWaits);
		bWaits <= (!b_valid || b_ready) ? 2'd0 : (accept ? bWaits + 1'b1 : bWaits);
		fWaits <= (owed == 0 || (accept && pick == 2'd2)) ? 2'd0 : (accept ? fWaits + 1'b1 : fWaits);
	end
end

// Bytes handed to the UART and not yet seen whole on the line (LINE_CHECK only).
logic [7:0] lineQueue [0:3];
logic [2:0] lineQueued;

always_ff @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		lineQueued <= '0;
		for (int i = 0; i < 4; i++) begin
			lineQueue[i] <= '0;
		end
	end else begin : update_line
		logic [7:0] q [0:3];
		logic [2:0] n;
		for (int i = 0; i < 4; i++) q[i] = lineQueue[i];
		n = lineQueued;
		if (rxDone && n != 0) begin
			for (int i = 0; i < 3; i++) q[i] = q[i+1];
			n = n - 1'b1;
		end
		if (byteTaken && n != 3'd4) begin
			q[n[1:0]] = peek_byte;
			n = n + 1'b1;
		end
		for (int i = 0; i < 4; i++) lineQueue[i] <= q[i];
		lineQueued <= n;
	end
end

always_comb begin
	if (started && rst_n) begin
		// Handshakes match the reference arbiter.
		assert (a_ready == (accept && pick == 2'd0));
		assert (b_ready == (accept && pick == 2'd1));
		assert (!(a_ready && b_ready));
		// Every byte handed to the UART is the next expected byte; nothing is sent that was not accepted, and nothing is lost.
		assert (queued <= 3'd2);
		assert (busy == (queued != 0));
		assert (startsLeft == queued[1:0]);
		if (byteTaken) begin
			assert (queued != 0);
			assert (peek_byte == queue[0]);
		end
`ifdef LINE_CHECK
		// Bounded end-to-end check: the reference receiver on tx_serial sees the same bytes.
		assert (lineQueued <= 3'd3);
		if (rxDone) begin
			assert (lineQueued != 0);
			assert (rxByte == lineQueue[0]);
		end
		if (rxActive && rxBit == 4'd9) begin
			assert (tx_serial);
		end
`endif
		// Fairness: a waiting source sees at most two other messages go first.
		assert (aWaits <= 2'd2);
		assert (bWaits <= 2'd2);
		assert (fWaits <= 2'd2);
	end
end

always_comb begin
	if (started && rst_n) begin
		cover (byteTaken && peek_byte == 8'hC0 && ratio == 4'd2);
		cover (byteTaken && peek_byte == 8'hA5 && queued == 3'd1);
		cover (rxDone && rxByte == 8'h83);
		cover (aWaits == 2'd2);
		// The flags served straight after channel B while B is idle (the coverage report's last unreached point).
		cover (accept && pick == 2'd2 && turn == 2'd2 && !b_valid);
	end
end

endmodule
