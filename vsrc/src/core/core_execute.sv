`ifndef __CORE_EXECUTE_SV
`define __CORE_EXECUTE_SV

module core_execute
	import common::*;
	import core_pkg::*;(
	input  ex_reg_t       ex_r,
	input  wb_like_reg_t  mem_r,
	input  wb_like_reg_t  wb_r,
	input  dbus_resp_t    dresp,
	input  logic          ex_is_mdu,
	input  logic          mdu_out_valid,
	input  logic [63:0]   mdu_out_result,
	output logic          ex_result_ready,
	output logic          ex_forwardable,
	output logic          stall_ex_busy,
	output logic [63:0]   ex_result,
	output logic [63:0]   ex_mem_addr,
	output logic          ex_flush_front,
	output logic [63:0]   ex_redirect_pc,
	output logic          mem_access_done,
	output logic          mem_result_ready,
	output logic          stall_mem_busy,
	output logic          stall_if_mem,
	output logic [63:0]   mem_stage_result,
	output logic [63:0]   mem_store_data_shifted,
	output logic [7:0]    mem_store_strobe,
	output logic          difftest_skip
);
	logic [63:0] ex_result_word;
	logic [63:0] ex_next_pc;
	logic        ex_branch_taken;
	logic [63:0] mem_load_data;
	logic [63:0] mem_aligned_data;
	logic [5:0]  mem_byte_shift;

	assign ex_result_ready = ex_is_mdu ? mdu_out_valid : !ex_r.is_load;
	assign stall_ex_busy   = ex_r.valid && ex_is_mdu && !mdu_out_valid;
	assign ex_forwardable  = ex_r.valid && ex_r.wen && (ex_r.rd != 0) && ex_result_ready;

	assign mem_access_done = (!mem_r.is_load && !mem_r.is_store) || dresp.data_ok;
	assign mem_result_ready = !mem_r.valid || !mem_r.is_load || mem_access_done;
	assign stall_mem_busy = mem_r.valid && (mem_r.is_load || mem_r.is_store) && !mem_access_done;
	assign stall_if_mem   = mem_r.valid && (mem_r.is_load || mem_r.is_store);

	always_comb begin
		ex_result = 64'd0;
		unique case (ex_r.alu_cmd)
			ALU_ADD: ex_result = ex_r.op1 + ex_r.op2;
			ALU_SUB: ex_result = ex_r.op1 - ex_r.op2;
			ALU_XOR: ex_result = ex_r.op1 ^ ex_r.op2;
			ALU_OR : ex_result = ex_r.op1 | ex_r.op2;
			ALU_AND: ex_result = ex_r.op1 & ex_r.op2;
			ALU_SLL: ex_result = ex_r.is_word ? {32'd0, (ex_r.op1[31:0] << ex_r.op2[4:0])} : (ex_r.op1 << ex_r.op2[5:0]);
			ALU_SRL: ex_result = ex_r.is_word ? {32'd0, (ex_r.op1[31:0] >> ex_r.op2[4:0])} : (ex_r.op1 >> ex_r.op2[5:0]);
			ALU_SRA: ex_result = ex_r.is_word ? {32'd0, $unsigned($signed(ex_r.op1[31:0]) >>> ex_r.op2[4:0])} : ($signed(ex_r.op1) >>> ex_r.op2[5:0]);
			ALU_SLT: ex_result = ($signed(ex_r.op1) < $signed(ex_r.op2)) ? 64'd1 : 64'd0;
			ALU_SLTU: ex_result = (ex_r.op1 < ex_r.op2) ? 64'd1 : 64'd0;
			ALU_MUL,
			ALU_DIV,
			ALU_DIVU,
			ALU_REM,
			ALU_REMU: ex_result = mdu_out_result;
			default: begin end
		endcase

		ex_result_word = {{32{ex_result[31]}}, ex_result[31:0]};
		if (ex_r.is_word &&
			(ex_r.alu_cmd == ALU_ADD || ex_r.alu_cmd == ALU_SUB || ex_r.alu_cmd == ALU_XOR ||
			 ex_r.alu_cmd == ALU_OR  || ex_r.alu_cmd == ALU_AND || ex_r.alu_cmd == ALU_SLL ||
			 ex_r.alu_cmd == ALU_SRL || ex_r.alu_cmd == ALU_SRA)) begin
			ex_result = ex_result_word;
		end
	end

	always_comb begin
		ex_branch_taken = 1'b0;
		if (ex_r.is_branch) begin
			unique case (ex_r.br_funct3)
				3'b000: ex_branch_taken = (ex_r.op1 == ex_r.op2);
				3'b001: ex_branch_taken = (ex_r.op1 != ex_r.op2);
				3'b100: ex_branch_taken = ($signed(ex_r.op1) < $signed(ex_r.op2));
				3'b101: ex_branch_taken = ($signed(ex_r.op1) >= $signed(ex_r.op2));
				3'b110: ex_branch_taken = (ex_r.op1 < ex_r.op2);
				3'b111: ex_branch_taken = (ex_r.op1 >= ex_r.op2);
				default: ex_branch_taken = 1'b0;
			endcase
		end
		if (ex_r.is_jal || ex_r.is_jalr) ex_branch_taken = 1'b1;
	end

	assign ex_next_pc = ex_r.is_jalr ? ((ex_r.op1 + ex_r.imm) & ~64'd1) : (ex_r.pc + ex_r.imm);
	assign ex_flush_front = ex_r.valid && ex_branch_taken;
	assign ex_redirect_pc = ex_next_pc;
	assign ex_mem_addr    = ex_r.op1 + ex_r.imm;

	always_comb begin
		mem_store_strobe = 8'd0;
		unique case (ex_r.mem_size)
			MSIZE1: mem_store_strobe = 8'b0000_0001 << ex_mem_addr[2:0];
			MSIZE2: mem_store_strobe = 8'b0000_0011 << ex_mem_addr[2:0];
			MSIZE4: mem_store_strobe = 8'b0000_1111 << ex_mem_addr[2:0];
			MSIZE8: mem_store_strobe = 8'b1111_1111;
			default: mem_store_strobe = 8'd0;
		endcase
	end

	assign mem_store_data_shifted = ex_r.rs2_store << ({ex_mem_addr[2:0], 3'b000});
	assign mem_byte_shift = {3'd0, mem_r.mem_addr[2:0]};
	assign mem_aligned_data = dresp.data >> (mem_byte_shift * 6'd8);

	always_comb begin
		mem_load_data = 64'd0;
		unique case (mem_r.mem_size)
			MSIZE1: mem_load_data = mem_r.mem_unsigned ? {56'd0, mem_aligned_data[7:0]} : {{56{mem_aligned_data[7]}}, mem_aligned_data[7:0]};
			MSIZE2: mem_load_data = mem_r.mem_unsigned ? {48'd0, mem_aligned_data[15:0]} : {{48{mem_aligned_data[15]}}, mem_aligned_data[15:0]};
			MSIZE4: mem_load_data = mem_r.mem_unsigned ? {32'd0, mem_aligned_data[31:0]} : {{32{mem_aligned_data[31]}}, mem_aligned_data[31:0]};
			MSIZE8: mem_load_data = mem_aligned_data;
			default: mem_load_data = mem_aligned_data;
		endcase
	end

	assign mem_stage_result = mem_r.is_load ? mem_load_data : mem_r.result;
	assign difftest_skip = wb_r.valid && (wb_r.is_load || wb_r.is_store) && !wb_r.mem_addr[31];
endmodule

`endif
