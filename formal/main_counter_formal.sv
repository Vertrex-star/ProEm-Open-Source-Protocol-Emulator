// =============================================================================
// Project: ProEm - Open Source Protocol Emulator
// File: formal/main_counter_formal.sv
// Module: main_counter_formal
// Type: Formal harness (SymbiYosys)
// Hierarchy: main_counter_formal
// Submodules: main_counter
// Author: Paul Vincent Bezzina
// Language: SystemVerilog
// Description: Proves MAIN moves every bit exactly once and in order, following one symbolic bit end to end: read bits come
// back in host entries of 8 with a short last one, written bits leave the host entries in order, BITS per frame, and a branch
// abort keeps the finished byte.
// =============================================================================

module main_counter_formal (
	input logic clk,
	input logic rst_n,
	input logic tick,
	input logic configuration,
	input logic [15:0] clock_cycles,
	input logic write_config,
	input logic input_bit,
	input logic msb,
	input logic enable,
	input logic fifo_free,
	input logic abort,
	input logic keep_pending,
	input logic host_empty,
	input logic [7:0] host_data,
	input logic [3:0] host_len,
	input logic pick,
	input logic [2:0] pick_offset
);

logic complete;
logic byte_done;
logic listening;
logic pending;
logic writing;
logic have_data;
logic waiting_end;
logic host_pop;
logic [7:0] data_out;
logic [3:0] data_len;
logic data_wire;
logic data_valid;

