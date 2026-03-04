`ifndef __CORE_SV
`define __CORE_SV

`ifdef VERILATOR
`include "include/common.sv"
`endif

module core import common::*;(
	input  logic       clk, reset,
	output ibus_req_t  ireq,
	input  ibus_resp_t iresp,
	output dbus_req_t  dreq,
	input  dbus_resp_t dresp,
	input  logic       trint, swint, exint
);
	/* TODO: Add your CPU-Core here. */
	localparam logic [31:0] TRAP_INSN = 32'h0005_006b;

	localparam logic [3:0] ALU_ADD  = 4'd0;
	localparam logic [3:0] ALU_SUB  = 4'd1;
	localparam logic [3:0] ALU_XOR  = 4'd2;
	localparam logic [3:0] ALU_OR   = 4'd3;
	localparam logic [3:0] ALU_AND  = 4'd4;
	localparam logic [3:0] ALU_MUL  = 4'd5;
	localparam logic [3:0] ALU_DIV  = 4'd6;
	localparam logic [3:0] ALU_DIVU = 4'd7;
	localparam logic [3:0] ALU_REM  = 4'd8;
	localparam logic [3:0] ALU_REMU = 4'd9;

	typedef struct packed {
		logic        valid;
		logic [63:0] pc;
		logic [31:0] instr;
	} id_reg_t;

	typedef struct packed {
		logic        valid;
		logic        trap;
		logic        wen;
		logic        is_word;
		logic [3:0]  alu_cmd;
		logic [4:0]  rd;
		logic [63:0] pc;
		logic [31:0] instr;
		logic [63:0] op1;
		logic [63:0] op2;
	} ex_reg_t;

	typedef struct packed {
		logic        valid;
		logic        trap;
		logic        wen;
		logic [4:0]  rd;
		logic [63:0] pc;
		logic [31:0] instr;
		logic [63:0] result;
	} wb_like_reg_t;

	logic [63:0] gpr [31:0];
	logic [63:0] gpr_diff [31:0];

	logic [63:0] fetch_pc;
	logic        fetch_fire;
	logic        fetch_pending;
	logic [63:0] fetch_req_pc;
	logic        fetch_buf_valid;
	logic [63:0] fetch_buf_pc;
	logic [31:0] fetch_buf_instr;
	logic        fetch_issue_fire;
	logic        fetch_resp_fire;
	logic [63:0] fetch_req_addr;

	id_reg_t      id_r;
	ex_reg_t      ex_r;
	wb_like_reg_t mem_r;
	wb_like_reg_t wb_r;

	logic [63:0] ex_result;
	logic [63:0] ex_result_word;

	logic [63:0] id_rs1_val, id_rs2_val;
	logic [63:0] id_imm_i;
	logic [6:0]  id_opcode;
	logic [2:0]  id_funct3;
	logic [6:0]  id_funct7;
	logic [4:0]  id_rs1, id_rs2, id_rd;
	logic        id_use_rs1, id_use_rs2;

	logic        id_dec_valid;
	logic        id_dec_trap;
	logic        id_dec_wen;
	logic        id_dec_is_word;
	logic [3:0]  id_dec_alu_cmd;
	logic [63:0] id_dec_op1, id_dec_op2;
	logic [4:0]  id_dec_rd;

	logic        halted;
	logic        trap_commit;
	logic        trap_valid_latched;
	logic [2:0]  trap_code_latched;
	logic [63:0] trap_pc_latched;
	logic [63:0] trap_cycle_latched;
	logic [63:0] trap_instr_latched;

	logic [63:0] cycle_cnt;
	logic [63:0] instr_cnt;

	logic        ex_is_mdu;
	logic        ex_result_ready;
	logic        ex_forwardable;
	logic        stall_ex_busy;
	logic        raw_hazard_ex;
	logic        raw_hazard_mem;
	logic        stall_front;
	logic        mem_result_ready;
	logic        mdu_busy;
	logic        mdu_out_valid;
	logic [63:0] mdu_out_result;
	logic [3:0]  mdu_cmd;
	logic        mdu_is_word;
	logic [6:0]  mdu_steps_left;
	logic [63:0] mdu_mul_acc;
	logic [63:0] mdu_mul_a;
	logic [63:0] mdu_mul_b;
	logic [64:0] mdu_div_rem;
	logic [63:0] mdu_div_quot;
	logic [63:0] mdu_div_divisor;
	logic        mdu_div_signed;
	logic        mdu_div_is_rem;
	logic        mdu_q_neg;
	logic        mdu_r_neg;

	integer i;

	function automatic logic is_mdu_cmd(input logic [3:0] cmd);
		begin
			is_mdu_cmd = (cmd == ALU_MUL) || (cmd == ALU_DIV) || (cmd == ALU_DIVU) || (cmd == ALU_REM) || (cmd == ALU_REMU);
		end
	endfunction


	assign dreq = '0;
	assign ex_is_mdu = is_mdu_cmd(ex_r.alu_cmd);
	assign ex_result_ready = !ex_is_mdu || mdu_out_valid;
	assign stall_ex_busy = ex_r.valid && !ex_result_ready;
	assign ex_forwardable = ex_r.valid && ex_r.wen && (ex_r.rd != 0) && ex_result_ready;
	assign mem_result_ready = 1'b1;
	assign raw_hazard_ex =
		id_r.valid && ex_r.valid && ex_r.wen && (ex_r.rd != 0) && !ex_result_ready &&
		((id_use_rs1 && (id_rs1 == ex_r.rd)) || (id_use_rs2 && (id_rs2 == ex_r.rd)));
	assign raw_hazard_mem =
		id_r.valid && mem_r.valid && mem_r.wen && (mem_r.rd != 0) && !mem_result_ready &&
		((id_use_rs1 && (id_rs1 == mem_r.rd)) || (id_use_rs2 && (id_rs2 == mem_r.rd)));
	assign stall_front = stall_ex_busy || raw_hazard_ex || raw_hazard_mem;
	assign fetch_fire = (!halted) && (!stall_front) && fetch_buf_valid;
	assign fetch_issue_fire = (!halted) && (!stall_front) && (!fetch_pending) && (!fetch_buf_valid || fetch_fire);
	assign fetch_req_addr = fetch_pending ? fetch_req_pc : fetch_pc;
	assign ireq.valid = !halted && (fetch_pending || fetch_issue_fire);
	assign ireq.addr  = fetch_req_addr;
	assign fetch_resp_fire = ireq.valid && iresp.data_ok;

	assign id_opcode = id_r.instr[6:0];
	assign id_funct3 = id_r.instr[14:12];
	assign id_funct7 = id_r.instr[31:25];
	assign id_rs1    = id_r.instr[19:15];
	assign id_rs2    = id_r.instr[24:20];
	assign id_rd     = id_r.instr[11:7];
	assign id_imm_i  = {{52{id_r.instr[31]}}, id_r.instr[31:20]};
	assign id_use_rs1 = (id_opcode == 7'b0010011) || (id_opcode == 7'b0110011) || (id_opcode == 7'b0011011) || (id_opcode == 7'b0111011);
	assign id_use_rs2 = (id_opcode == 7'b0110011) || (id_opcode == 7'b0111011);

	always_comb begin
		id_rs1_val = (id_rs1 == 0) ? 64'd0 : gpr[id_rs1];
		id_rs2_val = (id_rs2 == 0) ? 64'd0 : gpr[id_rs2];

		if (id_use_rs1 && ex_forwardable && (ex_r.rd == id_rs1)) id_rs1_val = ex_result;
		else if (id_use_rs1 && mem_r.valid && mem_r.wen && (mem_r.rd != 0) && (mem_r.rd == id_rs1)) id_rs1_val = mem_r.result;
		else if (id_use_rs1 && wb_r.valid && wb_r.wen && (wb_r.rd != 0) && (wb_r.rd == id_rs1)) id_rs1_val = wb_r.result;

		if (id_use_rs2 && ex_forwardable && (ex_r.rd == id_rs2)) id_rs2_val = ex_result;
		else if (id_use_rs2 && mem_r.valid && mem_r.wen && (mem_r.rd != 0) && (mem_r.rd == id_rs2)) id_rs2_val = mem_r.result;
		else if (id_use_rs2 && wb_r.valid && wb_r.wen && (wb_r.rd != 0) && (wb_r.rd == id_rs2)) id_rs2_val = wb_r.result;
	end

	always_comb begin
		id_dec_valid   = id_r.valid;
		id_dec_trap    = 1'b0;
		id_dec_wen     = 1'b0;
		id_dec_is_word = 1'b0;
		id_dec_alu_cmd = ALU_ADD;
		id_dec_op1     = id_rs1_val;
		id_dec_op2     = id_rs2_val;
		id_dec_rd      = id_rd;

		if (id_r.instr == TRAP_INSN) begin
			id_dec_trap = 1'b1;
		end else begin
			unique case (id_opcode)
				7'b0010011: begin
					unique case (id_funct3)
						3'b000: begin id_dec_wen = 1'b1; id_dec_alu_cmd = ALU_ADD; id_dec_op2 = id_imm_i; end
						3'b100: begin id_dec_wen = 1'b1; id_dec_alu_cmd = ALU_XOR; id_dec_op2 = id_imm_i; end
						3'b110: begin id_dec_wen = 1'b1; id_dec_alu_cmd = ALU_OR;  id_dec_op2 = id_imm_i; end
						3'b111: begin id_dec_wen = 1'b1; id_dec_alu_cmd = ALU_AND; id_dec_op2 = id_imm_i; end
						default: begin end
					endcase
				end
				7'b0110011: begin
					if (id_funct7 == 7'b0000001) begin
						unique case (id_funct3)
							3'b000: begin id_dec_wen = 1'b1; id_dec_alu_cmd = ALU_MUL;  end
							3'b100: begin id_dec_wen = 1'b1; id_dec_alu_cmd = ALU_DIV;  end
							3'b101: begin id_dec_wen = 1'b1; id_dec_alu_cmd = ALU_DIVU; end
							3'b110: begin id_dec_wen = 1'b1; id_dec_alu_cmd = ALU_REM;  end
							3'b111: begin id_dec_wen = 1'b1; id_dec_alu_cmd = ALU_REMU; end
							default: begin end
						endcase
					end else begin
						unique case (id_funct3)
							3'b000: begin id_dec_wen = 1'b1; id_dec_alu_cmd = id_funct7[5] ? ALU_SUB : ALU_ADD; end
							3'b100: begin id_dec_wen = 1'b1; id_dec_alu_cmd = ALU_XOR; end
							3'b110: begin id_dec_wen = 1'b1; id_dec_alu_cmd = ALU_OR;  end
							3'b111: begin id_dec_wen = 1'b1; id_dec_alu_cmd = ALU_AND; end
							default: begin end
						endcase
					end
				end
				7'b0011011: begin
					if (id_funct3 == 3'b000) begin
						id_dec_wen = 1'b1;
						id_dec_is_word = 1'b1;
						id_dec_alu_cmd = ALU_ADD;
						id_dec_op2 = id_imm_i;
					end
				end
				7'b0111011: begin
					if (id_funct7 == 7'b0000001) begin
						unique case (id_funct3)
							3'b000: begin id_dec_wen = 1'b1; id_dec_is_word = 1'b1; id_dec_alu_cmd = ALU_MUL;  end
							3'b100: begin id_dec_wen = 1'b1; id_dec_is_word = 1'b1; id_dec_alu_cmd = ALU_DIV;  end
							3'b101: begin id_dec_wen = 1'b1; id_dec_is_word = 1'b1; id_dec_alu_cmd = ALU_DIVU; end
							3'b110: begin id_dec_wen = 1'b1; id_dec_is_word = 1'b1; id_dec_alu_cmd = ALU_REM;  end
							3'b111: begin id_dec_wen = 1'b1; id_dec_is_word = 1'b1; id_dec_alu_cmd = ALU_REMU; end
							default: begin end
						endcase
					end else if (id_funct3 == 3'b000) begin
						id_dec_wen = 1'b1;
						id_dec_is_word = 1'b1;
						id_dec_alu_cmd = id_funct7[5] ? ALU_SUB : ALU_ADD;
					end
				end
				default: begin end
			endcase
		end
	end

	always_comb begin
		ex_result = 64'd0;
		unique case (ex_r.alu_cmd)
			ALU_ADD: ex_result = ex_r.op1 + ex_r.op2;
			ALU_SUB: ex_result = ex_r.op1 - ex_r.op2;
			ALU_XOR: ex_result = ex_r.op1 ^ ex_r.op2;
			ALU_OR : ex_result = ex_r.op1 | ex_r.op2;
			ALU_AND: ex_result = ex_r.op1 & ex_r.op2;
			ALU_MUL,
			ALU_DIV,
			ALU_DIVU,
			ALU_REM,
			ALU_REMU: ex_result = mdu_out_result;
			default: begin end
		endcase

		ex_result_word = {{32{ex_result[31]}}, ex_result[31:0]};
		if (ex_r.is_word &&
			(ex_r.alu_cmd == ALU_ADD || ex_r.alu_cmd == ALU_SUB || ex_r.alu_cmd == ALU_XOR || ex_r.alu_cmd == ALU_OR || ex_r.alu_cmd == ALU_AND)) begin
			ex_result = ex_result_word;
		end
	end

	always_ff @(posedge clk) begin
		if (reset) begin
			mdu_busy <= 1'b0;
			mdu_out_valid <= 1'b0;
			mdu_out_result <= 64'd0;
			mdu_cmd <= ALU_ADD;
			mdu_is_word <= 1'b0;
			mdu_steps_left <= 7'd0;
			mdu_mul_acc <= 64'd0;
			mdu_mul_a <= 64'd0;
			mdu_mul_b <= 64'd0;
			mdu_div_rem <= 65'd0;
			mdu_div_quot <= 64'd0;
			mdu_div_divisor <= 64'd0;
			mdu_div_signed <= 1'b0;
			mdu_div_is_rem <= 1'b0;
			mdu_q_neg <= 1'b0;
			mdu_r_neg <= 1'b0;
		end else begin
			logic [63:0] width_mask;
			logic [6:0]  width_steps;
			logic [5:0]  sign_bit;
			logic [63:0] op1_eff;
			logic [63:0] op2_eff;
			logic [63:0] dividend_abs;
			logic [63:0] divisor_abs;
			logic        op1_neg;
			logic        op2_neg;
			logic [63:0] mul_acc_next;
			logic [63:0] mul_a_next;
			logic [63:0] mul_b_next;
			logic [64:0] div_rem_next;
			logic [63:0] div_quot_next;
			logic [63:0] q_unsigned;
			logic [63:0] r_unsigned;
			logic [63:0] final_val;
			logic [63:0] mul_src0;
			logic [63:0] mul_src1;
			logic [63:0] div_q_abs_fast;
			logic [63:0] div_r_abs_fast;
			logic [63:0] div_pow2_mask;
			logic        div_is_pow2;
			logic [5:0]  div_pow2_shift;
			logic        div_is_signed;
			logic        div_is_rem;

			width_mask = ex_r.is_word ? 64'h0000_0000_ffff_ffff : 64'hffff_ffff_ffff_ffff;
			width_steps = ex_r.is_word ? 7'd32 : 7'd64;
			sign_bit = ex_r.is_word ? 6'd31 : 6'd63;
			op1_eff = ex_r.is_word ? {32'd0, ex_r.op1[31:0]} : ex_r.op1;
			op2_eff = ex_r.is_word ? {32'd0, ex_r.op2[31:0]} : ex_r.op2;

			if (!halted && !trap_commit && !stall_front && ex_r.valid && ex_is_mdu && mdu_out_valid) begin
				mdu_out_valid <= 1'b0;
			end

			if (mdu_busy) begin
				if (mdu_cmd == ALU_MUL) begin
					mul_acc_next = mdu_mul_acc;
					mul_a_next = mdu_mul_a;
					mul_b_next = mdu_mul_b;
					if (mdu_mul_b[0]) mul_acc_next = (mdu_mul_acc + mdu_mul_a) & width_mask;
					mul_a_next = (mdu_mul_a << 1) & width_mask;
					mul_b_next = (mdu_mul_b >> 1);

					mdu_mul_acc <= mul_acc_next;
					mdu_mul_a <= mul_a_next;
					mdu_mul_b <= mul_b_next;
					mdu_steps_left <= mdu_steps_left - 7'd1;

					if (mdu_steps_left == 7'd1) begin
						mdu_busy <= 1'b0;
						if (mdu_is_word) mdu_out_result <= {{32{mul_acc_next[31]}}, mul_acc_next[31:0]};
						else mdu_out_result <= mul_acc_next;
						mdu_out_valid <= 1'b1;
					end else if (mul_b_next == 64'd0) begin
						// Early stop when the remaining multiplier bits are all zero.
						mdu_busy <= 1'b0;
						if (mdu_is_word) mdu_out_result <= {{32{mul_acc_next[31]}}, mul_acc_next[31:0]};
						else mdu_out_result <= mul_acc_next;
						mdu_out_valid <= 1'b1;
					end
				end else begin
					div_rem_next = {mdu_div_rem[63:0], mdu_div_quot[63]};
					div_quot_next = {mdu_div_quot[62:0], 1'b0};
					if (div_rem_next >= {1'b0, mdu_div_divisor}) begin
						div_rem_next = div_rem_next - {1'b0, mdu_div_divisor};
						div_quot_next[0] = 1'b1;
					end

					mdu_div_rem <= div_rem_next;
					mdu_div_quot <= div_quot_next;
					mdu_steps_left <= mdu_steps_left - 7'd1;

					if (mdu_steps_left == 7'd1) begin
						q_unsigned = div_quot_next & (mdu_is_word ? 64'h0000_0000_ffff_ffff : 64'hffff_ffff_ffff_ffff);
						r_unsigned = div_rem_next[63:0] & (mdu_is_word ? 64'h0000_0000_ffff_ffff : 64'hffff_ffff_ffff_ffff);
						final_val = mdu_div_is_rem ? r_unsigned : q_unsigned;
						if (mdu_div_signed) begin
							if (!mdu_div_is_rem && mdu_q_neg) final_val = (~q_unsigned + 64'd1) & (mdu_is_word ? 64'h0000_0000_ffff_ffff : 64'hffff_ffff_ffff_ffff);
							if (mdu_div_is_rem && mdu_r_neg) final_val = (~r_unsigned + 64'd1) & (mdu_is_word ? 64'h0000_0000_ffff_ffff : 64'hffff_ffff_ffff_ffff);
						end

						mdu_busy <= 1'b0;
						if (mdu_is_word) mdu_out_result <= {{32{final_val[31]}}, final_val[31:0]};
						else mdu_out_result <= final_val;
						mdu_out_valid <= 1'b1;
					end
				end
			end else if (!halted && ex_r.valid && ex_is_mdu && !mdu_out_valid) begin
				mdu_cmd <= ex_r.alu_cmd;
				mdu_is_word <= ex_r.is_word;

				if (ex_r.alu_cmd == ALU_MUL) begin
					mul_src0 = op1_eff & width_mask;
					mul_src1 = op2_eff & width_mask;
					if ((mul_src0 == 64'd0) || (mul_src1 == 64'd0)) begin
						final_val = 64'd0;
						if (ex_r.is_word) mdu_out_result <= {{32{final_val[31]}}, final_val[31:0]};
						else mdu_out_result <= final_val;
						mdu_out_valid <= 1'b1;
						mdu_busy <= 1'b0;
					end else if (mul_src0 == 64'd1) begin
						final_val = mul_src1;
						if (ex_r.is_word) mdu_out_result <= {{32{final_val[31]}}, final_val[31:0]};
						else mdu_out_result <= final_val;
						mdu_out_valid <= 1'b1;
						mdu_busy <= 1'b0;
					end else if (mul_src1 == 64'd1) begin
						final_val = mul_src0;
						if (ex_r.is_word) mdu_out_result <= {{32{final_val[31]}}, final_val[31:0]};
						else mdu_out_result <= final_val;
						mdu_out_valid <= 1'b1;
						mdu_busy <= 1'b0;
					end else begin
						// Put the smaller value on multiplier side to trigger zero-detection early stop sooner.
						mdu_busy <= 1'b1;
						mdu_steps_left <= width_steps;
						mdu_mul_acc <= 64'd0;
						if (mul_src0 <= mul_src1) begin
							mdu_mul_a <= mul_src1;
							mdu_mul_b <= mul_src0;
						end else begin
							mdu_mul_a <= mul_src0;
							mdu_mul_b <= mul_src1;
						end
					end
				end else begin
					div_is_signed = (ex_r.alu_cmd == ALU_DIV) || (ex_r.alu_cmd == ALU_REM);
					div_is_rem = (ex_r.alu_cmd == ALU_REM) || (ex_r.alu_cmd == ALU_REMU);
					mdu_div_signed <= div_is_signed;
					mdu_div_is_rem <= div_is_rem;
					op1_neg = div_is_signed && op1_eff[sign_bit];
					op2_neg = div_is_signed && op2_eff[sign_bit];
					dividend_abs = op1_neg ? ((~op1_eff + 64'd1) & width_mask) : (op1_eff & width_mask);
					divisor_abs = op2_neg ? ((~op2_eff + 64'd1) & width_mask) : (op2_eff & width_mask);
					div_is_pow2 = ((divisor_abs & (divisor_abs - 64'd1)) == 64'd0);
					div_pow2_shift = 6'd0;
					for (int b = 0; b < 64; b = b + 1) begin
						if (divisor_abs[b]) div_pow2_shift = b[5:0];
					end
					div_pow2_mask = (div_pow2_shift == 6'd0) ? 64'd0 : ((64'd1 << div_pow2_shift) - 64'd1);
					mdu_q_neg <= op1_neg ^ op2_neg;
					mdu_r_neg <= op1_neg;

					if ((op2_eff & width_mask) == 64'd0) begin
						final_val = div_is_rem ? (op1_eff & width_mask) : width_mask;
						if (ex_r.is_word) mdu_out_result <= {{32{final_val[31]}}, final_val[31:0]};
						else mdu_out_result <= final_val;
						mdu_out_valid <= 1'b1;
						mdu_busy <= 1'b0;
					end else if (((ex_r.alu_cmd == ALU_DIV) || (ex_r.alu_cmd == ALU_REM)) &&
						((op1_eff & width_mask) == (ex_r.is_word ? 64'h0000_0000_8000_0000 : 64'h8000_0000_0000_0000)) &&
						((op2_eff & width_mask) == (ex_r.is_word ? 64'h0000_0000_ffff_ffff : 64'hffff_ffff_ffff_ffff))) begin
						final_val = (ex_r.alu_cmd == ALU_DIV) ? (op1_eff & width_mask) : 64'd0;
						if (ex_r.is_word) mdu_out_result <= {{32{final_val[31]}}, final_val[31:0]};
						else mdu_out_result <= final_val;
						mdu_out_valid <= 1'b1;
						mdu_busy <= 1'b0;
					end else if (dividend_abs == 64'd0) begin
						final_val = 64'd0;
						if (ex_r.is_word) mdu_out_result <= {{32{final_val[31]}}, final_val[31:0]};
						else mdu_out_result <= final_val;
						mdu_out_valid <= 1'b1;
						mdu_busy <= 1'b0;
					end else if (divisor_abs == 64'd1) begin
						div_q_abs_fast = dividend_abs & width_mask;
						div_r_abs_fast = 64'd0;
						q_unsigned = div_q_abs_fast & width_mask;
						r_unsigned = div_r_abs_fast & width_mask;
						final_val = div_is_rem ? r_unsigned : q_unsigned;
						if (div_is_signed) begin
							if (!div_is_rem && (op1_neg ^ op2_neg)) final_val = (~q_unsigned + 64'd1) & width_mask;
							if (div_is_rem && op1_neg) final_val = (~r_unsigned + 64'd1) & width_mask;
						end
						if (ex_r.is_word) mdu_out_result <= {{32{final_val[31]}}, final_val[31:0]};
						else mdu_out_result <= final_val;
						mdu_out_valid <= 1'b1;
						mdu_busy <= 1'b0;
					end else if (dividend_abs < divisor_abs) begin
						div_q_abs_fast = 64'd0;
						div_r_abs_fast = dividend_abs & width_mask;
						q_unsigned = div_q_abs_fast & width_mask;
						r_unsigned = div_r_abs_fast & width_mask;
						final_val = div_is_rem ? r_unsigned : q_unsigned;
						if (div_is_signed) begin
							if (!div_is_rem && (op1_neg ^ op2_neg)) final_val = (~q_unsigned + 64'd1) & width_mask;
							if (div_is_rem && op1_neg) final_val = (~r_unsigned + 64'd1) & width_mask;
						end
						if (ex_r.is_word) mdu_out_result <= {{32{final_val[31]}}, final_val[31:0]};
						else mdu_out_result <= final_val;
						mdu_out_valid <= 1'b1;
						mdu_busy <= 1'b0;
					end else if (div_is_pow2) begin
						div_q_abs_fast = (dividend_abs >> div_pow2_shift) & width_mask;
						div_r_abs_fast = dividend_abs & div_pow2_mask;
						q_unsigned = div_q_abs_fast & width_mask;
						r_unsigned = div_r_abs_fast & width_mask;
						final_val = div_is_rem ? r_unsigned : q_unsigned;
						if (div_is_signed) begin
							if (!div_is_rem && (op1_neg ^ op2_neg)) final_val = (~q_unsigned + 64'd1) & width_mask;
							if (div_is_rem && op1_neg) final_val = (~r_unsigned + 64'd1) & width_mask;
						end
						if (ex_r.is_word) mdu_out_result <= {{32{final_val[31]}}, final_val[31:0]};
						else mdu_out_result <= final_val;
						mdu_out_valid <= 1'b1;
						mdu_busy <= 1'b0;
					end else begin

						mdu_busy <= 1'b1;
						mdu_steps_left <= width_steps;
						mdu_div_rem <= 65'd0;
						mdu_div_quot <= (dividend_abs & width_mask) << (7'd64 - width_steps);
						mdu_div_divisor <= divisor_abs & width_mask;
					end
				end
			end
		end
	end

	assign trap_commit = wb_r.valid && wb_r.trap;

	always_ff @(posedge clk) begin
		if (reset) begin
			fetch_pc <= PCINIT;
			fetch_pending <= 1'b0;
			fetch_req_pc <= 64'd0;
			fetch_buf_valid <= 1'b0;
			fetch_buf_pc <= 64'd0;
			fetch_buf_instr <= 32'd0;
			id_r <= '0;
			ex_r <= '0;
			mem_r <= '0;
			wb_r <= '0;
			halted <= 1'b0;
			trap_valid_latched <= 1'b0;
			trap_code_latched <= 3'd0;
			trap_pc_latched <= 64'd0;
			trap_cycle_latched <= 64'd0;
			trap_instr_latched <= 64'd0;
			cycle_cnt <= 64'd0;
			instr_cnt <= 64'd0;
			for (i = 0; i < 32; i = i + 1) begin
				gpr[i] <= 64'd0;
			end
		end else begin
			cycle_cnt <= cycle_cnt + 64'd1;
			if (wb_r.valid) instr_cnt <= instr_cnt + 64'd1;

			if (wb_r.valid && wb_r.wen && (wb_r.rd != 0)) begin
				gpr[wb_r.rd] <= wb_r.result;
			end
			gpr[0] <= 64'd0;

			if (trap_commit) begin
				halted <= 1'b1;
				fetch_pending <= 1'b0;
				fetch_buf_valid <= 1'b0;
				trap_valid_latched <= 1'b1;
				trap_code_latched <= gpr[10][2:0];
				trap_pc_latched <= wb_r.pc;
				trap_cycle_latched <= cycle_cnt;
				trap_instr_latched <= instr_cnt + 64'd1;
			end

			if (!halted && !trap_commit) begin
				if (fetch_resp_fire) begin
					fetch_buf_valid <= 1'b1;
					fetch_buf_pc <= fetch_req_addr;
					fetch_buf_instr <= iresp.data;
					fetch_pc <= fetch_req_addr + 64'd4;
					fetch_pending <= 1'b0;
				end else if (fetch_issue_fire) begin
					fetch_pending <= 1'b1;
					fetch_req_pc <= fetch_pc;
				end
				if (fetch_fire && !fetch_resp_fire) begin
					fetch_buf_valid <= 1'b0;
				end

				wb_r.valid <= mem_r.valid;
				wb_r.trap  <= mem_r.trap;
				wb_r.wen   <= mem_r.wen;
				wb_r.rd    <= mem_r.rd;
				wb_r.pc    <= mem_r.pc;
				wb_r.instr <= mem_r.instr;
				wb_r.result<= mem_r.result;

				if (stall_front) begin
					mem_r <= '0;
				end else begin
					mem_r.valid <= ex_r.valid;
					mem_r.trap  <= ex_r.trap;
					mem_r.wen   <= ex_r.wen;
					mem_r.rd    <= ex_r.rd;
					mem_r.pc    <= ex_r.pc;
					mem_r.instr <= ex_r.instr;
					mem_r.result<= ex_result;

					ex_r.valid   <= id_dec_valid;
					ex_r.trap    <= id_dec_trap;
					ex_r.wen     <= id_dec_wen;
					ex_r.is_word <= id_dec_is_word;
					ex_r.alu_cmd <= id_dec_alu_cmd;
					ex_r.rd      <= id_dec_rd;
					ex_r.pc      <= id_r.pc;
					ex_r.instr   <= id_r.instr;
					ex_r.op1     <= id_dec_op1;
					ex_r.op2     <= id_dec_op2;

					if (fetch_fire) begin
						id_r.valid <= 1'b1;
						id_r.pc    <= fetch_buf_pc;
						id_r.instr <= fetch_buf_instr;
					end else begin
						id_r.valid <= 1'b0;
						id_r.pc    <= 64'd0;
						id_r.instr <= 32'd0;
					end
				end
			end else begin
				id_r.valid  <= 1'b0;
				ex_r.valid  <= 1'b0;
				mem_r.valid <= 1'b0;
				wb_r.valid  <= 1'b0;
			end
		end
	end

	always_comb begin
		for (int j = 0; j < 32; j = j + 1) begin
			gpr_diff[j] = gpr[j];
		end
		if (wb_r.valid && wb_r.wen && (wb_r.rd != 0)) begin
			gpr_diff[wb_r.rd] = wb_r.result;
		end
		gpr_diff[0] = 64'd0;
	end

`ifdef VERILATOR
	DifftestInstrCommit DifftestInstrCommit(
		.clock              (clk),
		.coreid             (0),
		.index              (0),
		.valid              (wb_r.valid),
		.pc                 (wb_r.pc),
		.instr              (wb_r.instr),
		.skip               (0),
		.isRVC              (0),
		.scFailed           (0),
		.wen                (wb_r.valid && wb_r.wen && (wb_r.rd != 0)),
		.wdest              ({3'd0, wb_r.rd}),
		.wdata              (wb_r.result)
	);

	DifftestArchIntRegState DifftestArchIntRegState (
		.clock              (clk),
		.coreid             (0),
		.gpr_0              (gpr_diff[0]),
		.gpr_1              (gpr_diff[1]),
		.gpr_2              (gpr_diff[2]),
		.gpr_3              (gpr_diff[3]),
		.gpr_4              (gpr_diff[4]),
		.gpr_5              (gpr_diff[5]),
		.gpr_6              (gpr_diff[6]),
		.gpr_7              (gpr_diff[7]),
		.gpr_8              (gpr_diff[8]),
		.gpr_9              (gpr_diff[9]),
		.gpr_10             (gpr_diff[10]),
		.gpr_11             (gpr_diff[11]),
		.gpr_12             (gpr_diff[12]),
		.gpr_13             (gpr_diff[13]),
		.gpr_14             (gpr_diff[14]),
		.gpr_15             (gpr_diff[15]),
		.gpr_16             (gpr_diff[16]),
		.gpr_17             (gpr_diff[17]),
		.gpr_18             (gpr_diff[18]),
		.gpr_19             (gpr_diff[19]),
		.gpr_20             (gpr_diff[20]),
		.gpr_21             (gpr_diff[21]),
		.gpr_22             (gpr_diff[22]),
		.gpr_23             (gpr_diff[23]),
		.gpr_24             (gpr_diff[24]),
		.gpr_25             (gpr_diff[25]),
		.gpr_26             (gpr_diff[26]),
		.gpr_27             (gpr_diff[27]),
		.gpr_28             (gpr_diff[28]),
		.gpr_29             (gpr_diff[29]),
		.gpr_30             (gpr_diff[30]),
		.gpr_31             (gpr_diff[31])
	);

    DifftestTrapEvent DifftestTrapEvent(
		.clock              (clk),
		.coreid             (0),
		.valid              (trap_valid_latched),
		.code               (trap_code_latched),
		.pc                 (trap_pc_latched),
		.cycleCnt           (trap_cycle_latched),
		.instrCnt           (trap_instr_latched)
	);

	DifftestCSRState DifftestCSRState(
		.clock              (clk),
		.coreid             (0),
		.priviledgeMode     (3),
		.mstatus            (0),
		.sstatus            (0 /* mstatus & 64'h800000030001e000 */),
		.mepc               (0),
		.sepc               (0),
		.mtval              (0),
		.stval              (0),
		.mtvec              (0),
		.stvec              (0),
		.mcause             (0),
		.scause             (0),
		.satp               (0),
		.mip                (0),
		.mie                (0),
		.mscratch           (0),
		.sscratch           (0),
		.mideleg            (0),
		.medeleg            (0)
	);
`endif
endmodule
`endif
