// =============================================================================
// Project: ProEm - Open Source Protocol Emulator
// File: rtl/core/frame_chain/frame_chain.sv
// Module: frame_chain
// Type: RTL, core (frame chain)
// Hierarchy: protocol_emulator > emulator_channel > frame_chain
// Submodules: first_counter, header_counter (x6), start_router, main_counter, end_counter, watchdog, frame_buffer
// Author: Paul Vincent Bezzina
// Language: SystemVerilog
// Description:
// =============================================================================

module frame_chain #(
	parameter int blocks = 7,
	parameter int buffer_depth = 16
) (
	input logic clk,
	input logic rst_n,
	input logic tick,
	input logic end_tick,
	input logic[7:0] pins,
	input logic[7:0] raw_pins,
	input logic code_error,
	input logic run,
	input logic[1:0] run_mode,
	input logic halt,
	input logic host_empty,
	input logic[7:0] host_data,
	input logic[3:0] host_len,
	input logic cfg_we,
	input logic[3:0] cfg_sel,
	input logic[7:0] cfg_compare,
	input logic[7:0] cfg_cycles,
	input logic[2:0] cfg_pin,
	input logic cfg_capture,
	input logic cfg_write,
	input logic[1:0] cfg_group,
	input logic cfg_sr,
	input logic cfg_follow,
	input logic[15:0] cfg_main_cycles,
	input logic cfg_wait_end,
	input logic cfg_ack,
	input logic[15:0] cfg_end_pattern,
	input logic[2:0] cfg_pin_b,
	input logic cfg_pair,
	input logic cfg_invert,
	input logic cfg_error,
	input logic tx_done,
	input logic out_rd_en,

	output logic host_pop,
	output logic[7:0] out_data,
	output logic[3:0] out_len,
	output logic out_wire,
	output logic out_empty,
	output logic out_full,
	output logic complete,
	output logic abort,
	output logic timeout,
	output logic line_error,
	output logic byte_done,
	output logic line_free,
	output logic listen,
	output logic armed,
	output logic in_frame
);

logic[blocks-1:0] block_success;
logic[blocks-1:0] block_fail;
logic[blocks-1:0] block_configured;
logic[blocks-1:0] block_active;
logic[blocks-1:0] block_ready;
logic[blocks-1:0] block_enable;
logic[blocks-1:0] block_push;
logic[blocks-1:0] block_writing;
logic[blocks-1:0] block_sr;
logic[blocks-1:0] sr_sent;
logic[blocks-1:0] sr_need;
logic[7:0] block_value [0:blocks-1];
logic[3:0] block_len [0:blocks-1];
logic[1:0] block_group [0:blocks-1];
logic[1:0] mode;
logic[2:0] data_pin;
logic[2:0] end_pin;
logic[2:0] end_pin_b;
logic[7:0] main_data;
logic[3:0] main_len;
logic[12:0] fifo_din;
logic[12:0] fifo_raw;
logic[7:0] reversed;
logic[7:0] flipped;
logic[4:0] outstanding;
logic[4:0] status_flags;

logic input_bit;
logic end_a;
logic end_b;
logic end_input;
logic end_pair;
logic end_invert;
logic end_error;
logic msb;
logic read_tick;
logic main_wire;
logic wire_accept;
logic main_listening;
logic[blocks-1:0] block_listening;
logic start_tick;
logic main_ready;
logic main_enable;
logic main_sr;
logic main_sr_sent;
logic main_sr_need;
logic sr_accept;
logic main_valid;
logic main_pending;
logic main_writing;
logic main_have_data;
logic end_success;
logic fifo_wr;
logic write_end;
logic frame_reset;
logic commit_wait;
logic commit;
logic end_configured;
logic rearm_wait;
logic rearm_done;
logic internal_armed;
logic internal_line_error;
logic mode_read;
logic mode_write;
logic armed_now;
logic status_pending;
logic status_accept;
logic overflow_seen;
logic frame_event;
logic space;
logic out_almost_full;