main_counter dut (
	.clk(clk),
	.rst_n(rst_n),
	.tick(tick),
	.configuration(configuration),
	.clock_cycles(clock_cycles),
	.wait_end(1'b0),
	.write_config(write_config),
	.follow_config(1'b0),
	.follow_write(1'b0),
	.ack_config(1'b0),
	.input_bit(input_bit),
	.msb(msb),
	.enable(enable),
	.fifo_free(fifo_free),
	.end_success(1'b0),
	.abort(abort),
	.keep_pending(keep_pending),
	.host_empty(host_empty),
	.host_data(host_data),
	.host_len(host_len),
	.complete(complete),
	.byte_done(byte_done),
	.listening(listening),
	.pending(pending),
	.writing(writing),
	.have_data(have_data),
	.waiting_end(waiting_end),
	.host_pop(host_pop),
	.data_out(data_out),
	.data_len(data_len),
	.data_wire(data_wire),
	.data_valid(data_valid)
);

logic started;
logic configured;
logic order;
logic dirWrite;
logic [15:0] bits;

// ISA ranges and the chain's own guarantees: BITS 1 to 65535, host entries 1 to 8 bits, bit order and direction steady while
// MAIN is configured.
always_comb begin
	if (configuration) begin
		assume (clock_cycles >= 16'd1);
	end
	if (!host_empty) begin
		assume (host_len >= 4'd1 && host_len <= 4'd8);
	end
	if (configured && !configuration) begin
		assume (msb == order);
	end
	// MAIN is rewritten between frames, not while it runs; a read frame only loses its enable at a frame boundary (the chain
	// aborts a frame it stops early); an abort is not raised on the clock a wire entry leaves.
	if (configuration) begin
		assume (!enable);
	end
	if (configured && !dirWrite && !enable) begin
		assume (inPos == 0);
	end
	if (configured && abort) begin
		assume (!data_valid);
	end
	// No read overflow: a new byte never completes while the last one still waits for a full buffer (the frame chain reports
	// that case as overflow; it is covered separately below).
	if (byte_done && !writing && pending && !fifo_free) begin
		assume (1'b0);
	end
end

// The host FIFO keeps its head until it is popped.
logic headHeld;
logic [11:0] headLast;

always_comb begin
	if (headHeld) begin
		assume (!host_empty && {host_len, host_data} == headLast);
	end
end

initial assume (!rst_n);
initial started = 1'b0;

always_ff @(posedge clk) begin
	started <= 1'b1;
end

always_ff @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		headHeld <= 1'b0;
		headLast <= '0;
	end else begin
		headHeld <= !host_empty && !host_pop && !configuration;
		headLast <= {host_len, host_data};
	end
end

always_ff @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		configured <= 1'b0;
		order <= 1'b0;
		dirWrite <= 1'b0;
		bits <= '0;
	end else if (configuration) begin
		configured <= 1'b1;
		order <= msb;
		dirWrite <= write_config;
		bits <= clock_cycles;
	end
end

// ---------------------------------------------------------------------------
// Read: positions in the frame of bits taken (inPos) and bits handed to the host (outPos).
// ---------------------------------------------------------------------------
logic readTick;
logic hostEntry;
logic [15:0] inPos;
logic [15:0] outPos;
logic [5:0] inAbs;
logic [5:0] outAbs;
logic [3:0] lastLen;
logic keptByte;
logic rTracking;
logic [5:0] rPos;
logic rValue;
logic [3:0] rOff;
logic rBit;
logic frameReset;

assign readTick = configured && !dirWrite && enable && tick && !configuration && !abort;
assign hostEntry = data_valid && !data_wire;
assign frameReset = configuration || abort || !enable;
// A byte survives the abort only on a branch abort, and only if one is waiting (ACK is off, so pending is that byte).
assign keptByte = keep_pending && pending && !dirWrite;

always_comb begin
	rOff = rPos - outAbs;
	rBit = order ? data_out[data_len - 1'b1 - rOff] : data_out[rOff];
end

always_ff @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		inPos <= '0;
		outPos <= '0;
		inAbs <= '0;
		outAbs <= '0;
		lastLen <= '0;
		rTracking <= 1'b0;
		rPos <= '0;
		rValue <= 1'b0;
	end else begin
		if (configuration || (abort && !keptByte)) begin
			// An abort drops the partial frame and anything still waiting.
			inPos <= '0;
			outPos <= '0;
			outAbs <= inAbs;
			rTracking <= 1'b0;
		end else if (abort) begin
			// A branch abort keeps the finished byte still waiting (lastLen bits) and drops only the partial byte after it.
			inPos <= '0;
			outPos <= 16'd0 - lastLen;
			inAbs <= outAbs + lastLen;
			if (rTracking && (rPos - outAbs) >= {2'd0, lastLen}) begin
				rTracking <= 1'b0;
			end
		end else begin
			// inPos and outPos count within the frame; inAbs and outAbs along the whole bit stream.
			if (hostEntry) begin
				outPos <= (outPos + data_len == bits) ? 16'd0 : outPos + data_len;
				outAbs <= outAbs + data_len;
				if (rTracking && (rPos - outAbs) < data_len) begin
					rTracking <= 1'b0;
				end
			end
			if (readTick && byte_done) begin
				lastLen <= {1'b0, inPos[2:0]} + 4'd1;
			end
			if (readTick) begin
				inPos <= (inPos + 1'b1 == bits) ? 16'd0 : inPos + 1'b1;
				inAbs <= inAbs + 1'b1;
				if (!rTracking && pick) begin
					rTracking <= 1'b1;
					rPos <= inAbs;
					rValue <= input_bit;
				end
			end
		end
	end
end

// ---------------------------------------------------------------------------
// Write: positions in the host bit stream of bits popped (hPos) and bits sent on the wire (wPos), and bits sent this frame.
// ---------------------------------------------------------------------------
logic wireEntry;
logic [5:0] hPos;
logic [5:0] wPos;
logic [15:0] frameBits;
logic wTracking;
logic [5:0] wPos0;
logic wValue;
logic [3:0] wOff;
logic wBit;
logic popBit;
logic [5:0] popPos;
logic [3:0] popOff;
logic popNowBit;
logic popSentNow;

assign wireEntry = data_valid && data_wire;
assign popBit = order ? host_data[host_len - 1'b1 - pick_offset] : host_data[pick_offset];

always_comb begin
	wOff = wPos0 - wPos;
	wBit = order ? data_out[data_len - 1'b1 - wOff] : data_out[wOff];
	// A bit can be popped and sent on the same clock; then it is checked at once instead of tracked.
	popPos = hPos + pick_offset;
	popOff = popPos - wPos;
	popNowBit = order ? data_out[data_len - 1'b1 - popOff] : data_out[popOff];
	popSentNow = wireEntry && ((popPos - wPos) < data_len);
end

always_ff @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		hPos <= '0;
		wPos <= '0;
		frameBits <= '0;
		wTracking <= 1'b0;
		wPos0 <= '0;
		wValue <= 1'b0;
	end else if (configuration) begin
		frameBits <= '0;
		wTracking <= 1'b0;
		hPos <= '0;
		wPos <= '0;
	end else begin
		if (host_pop) begin
			hPos <= hPos + host_len;
			if (!wTracking && pick && {1'b0, pick_offset} < host_len && !popSentNow) begin
				wTracking <= 1'b1;
				wPos0 <= hPos + pick_offset;
				wValue <= popBit;
			end
		end
		if (wireEntry) begin
			wPos <= wPos + data_len;
			frameBits <= (complete) ? 16'd0 : frameBits + data_len;
			if (wTracking && (wPos0 - wPos) < data_len) begin
				wTracking <= 1'b0;
			end
		end else if (abort || !enable) begin
			frameBits <= '0;
		end
	end
end

// ---------------------------------------------------------------------------
// Helper invariants. MAIN's registers, read by the .sby script (connect after flatten), are tied to the reference so that
// k-induction closes in a few steps. They are proved like every other assertion, and left out of mutation runs.
// ---------------------------------------------------------------------------
logic [15:0] peek_remaining;
logic [15:0] peek_clock;
logic [2:0] peek_index;
logic peek_pending_valid;
logic [3:0] peek_pending_len;
logic [7:0] peek_pending_data;
logic [7:0] peek_shift;
logic peek_carry_valid;
logic [3:0] peek_carry_len;
logic [7:0] peek_carry_data;
logic peek_write;
logic peek_ack_pending;
logic peek_nack_pending;
logic peek_ack_wait;
logic [5:0] lagIn;
logic [5:0] dRead;
logic [5:0] dShift;
logic pendBit;
logic shiftBit;
logic [5:0] dCarry;
logic carryBit;

always_comb begin
	lagIn = inAbs - outAbs;
	dRead = rPos - outAbs;
	dShift = dRead - (peek_pending_valid ? {2'd0, peek_pending_len} : 6'd0);
	pendBit = order ? peek_pending_data[peek_pending_len - 1'b1 - dRead[3:0]] : peek_pending_data[dRead[3:0]];
	shiftBit = order ? peek_shift[peek_index - 1'b1 - dShift[2:0]] : peek_shift[4'd8 - peek_index + dShift[2:0]];
	dCarry = wPos0 - wPos;
	carryBit = order ? peek_carry_data[peek_carry_len - 1'b1 - dCarry[3:0]] : peek_carry_data[dCarry[3:0]];
end

`ifndef MUTATION
always_comb begin
	if (started && rst_n && configured && !configuration) begin
		assert (peek_clock == bits);
		assert (peek_write == dirWrite);
		assert (!peek_ack_pending && !peek_nack_pending && !peek_ack_wait);
		assert (bits != 0);
		if (!dirWrite) begin
			assert (inPos < bits);
			assert (peek_remaining == bits - inPos);
			assert (peek_index == inPos[2:0]);
			assert (lagIn == (peek_pending_valid ? {2'd0, peek_pending_len} : 6'd0) + {3'd0, peek_index});
			if (peek_pending_valid) begin
				assert (peek_pending_len >= 4'd1 && peek_pending_len <= 4'd8);
				assert ((peek_pending_data >> peek_pending_len) == 8'd0);
				assert ((outPos + peek_pending_len + peek_index == inPos && peek_pending_len == 4'd8)
					|| (outPos + peek_pending_len == bits && inPos == {13'd0, peek_index})
					|| (outPos + peek_pending_len == 16'd0 && inPos == {13'd0, peek_index}));
				assert (lastLen == peek_pending_len);
			end else begin
				assert (outPos + peek_index == inPos);
			end
			if (rTracking) begin
				if (peek_pending_valid && dRead < {2'd0, peek_pending_len}) begin
					assert (pendBit == rValue);
				end else begin
					assert (shiftBit == rValue);
				end
			end
		end else begin
			assert (frameBits < bits);
			assert ((hPos - wPos) <= 6'd7);
			assert (peek_remaining == bits - frameBits);
			assert ((hPos - wPos) == (peek_carry_valid ? {2'd0, peek_carry_len} : 6'd0));
			if (peek_carry_valid) begin
				assert (peek_carry_len >= 4'd1 && peek_carry_len <= 4'd7);
			end
			if (wTracking) begin
				assert (peek_carry_valid && dCarry < {2'd0, peek_carry_len});
				assert (carryBit == wValue);
			end
		end
	end
end
`endif

always_comb begin
	if (started && rst_n && configured && !configuration) begin
		assert (writing == dirWrite);
		if (!dirWrite) begin
			// Reading: host entries only, in bytes of 8 except the frame's last, every bit in its place, none taken twice.
			assert (!wireEntry);
			if (hostEntry) begin
				assert (data_len >= 4'd1 && data_len <= 4'd8);
				assert (data_len == 4'd8 || outPos + data_len == bits || outPos + data_len == 16'd0);
				// Nothing above the entry's length: a short last byte must not carry bits of the byte before it.
				assert ((data_out >> data_len) == 8'd0);
				assert (outPos + data_len <= bits);
				if (rTracking && (rPos - outAbs) < data_len) begin
					assert (rBit == rValue);
				end
			end
			// Never more than a byte waiting plus a byte being shifted in, so no bit is skipped or emitted twice.
			assert ((inAbs - outAbs) <= 6'd16);
			if (rTracking) begin
				assert ((rPos - outAbs) < (inAbs - outAbs));
			end
			// Complete exactly on the tick that takes the BITS-th bit. (On an abort clock MAIN may still raise complete; the frame
			// chain gives the abort priority, so that clock is not checked here.)
			if (!abort) begin
				assert (complete == (readTick && inPos + 1'b1 == bits));
			end
		end else begin
			// Writing: wire entries only, 1 to 8 bits, never more than BITS in a frame, the frame ends on exactly BITS.
			assert (!hostEntry);
			if (wireEntry) begin
				assert (data_len >= 4'd1 && data_len <= 4'd8);
				assert (frameBits + data_len <= bits);
				assert ((data_out >> data_len) == 8'd0);
				assert (complete == (frameBits + data_len == bits));
				if (wTracking && (wPos0 - wPos) < data_len) begin
					assert (wBit == wValue);
				end
			end else begin
				assert (!complete);
			end
			if (host_pop && pick && {1'b0, pick_offset} < host_len && popSentNow) begin
				assert (popNowBit == popBit);
			end
			// Nothing is sent that was not popped, and a popped bit is never skipped.
			if (wTracking) begin
				assert ((wPos0 - wPos) < 6'd16);
			end
			assert ((hPos - wPos) <= 6'd8);
		end
	end
end

always_comb begin
	if (started && rst_n && configured) begin
		cover (hostEntry && rTracking && data_len == 4'd3 && bits == 16'd11 && order);
		cover (wireEntry && wTracking && complete && data_len == 4'd2 && !order);
		cover (byte_done && !writing && pending);
		cover (dirWrite && host_pop && have_data && data_len == 4'd1);
		cover (hostEntry && rTracking && outPos + data_len == 16'd0 && data_len == 4'd3);
	end
end

endmodule
