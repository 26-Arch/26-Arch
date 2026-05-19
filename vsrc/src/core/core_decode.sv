`ifndef __CORE_DECODE_SV
`define __CORE_DECODE_SV

module core_decode
	import common::*;
	import core_pkg::*;(
	input  id_reg_t       id_r,
	input  ex_reg_t       ex_r,
	input  wb_like_reg_t  mem_r,
	input  wb_like_reg_t  wb_r,
	input  logic [63:0]   gpr [31:0],
	input  logic [63:0]   csr_mstatus,
	input  logic [63:0]   csr_mtvec,
	input  logic [63:0]   csr_mip,
	input  logic [63:0]   csr_mie,
	input  logic [63:0]   csr_mscratch,
	input  logic [63:0]   csr_mcause,
	input  logic [63:0]   csr_mtval,
	input  logic [63:0]   csr_mepc,
	input  logic [63:0]   csr_mcycle,
	input  logic [63:0]   csr_mhartid,
	input  logic [63:0]   csr_satp,
	input  logic          ex_forwardable,
	input  logic [63:0]   ex_result,
	output logic [4:0]    id_rs1,
	output logic [4:0]    id_rs2,
	output logic          id_use_rs1,
	output logic          id_use_rs2,
	output logic          id_dec_valid,
	output logic          id_dec_trap,
	output logic          id_dec_wen,
	output logic          id_dec_is_word,
	output logic [3:0]    id_dec_alu_cmd,
	output logic [63:0]   id_dec_op1,
	output logic [63:0]   id_dec_op2,
	output logic [63:0]   id_dec_imm,
	output logic [63:0]   id_dec_rs2_store,
	output logic [4:0]    id_dec_rd,
	output logic          id_dec_is_load,
	output logic          id_dec_is_store,
	output logic [2:0]    id_dec_mem_size,
	output logic          id_dec_mem_unsigned,
	output logic          id_dec_is_branch,
	output logic [2:0]    id_dec_br_funct3,
	output logic          id_dec_is_jal,
	output logic          id_dec_is_jalr,
	output logic          id_dec_wb_pc4,
	output logic          id_dec_csr_wen,
	output logic [11:0]   id_dec_csr_addr,
	output logic [63:0]   id_dec_csr_wdata
);
	logic [63:0] id_rs1_val;
	logic [63:0] id_rs2_val;
	logic [63:0] id_imm_i;
	logic [63:0] id_imm_s;
	logic [63:0] id_imm_b;
	logic [63:0] id_imm_u;
	logic [63:0] id_imm_j;
	logic [6:0]  id_opcode;
	logic [2:0]  id_funct3;
	logic [6:0]  id_funct7;
	logic [4:0]  id_rd;
	logic [11:0] id_csr_addr;
	logic [63:0] id_csr_rdata;

	assign id_opcode = id_r.instr[6:0];
	assign id_funct3 = id_r.instr[14:12];
	assign id_funct7 = id_r.instr[31:25];
	assign id_rs1    = id_r.instr[19:15];
	assign id_rs2    = id_r.instr[24:20];
	assign id_rd     = id_r.instr[11:7];
	assign id_imm_i  = {{52{id_r.instr[31]}}, id_r.instr[31:20]};
	assign id_imm_s  = {{52{id_r.instr[31]}}, id_r.instr[31:25], id_r.instr[11:7]};
	assign id_imm_b  = {{51{id_r.instr[31]}}, id_r.instr[31], id_r.instr[7], id_r.instr[30:25], id_r.instr[11:8], 1'b0};
	assign id_imm_u  = {{32{id_r.instr[31]}}, id_r.instr[31:12], 12'd0};
	assign id_imm_j  = {{43{id_r.instr[31]}}, id_r.instr[31], id_r.instr[19:12], id_r.instr[20], id_r.instr[30:21], 1'b0};
	assign id_csr_addr = id_r.instr[31:20];

	// Operand usage is exposed so the top level can do hazard detection
	// without repeating decode knowledge.
	assign id_use_rs1 = (id_opcode == 7'b0010011) || (id_opcode == 7'b0110011) ||
	                    (id_opcode == 7'b0011011) || (id_opcode == 7'b0111011) ||
	                    (id_opcode == 7'b0000011) || (id_opcode == 7'b0100011) ||
	                    (id_opcode == 7'b1100011) || (id_opcode == 7'b1100111) ||
	                    ((id_opcode == 7'b1110011) && (id_funct3 == 3'b001 || id_funct3 == 3'b010 || id_funct3 == 3'b011));
	assign id_use_rs2 = (id_opcode == 7'b0110011) || (id_opcode == 7'b0111011) ||
	                    (id_opcode == 7'b0100011) || (id_opcode == 7'b1100011);

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
		unique case (id_csr_addr)
			CSR_MSTATUS:  id_csr_rdata = csr_mstatus;
			CSR_MTVEC:    id_csr_rdata = csr_mtvec;
			CSR_MIP:      id_csr_rdata = csr_mip;
			CSR_MIE:      id_csr_rdata = csr_mie;
			CSR_MSCRATCH: id_csr_rdata = csr_mscratch;
			CSR_MCAUSE:   id_csr_rdata = csr_mcause;
			CSR_MTVAL:    id_csr_rdata = csr_mtval;
			CSR_MEPC:     id_csr_rdata = csr_mepc;
			CSR_MCYCLE:   id_csr_rdata = csr_mcycle;
			CSR_MHARTID:  id_csr_rdata = csr_mhartid;
			CSR_SATP:     id_csr_rdata = csr_satp;
			default:      id_csr_rdata = 64'd0;
		endcase

		if (ex_r.valid && ex_r.csr_wen && (ex_r.csr_addr == id_csr_addr)) id_csr_rdata = ex_r.csr_wdata;
		else if (mem_r.valid && mem_r.csr_wen && (mem_r.csr_addr == id_csr_addr)) id_csr_rdata = mem_r.csr_wdata;
		else if (wb_r.valid && wb_r.csr_wen && (wb_r.csr_addr == id_csr_addr)) id_csr_rdata = wb_r.csr_wdata;
	end

	always_comb begin
		id_dec_valid        = id_r.valid;
		id_dec_trap         = 1'b0;
		id_dec_wen          = 1'b0;
		id_dec_is_word      = 1'b0;
		id_dec_alu_cmd      = ALU_ADD;
		id_dec_op1          = id_rs1_val;
		id_dec_op2          = id_rs2_val;
		id_dec_imm          = id_imm_i;
		id_dec_rs2_store    = id_rs2_val;
		id_dec_rd           = id_rd;
		id_dec_is_load      = 1'b0;
		id_dec_is_store     = 1'b0;
		id_dec_mem_size     = MSIZE8;
		id_dec_mem_unsigned = 1'b0;
		id_dec_is_branch    = 1'b0;
		id_dec_br_funct3    = 3'd0;
		id_dec_is_jal       = 1'b0;
		id_dec_is_jalr      = 1'b0;
		id_dec_wb_pc4       = 1'b0;
		id_dec_csr_wen      = 1'b0;
		id_dec_csr_addr     = id_csr_addr;
		id_dec_csr_wdata    = 64'd0;

		if (id_r.instr == TRAP_INSN) begin
			id_dec_trap = 1'b1;
		end else begin
			unique case (id_opcode)
				7'b0110111: begin
					id_dec_wen = 1'b1;
					id_dec_op1 = 64'd0;
					id_dec_op2 = id_imm_u;
				end
				7'b0010111: begin
					id_dec_wen = 1'b1;
					id_dec_op1 = id_r.pc;
					id_dec_op2 = id_imm_u;
				end
				7'b1101111: begin
					id_dec_wen = 1'b1;
					id_dec_is_jal = 1'b1;
					id_dec_wb_pc4 = 1'b1;
					id_dec_imm = id_imm_j;
				end
				7'b1100111: begin
					if (id_funct3 == 3'b000) begin
						id_dec_wen = 1'b1;
						id_dec_is_jalr = 1'b1;
						id_dec_wb_pc4 = 1'b1;
						id_dec_imm = id_imm_i;
					end
				end
				7'b1100011: begin
					id_dec_is_branch = 1'b1;
					id_dec_br_funct3 = id_funct3;
					id_dec_imm = id_imm_b;
				end
				7'b0000011: begin
					id_dec_wen = 1'b1;
					id_dec_is_load = 1'b1;
					id_dec_imm = id_imm_i;
					unique case (id_funct3)
						3'b000: begin id_dec_mem_size = MSIZE1; id_dec_mem_unsigned = 1'b0; end
						3'b001: begin id_dec_mem_size = MSIZE2; id_dec_mem_unsigned = 1'b0; end
						3'b010: begin id_dec_mem_size = MSIZE4; id_dec_mem_unsigned = 1'b0; end
						3'b011: begin id_dec_mem_size = MSIZE8; id_dec_mem_unsigned = 1'b0; end
						3'b100: begin id_dec_mem_size = MSIZE1; id_dec_mem_unsigned = 1'b1; end
						3'b101: begin id_dec_mem_size = MSIZE2; id_dec_mem_unsigned = 1'b1; end
						3'b110: begin id_dec_mem_size = MSIZE4; id_dec_mem_unsigned = 1'b1; end
						default: begin id_dec_valid = 1'b0; end
					endcase
				end
				7'b0100011: begin
					id_dec_is_store = 1'b1;
					id_dec_imm = id_imm_s;
					unique case (id_funct3)
						3'b000: id_dec_mem_size = MSIZE1;
						3'b001: id_dec_mem_size = MSIZE2;
						3'b010: id_dec_mem_size = MSIZE4;
						3'b011: id_dec_mem_size = MSIZE8;
						default: begin id_dec_valid = 1'b0; end
					endcase
				end
				7'b0010011: begin
					unique case (id_funct3)
						3'b000: begin id_dec_wen = 1'b1; id_dec_alu_cmd = ALU_ADD; id_dec_op2 = id_imm_i; end
						3'b001: begin id_dec_wen = 1'b1; id_dec_alu_cmd = ALU_SLL; id_dec_op2 = {58'd0, id_r.instr[25:20]}; end
						3'b010: begin id_dec_wen = 1'b1; id_dec_alu_cmd = ALU_SLT; id_dec_op2 = id_imm_i; end
						3'b011: begin id_dec_wen = 1'b1; id_dec_alu_cmd = ALU_SLTU; id_dec_op2 = id_imm_i; end
						3'b100: begin id_dec_wen = 1'b1; id_dec_alu_cmd = ALU_XOR; id_dec_op2 = id_imm_i; end
						3'b101: begin
							id_dec_wen = 1'b1;
							id_dec_alu_cmd = id_funct7[5] ? ALU_SRA : ALU_SRL;
							id_dec_op2 = {58'd0, id_r.instr[25:20]};
						end
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
							3'b001: begin id_dec_wen = 1'b1; id_dec_alu_cmd = ALU_SLL; end
							3'b010: begin id_dec_wen = 1'b1; id_dec_alu_cmd = ALU_SLT; end
							3'b011: begin id_dec_wen = 1'b1; id_dec_alu_cmd = ALU_SLTU; end
							3'b100: begin id_dec_wen = 1'b1; id_dec_alu_cmd = ALU_XOR; end
							3'b101: begin id_dec_wen = 1'b1; id_dec_alu_cmd = id_funct7[5] ? ALU_SRA : ALU_SRL; end
							3'b110: begin id_dec_wen = 1'b1; id_dec_alu_cmd = ALU_OR;  end
							3'b111: begin id_dec_wen = 1'b1; id_dec_alu_cmd = ALU_AND; end
							default: begin end
						endcase
					end
				end
				7'b0011011: begin
					unique case (id_funct3)
						3'b000: begin
							id_dec_wen = 1'b1;
							id_dec_is_word = 1'b1;
							id_dec_alu_cmd = ALU_ADD;
							id_dec_op2 = id_imm_i;
						end
						3'b001: begin
							id_dec_wen = 1'b1;
							id_dec_is_word = 1'b1;
							id_dec_alu_cmd = ALU_SLL;
							id_dec_op2 = {59'd0, id_r.instr[24:20]};
						end
						3'b101: begin
							id_dec_wen = 1'b1;
							id_dec_is_word = 1'b1;
							id_dec_alu_cmd = id_funct7[5] ? ALU_SRA : ALU_SRL;
							id_dec_op2 = {59'd0, id_r.instr[24:20]};
						end
						default: begin end
					endcase
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
					end else begin
						unique case (id_funct3)
							3'b000: begin id_dec_wen = 1'b1; id_dec_is_word = 1'b1; id_dec_alu_cmd = id_funct7[5] ? ALU_SUB : ALU_ADD; end
							3'b001: begin id_dec_wen = 1'b1; id_dec_is_word = 1'b1; id_dec_alu_cmd = ALU_SLL; end
							3'b101: begin id_dec_wen = 1'b1; id_dec_is_word = 1'b1; id_dec_alu_cmd = id_funct7[5] ? ALU_SRA : ALU_SRL; end
							default: begin end
						endcase
					end
				end
				7'b1110011: begin
					id_dec_wen = (id_rd != 0);
					id_dec_op1 = id_csr_rdata;
					id_dec_op2 = 64'd0;
					unique case (id_funct3)
						3'b001: begin
							id_dec_csr_wen = 1'b1;
							id_dec_csr_wdata = id_rs1_val;
						end
						3'b010: begin
							id_dec_csr_wen = (id_rs1 != 0);
							id_dec_csr_wdata = id_csr_rdata | id_rs1_val;
						end
						3'b011: begin
							id_dec_csr_wen = (id_rs1 != 0);
							id_dec_csr_wdata = id_csr_rdata & ~id_rs1_val;
						end
						3'b101: begin
							id_dec_csr_wen = 1'b1;
							id_dec_csr_wdata = {59'd0, id_rs1};
						end
						3'b110: begin
							id_dec_csr_wen = (id_rs1 != 0);
							id_dec_csr_wdata = id_csr_rdata | {59'd0, id_rs1};
						end
						3'b111: begin
							id_dec_csr_wen = (id_rs1 != 0);
							id_dec_csr_wdata = id_csr_rdata & ~{59'd0, id_rs1};
						end
						default: begin
							id_dec_valid = 1'b0;
							id_dec_wen = 1'b0;
						end
					endcase
					id_dec_csr_wdata = sanitize_csr_write(id_csr_addr, id_dec_csr_wdata);
				end
				default: begin end
			endcase
		end
	end
endmodule

`endif
