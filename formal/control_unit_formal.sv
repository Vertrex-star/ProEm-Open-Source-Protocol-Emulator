// =============================================================================
// Project: ProEm - Open Source Protocol Emulator
// File: formal/control_unit_formal.sv
// Module: control_unit_formal
// Type: Formal harness (SymbiYosys)
// Hierarchy: control_unit_formal
// Submodules: control_unit
// Author: Paul Vincent Bezzina
// Language: SystemVerilog
// Description: Proves the instruction decoder against a second decoder written from the ISA's byte layouts: every instruction
// takes the right number of operand bytes and makes exactly one write or pulse with the right fields on the right chain.
// cmd_error is raised exactly when the ISA says.
// =============================================================================

module control_unit_formal (
	input logic clk,
	input logic rst_n,
	input logic [7:0] rx_data,
	input logic rx_valid
);

logic cfg_we_a;
logic cfg_we_b;
logic [3:0] cfg_sel;
logic [7:0] cfg_compare;
logic [7:0] cfg_cycles;
logic [2:0] cfg_pin;
logic cfg_capture;
logic cfg_write;
logic [1:0] cfg_group;
logic cfg_sr;
logic cfg_any;
logic cfg_seek;
logic cfg_follow;
logic [15:0] cfg_main_cycles;
logic cfg_wait_end;
logic cfg_ack;
logic [15:0] cfg_end_pattern;
logic [2:0] cfg_pin_b;
logic cfg_pair;
logic cfg_invert;
logic cfg_error;
logic run_a;
logic run_b;
logic [1:0] run_mode;
logic halt_a;
logic halt_b;
logic clear_a;
logic clear_b;
logic host_we_a;
logic host_we_b;
logic [11:0] host_wdata;
logic [15:0] line_a;
logic [15:0] line_b;
logic [31:0] clock_a;
logic [31:0] clock_b;
logic [7:0] out_a;
logic [7:0] out_b;
logic [15:0] link_div;
logic cmd_error;

control_unit dut (
	.clk(clk),
	.rst_n(rst_n),
	.rx_data(rx_data),
	.rx_valid(rx_valid),
	.cfg_we_a(cfg_we_a),
	.cfg_we_b(cfg_we_b),
	.cfg_sel(cfg_sel),
	.cfg_compare(cfg_compare),
	.cfg_cycles(cfg_cycles),
	.cfg_pin(cfg_pin),
	.cfg_capture(cfg_capture),
	.cfg_write(cfg_write),
	.cfg_group(cfg_group),
	.cfg_sr(cfg_sr),
	.cfg_any(cfg_any),
	.cfg_seek(cfg_seek),
	.cfg_follow(cfg_follow),
	.cfg_main_cycles(cfg_main_cycles),
	.cfg_wait_end(cfg_wait_end),
	.cfg_ack(cfg_ack),
	.cfg_end_pattern(cfg_end_pattern),
	.cfg_pin_b(cfg_pin_b),
	.cfg_pair(cfg_pair),
	.cfg_invert(cfg_invert),
	.cfg_error(cfg_error),
	.run_a(run_a),
	.run_b(run_b),
	.run_mode(run_mode),
	.halt_a(halt_a),
	.halt_b(halt_b),
	.clear_a(clear_a),
	.clear_b(clear_b),
	.host_we_a(host_we_a),
	.host_we_b(host_we_b),
	.host_wdata(host_wdata),
	.line_a(line_a),
	.line_b(line_b),
	.clock_a(clock_a),
	.clock_b(clock_b),
	.out_a(out_a),
	.out_b(out_b),
	.link_div(link_div),
	.cmd_error(cmd_error)
);

logic started;
logic lastValid;

// uart_rx_formal proves rx_valid never pulses on two consecutive clocks; this is all the decoder relies on.
always_comb begin
	if (lastValid) begin
		assume (!rx_valid);
	end
end

initial assume (!rst_n);
initial started = 1'b0;

always_ff @(posedge clk) begin
	started <= 1'b1;
end

always_ff @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		lastValid <= 1'b0;
	end else begin
		lastValid <= rx_valid;
	end
end

// ---------------------------------------------------------------------------
// Reference decoder, from the ISA's instruction table (opcode, CH, N, operand count, high byte first).
// ---------------------------------------------------------------------------
function automatic logic [2:0] operandBytes(input logic [3:0] op);
	case (op)
		4'h1, 4'h2, 4'h3, 4'hF: operandBytes = 3'd3;
		4'h4, 4'hB: operandBytes = 3'd4;
		4'h5, 4'hA, 4'hE: operandBytes = 3'd2;
		4'hC, 4'hD: operandBytes = 3'd1;
		default: operandBytes = 3'd0;
	endcase
endfunction