assign input_bit = pins[data_pin];
assign end_a = raw_pins[end_pin];
assign end_b = raw_pins[end_pin_b] ^ end_invert;
assign end_input = end_pair ? (!end_a && !end_b) : end_a;
assign mode_read = (mode == 2'd1);
assign mode_write = (mode == 2'd2);
assign armed_now = internal_armed || run;
assign line_free = (outstanding == 5'd0) && !(|(block_push & block_writing));
assign read_tick = tick && line_free;
assign rearm_done = rearm_wait && end_success;
assign space = !out_almost_full;
assign start_tick = armed_now && (block_writing[0] ? ((run || (main_have_data && mode == 2'd0)) && space) : (read_tick && !rearm_wait));

always_comb begin
	block_active[0] = 1'b1;
	for (int k = 1; k < blocks; k++) begin
		block_active[k] = block_configured[k] && ((block_group[k] == 2'd0) || (block_group[k] == 2'd1 && mode_read) || (block_group[k] == 2'd2 && mode_write));
	end
end

always_comb begin
	block_enable[0] = 1'b1;
	sr_need[0] = 1'b0;
	for (int k = 1; k < blocks; k++) begin
		block_enable[k] = block_ready[k] && (!block_sr[k] || sr_sent[k]) && (!block_writing[k] || space);
		sr_need[k] = block_ready[k] && block_sr[k] && !sr_sent[k];
	end
end

assign main_enable = main_ready && (!main_sr || main_sr_sent);
assign main_sr_need = main_ready && main_sr && !main_sr_sent;
assign sr_accept = ((|sr_need) || main_sr_need) && !(|block_push) && !main_valid && !out_full && !abort && !halt;
assign frame_event = complete || abort || write_end;
assign status_accept = status_pending && !frame_event && !(|block_push) && !main_valid && !sr_accept && !out_full && !main_pending && !halt;

always_comb begin
	block_listening[0] = internal_armed && !block_writing[0] && !block_success[0];
	for (int k = 1; k < blocks; k++) begin
		block_listening[k] = block_enable[k] && !block_writing[k] && !block_success[k] && !block_fail[k];
	end
end

assign listen = line_free && ((|block_listening) || main_listening);
assign wire_accept = fifo_wr && fifo_din[12] && !out_full && !abort && !halt;
assign write_end = timeout && main_writing && main_enable;
assign abort = (|block_fail) || (timeout && !write_end) || internal_line_error;
assign frame_reset = complete || abort || write_end || halt;
assign commit = (commit_wait && !main_pending) || main_enable;

always_ff@(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		data_pin <= '0;
		end_pin <= '0;
		end_pin_b <= '0;
		end_pair <= 1'b0;
		end_invert <= 1'b0;
		end_error <= 1'b0;
		msb <= 1'b0;
		mode <= '0;
		commit_wait <= 1'b0;
		outstanding <= '0;
		end_configured <= 1'b0;
		rearm_wait <= 1'b0;
		internal_armed <= 1'b0;
		internal_line_error <= 1'b0;
		status_pending <= 1'b0;
		status_flags <= '0;
		overflow_seen <= 1'b0;
		main_sr <= 1'b0;
		main_sr_sent <= 1'b0;
		block_sr <= '0;
		sr_sent <= '0;
		for (int k = 0; k < blocks; k++) begin
			block_group[k] <= '0;
		end
	end else begin
		outstanding <= outstanding + wire_accept - tx_done;
		internal_line_error <= ((end_error && end_pair && end_tick && end_a && end_b && main_enable && !main_writing) || (code_error && block_success[0])) && !internal_line_error;
		if (frame_event) begin
			status_pending <= 1'b1;
			status_flags <= status_flags | {overflow_seen || (fifo_wr && out_full), internal_line_error, timeout, abort, complete || write_end};
			overflow_seen <= 1'b0;
		end else if (status_accept) begin
			status_pending <= 1'b0;
			status_flags <= '0;
		end else if (fifo_wr && out_full) begin
			overflow_seen <= 1'b1;
		end
		if (halt) begin
			status_pending <= 1'b0;
			status_flags <= '0;
		end
		if (halt) begin
			internal_armed <= 1'b0;
		end else if (run) begin
			internal_armed <= 1'b1;
			mode <= run_mode;
		end
		for (int k = 1; k < blocks; k++) begin
			if (cfg_we && cfg_sel == k) begin
				block_group[k] <= cfg_group;
				block_sr[k] <= cfg_sr;
			end
		end
		if (cfg_we && cfg_sel == 4'd14) begin
			data_pin <= cfg_pin;
			main_sr <= cfg_sr;
		end
		if (cfg_we && cfg_sel == 4'd15) begin
			end_pin <= cfg_pin;
			end_pin_b <= cfg_pin_b;
			end_pair <= cfg_pair;
			end_invert <= cfg_invert;
			end_error <= cfg_error;
			end_configured <= 1'b1;
		end
		if (frame_reset) begin
			sr_sent <= '0;
			main_sr_sent <= 1'b0;
		end else if (sr_accept) begin
			sr_sent <= sr_sent | sr_need;
			main_sr_sent <= main_sr_sent || main_sr_need;
		end
		if (halt) begin
			rearm_wait <= 1'b0;
		end else if (abort && end_configured && !block_writing[0]) begin
			rearm_wait <= 1'b1;
		end else if (rearm_done) begin
			rearm_wait <= 1'b0;
		end
		if (cfg_we && cfg_sel == 4'd12) begin
			msb <= cfg_compare[0];
		end
		if (halt) begin
			commit_wait <= 1'b0;
		end else if (complete || write_end) begin
			commit_wait <= 1'b1;
		end else if (commit || abort) begin
			commit_wait <= 1'b0;
		end
	end
end

first_counter start (
	.clk(clk),
	.rst_n(rst_n),
	.tick(start_tick),
	.configuration(cfg_we && cfg_sel == 4'd0),
	.compare_bit(cfg_compare),
	.clock_cycles(cfg_cycles),
	.pin_select(cfg_pin),
	.capture(cfg_capture),
	.write_config(cfg_write),
	.pins(pins),
	.msb(msb),
	.enable(internal_armed && !rearm_wait),
	.complete(frame_reset),
	.abort(1'b0),
	.success(block_success[0]),
	.writing(block_writing[0]),
	.compare_out(block_value[0]),
	.push(block_push[0]),
	.push_len(block_len[0])
);

assign block_fail[0] = 1'b0;
assign block_configured[0] = 1'b1;

genvar i;
generate
	for (i = 1; i < blocks; i++) begin : g_header
		header_counter header (
			.clk(clk),
			.rst_n(rst_n),
			.tick(read_tick),
			.configuration(cfg_we && cfg_sel == i),
			.compare_bit(cfg_compare),
			.clock_cycles(cfg_cycles),
			.capture(cfg_capture),
			.write_config(cfg_write),
			.input_bit(input_bit),
			.msb(msb),
			.enable(block_enable[i]),
			.complete(frame_reset),
			.abort(1'b0),
			.success(block_success[i]),
			.fail(block_fail[i]),
			.configured(block_configured[i]),
			.writing(block_writing[i]),
			.compare_out(block_value[i]),
			.push(block_push[i]),
			.push_len(block_len[i])
		);
	end
endgenerate

start_router #(
	.blocks(blocks)
) router (
	.block_success(block_success),
	.block_configured(block_configured),
	.block_active(block_active),
	.block_enable(block_ready),
	.main_enable(main_ready)
);

main_counter main_block (
	.clk(clk),
	.rst_n(rst_n),
	.tick(read_tick),
	.configuration(cfg_we && cfg_sel == 4'd14),
	.clock_cycles(cfg_main_cycles),
	.wait_end(cfg_wait_end),
	.write_config(cfg_write),
	.follow_config(cfg_follow),
	.follow_write(mode_write),
	.ack_config(cfg_ack),
	.input_bit(input_bit),
	.msb(msb),
	.enable(main_enable),
	.fifo_free(!(|block_push) && (!main_writing || space)),
	.end_success(end_success),
	.abort(abort || halt),
	.host_empty(host_empty),
	.host_data(host_data),
	.host_len(host_len),
	.complete(complete),
	.byte_done(byte_done),
	.listening(main_listening),
	.pending(main_pending),
	.writing(main_writing),
	.have_data(main_have_data),
	.host_pop(host_pop),
	.data_out(main_data),
	.data_len(main_len),
	.data_wire(main_wire),
	.data_valid(main_valid)
);

end_counter #(
	.width(16)
) end_block (
	.clk(clk),
	.rst_n(rst_n),
	.tick(end_tick),
	.configuration(cfg_we && cfg_sel == 4'd15),
	.compare_bit(cfg_end_pattern),
	.clock_cycles(cfg_cycles),
	.input_bit(end_input),
	.msb(msb),
	.enable((main_enable && !main_writing) || rearm_wait),
	.complete(frame_reset || rearm_done),
	.abort(1'b0),
	.success(end_success)
);

watchdog dog (
	.clk(clk),
	.rst_n(rst_n),
	.configuration(cfg_we && cfg_sel == 4'd13),
	.clock_limit(cfg_main_cycles),
	.busy(block_success[0]),
	.tick(tick || host_pop || tx_done),
	.frame_reset(frame_reset),
	.timeout(timeout)
);

always_comb begin
	fifo_wr = 1'b0;
	fifo_raw = '0;
	if (status_accept) begin
		fifo_wr = 1'b1;
		fifo_raw = {1'b0, 4'hF, 3'd0, status_flags};
	end
	if (sr_accept) begin
		fifo_wr = 1'b1;
		fifo_raw = {1'b1, 4'd0, 8'd0};
	end
	if (main_valid) begin
		fifo_wr = 1'b1;
		fifo_raw = {main_wire, main_len, main_data};
	end
	for (int j = blocks - 1; j >= 0; j--) begin
		if (block_push[j]) begin
			fifo_wr = 1'b1;
			fifo_raw = {block_writing[j], block_len[j], block_value[j]};
		end
	end
end

always_comb begin
	for (int r = 0; r < 8; r++) begin
		flipped[r] = fifo_raw[7 - r];
	end
	reversed = flipped >> (4'd8 - fifo_raw[11:8]);
	fifo_din = (msb && fifo_raw[12]) ? {fifo_raw[12:8], reversed} : fifo_raw;
end

frame_buffer #(
	.depth(buffer_depth),
	.width(13)
) out_buffer (
	.clk(clk),
	.rst_n(rst_n),
	.wr_en(fifo_wr),
	.din(fifo_din),
	.commit(commit),
	.commit_all(wire_accept || status_accept),
	.rollback(abort || halt),
	.rd_en(out_rd_en),
	.full(out_full),
	.almost_full(out_almost_full),
	.empty(out_empty),
	.dout({out_wire, out_len, out_data})
);

assign line_error = internal_line_error;
assign armed = internal_armed;
assign in_frame = block_success[0];

endmodule
