`ifndef __CORE_MDU_SV
`define __CORE_MDU_SV

module core_mdu
	import common::*;
	import core_pkg::*;(
	input  logic        clk,
	input  logic        reset,
	input  logic        halted,
	input  logic        trap_commit,
	input  logic        stall_pipe,
	input  ex_reg_t     ex_r,
	input  logic        ex_is_mdu,
	output logic        mdu_out_valid,
	output logic [63:0] mdu_out_result
);
	logic        mdu_busy;
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

			if (!halted && !trap_commit && !stall_pipe && ex_r.valid && ex_is_mdu && mdu_out_valid) begin
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
						// Early stop once the remaining multiplier bits are all zero.
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
						// Put the smaller operand on the multiplier side so the early stop fires sooner.
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
endmodule

`endif