logic collecting;
logic [3:0] op;
logic ch;
logic [2:0] n;
logic [2:0] want;
logic [2:0] got;
logic [7:0] b [0:3];
logic done1;
logic done2;
logic [3:0] xOp;
logic xCh;
logic [2:0] xN;
logic [7:0] x1;
logic [7:0] x2;
logic [7:0] x3;
logic [7:0] x4;
logic orderA;
logic orderB;
logic [15:0] refLineA;
logic [15:0] refLineB;
logic [31:0] refClockA;
logic [31:0] refClockB;
logic [7:0] refOutA;
logic [7:0] refOutB;
logic [15:0] refLink;

always_ff @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		collecting <= 1'b0;
		op <= '0;
		ch <= 1'b0;
		n <= '0;
		want <= '0;
		got <= '0;
		for (int i = 0; i < 4; i++) begin
			b[i] <= '0;
		end
		done1 <= 1'b0;
	end else begin
		done1 <= 1'b0;
		if (rx_valid) begin
			if (!collecting) begin
				op <= rx_data[7:4];
				ch <= rx_data[3];
				n <= rx_data[2:0];
				want <= operandBytes(rx_data[7:4]);
				got <= '0;
				if (operandBytes(rx_data[7:4]) == 3'd0) begin
					done1 <= 1'b1;
				end else begin
					collecting <= 1'b1;
				end
			end else begin
				b[got[1:0]] <= rx_data;
				got <= got + 1'b1;
				if (got + 1'b1 == want) begin
					collecting <= 1'b0;
					done1 <= 1'b1;
				end
			end
		end
	end
end

// The decoded instruction, one clock later; its effects are checked on the clock after that (done2).
always_ff @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		done2 <= 1'b0;
		xOp <= '0;
		xCh <= 1'b0;
		xN <= '0;
		x1 <= '0;
		x2 <= '0;
		x3 <= '0;
		x4 <= '0;
	end else begin
		done2 <= done1;
		if (done1) begin
			xOp <= op;
			xCh <= ch;
			xN <= n;
			x1 <= b[0];
			x2 <= b[1];
			x3 <= b[2];
			x4 <= b[3];
		end
	end
end

// State the ISA says persists: bit order per chain, LINE, CLOCK, OUT per chain, LINK globally. CLEAR resets a chain's own.
// Updated as the instruction is decoded, so the new value is visible on the same clock as the instruction's pulses.
always_ff @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		orderA <= 1'b0;
		orderB <= 1'b0;
		refLineA <= '0;
		refLineB <= '0;
		refClockA <= '0;
		refClockB <= '0;
		refOutA <= '0;
		refOutB <= '0;
		refLink <= '0;
	end else if (done1) begin
		case (op)
			4'h6: if (ch) orderB <= n[0]; else orderA <= n[0];
			4'h9: begin
				if (ch) begin
					orderB <= 1'b0;
					refLineB <= '0;
					refClockB <= '0;
					refOutB <= '0;
				end else begin
					orderA <= 1'b0;
					refLineA <= '0;
					refClockA <= '0;
					refOutA <= '0;
				end
			end
			4'hA: if (ch) refLineB <= {b[0], b[1]}; else refLineA <= {b[0], b[1]};
			4'hB: if (ch) refClockB <= {b[0], b[1], b[2], b[3]}; else refClockA <= {b[0], b[1], b[2], b[3]};
			4'hD: if (ch) refOutB <= b[0]; else refOutA <= b[0];
			4'hE: refLink <= {b[0], b[1]};
			default: begin
			end
		endcase
	end
end

// What the ISA says each instruction does, evaluated for the instruction being checked.
logic expWrite;
logic [3:0] expSel;
logic expError;
logic order;
logic [3:0] cyc;
logic [7:0] startValue;

always_comb begin
	order = xCh ? orderB : orderA;
	cyc = x1[3:0];
	// START's VALUE is a plain number in its bottom CYC bits; LSB first, the block expects it at the top of the byte.
	startValue = (!order && cyc != 4'd0 && cyc < 4'd8) ? (x3 << (4'd8 - cyc)) : x3;
	expWrite = 1'b0;
	expSel = '0;
	expError = 1'b0;
	case (xOp)
		4'h1: begin
			// START: CYC 0 (condition) to 8.
			expWrite = (x1[3:0] <= 4'd8);
			expSel = 4'd0;
			expError = !expWrite;
		end
		4'h2: begin
			// HDR n: n 1 to 6, CYC 1 to 8.
			expWrite = (xN >= 3'd1 && xN <= 3'd6) && (x1[3:0] >= 4'd1 && x1[3:0] <= 4'd8);
			expSel = {1'b0, xN};
			expError = !expWrite;
		end
		4'h3: begin
			expWrite = 1'b1;
			expSel = 4'd14;
		end
		4'h4: begin
			// END: LEN 1 to 16.
			expWrite = (x1[7:3] >= 5'd1 && x1[7:3] <= 5'd16);
			expSel = 4'd15;
			expError = !expWrite;
		end
		4'h5: begin
			expWrite = 1'b1;
			expSel = 4'd13;
		end
		4'h6: begin
			expWrite = 1'b1;
			expSel = 4'd12;
		end
		4'hF: begin
			expWrite = (xN <= 3'd4);
			expError = !expWrite;
			case (xN)
				3'd0: expSel = 4'd8;
				3'd1: expSel = 4'd9;
				3'd2: expSel = 4'd10;
				3'd3: expSel = 4'd11;
				default: expSel = 4'd7;
			endcase
		end
		default: begin
		end
	endcase
end

always_comb begin
	if (started && rst_n) begin
		// Exactly one pulse per instruction, on its own chain, and none at any other time.
		assert (cfg_we_a == (done2 && expWrite && !xCh));
		assert (cfg_we_b == (done2 && expWrite && xCh));
		assert (run_a == (done2 && xOp == 4'h7 && !xCh));
		assert (run_b == (done2 && xOp == 4'h7 && xCh));
		assert (halt_a == (done2 && xOp == 4'h8 && !xCh));
		assert (halt_b == (done2 && xOp == 4'h8 && xCh));
		assert (clear_a == (done2 && xOp == 4'h9 && !xCh));
		assert (clear_b == (done2 && xOp == 4'h9 && xCh));
		assert (host_we_a == (done2 && xOp == 4'hC && !xCh));
		assert (host_we_b == (done2 && xOp == 4'hC && xCh));
		assert (cmd_error == (done2 && expError));
		// Global and per-chain settings.
		assert (line_a == refLineA);
		assert (line_b == refLineB);
		assert (clock_a == refClockA);
		assert (clock_b == refClockB);
		assert (out_a == refOutA);
		assert (out_b == refOutB);
		assert (link_div == refLink);
		if (done2) begin
			if (expWrite) begin
				assert (cfg_sel == expSel);
			end
			case (xOp)
				4'h1, 4'h2: begin
					if (expWrite) begin
						assert (cfg_write == x1[7]);
						assert (cfg_capture == x1[6]);
						assert (cfg_group == x1[5:4]);
						assert (cfg_cycles == {4'd0, x1[3:0]});
						assert (cfg_pin == x2[2:0]);
						if (xOp == 4'h2) begin
							assert (cfg_sr == x2[7]);
							assert (cfg_any == x2[6]);
							assert (cfg_seek == x2[5]);
							assert (cfg_compare == x3);
						end else begin
							assert (!cfg_any && !cfg_seek);
							assert (cfg_compare == startValue);
						end
					end
				end
				4'h3: begin
					assert (cfg_write == (x1[7:6] == 2'b01));
					assert (cfg_follow == (x1[7:6] == 2'b10));
					assert (cfg_wait_end == x1[5]);
					assert (cfg_ack == x1[4]);
					assert (cfg_sr == x1[3]);
					assert (cfg_pin == x1[2:0]);
					assert (cfg_main_cycles == {x2, x3});
				end
				4'h4: if (expWrite) begin
					assert (cfg_cycles == {3'd0, x1[7:3]});
					assert (cfg_pin == x1[2:0]);
					assert (cfg_pair == x2[7]);
					assert (cfg_invert == x2[6]);
					assert (cfg_error == x2[5]);
					assert (cfg_pin_b == x2[2:0]);
					assert (cfg_end_pattern == {x3, x4});
				end
				4'h5: begin
					assert (cfg_main_cycles == {x1, x2});
				end
				4'h6: begin
					assert (cfg_compare == {7'd0, xN[0]});
				end
				4'h7: begin
					assert (run_mode == xN[1:0]);
				end
				4'hC: begin
					// DATA: length N + 1 (1 to 8), then the value.
					assert (host_wdata == {{1'b0, xN} + 4'd1, x1});
				end
				4'hF: begin
					if (expWrite) begin
						assert (cfg_main_cycles == {8'd0, x1});
						assert (cfg_cycles == x2);
						assert (cfg_compare == x3);
					end
				end
				default: begin
				end
			endcase
		end
	end
end

always_comb begin
	if (started && rst_n) begin
		cover (cfg_we_b && cfg_sel == 4'd15 && cfg_end_pattern == 16'hBEEF);
		cover (host_we_a && host_wdata == 12'h8A5);
		cover (cmd_error && xOp == 4'hF);
		cover (cmd_error && xOp == 4'h4 && x1[7:3] == 5'd17);
		cover (clear_b && done2);
	end
end

endmodule
