`ifndef __CORE_PKG_SV
`define __CORE_PKG_SV

package core_pkg;
	import common::*;

	localparam logic [31:0] TRAP_INSN = 32'h0005_006b;

	localparam logic [3:0] ALU_ADD  = 4'd0;
	localparam logic [3:0] ALU_SUB  = 4'd1;
	localparam logic [3:0] ALU_XOR  = 4'd2;
	localparam logic [3:0] ALU_OR   = 4'd3;
	localparam logic [3:0] ALU_AND  = 4'd4;
	localparam logic [3:0] ALU_SLL  = 4'd5;
	localparam logic [3:0] ALU_SRL  = 4'd6;
	localparam logic [3:0] ALU_SRA  = 4'd7;
	localparam logic [3:0] ALU_SLT  = 4'd8;
	localparam logic [3:0] ALU_SLTU = 4'd9;
	localparam logic [3:0] ALU_MUL  = 4'd10;
	localparam logic [3:0] ALU_DIV  = 4'd11;
	localparam logic [3:0] ALU_DIVU = 4'd12;
	localparam logic [3:0] ALU_REM  = 4'd13;
	localparam logic [3:0] ALU_REMU = 4'd14;

	localparam logic [11:0] CSR_SATP     = 12'h180;
	localparam logic [11:0] CSR_MSTATUS  = 12'h300;
	localparam logic [11:0] CSR_MIE      = 12'h304;
	localparam logic [11:0] CSR_MTVEC    = 12'h305;
	localparam logic [11:0] CSR_MSCRATCH = 12'h340;
	localparam logic [11:0] CSR_MEPC     = 12'h341;
	localparam logic [11:0] CSR_MCAUSE   = 12'h342;
	localparam logic [11:0] CSR_MTVAL    = 12'h343;
	localparam logic [11:0] CSR_MIP      = 12'h344;
	localparam logic [11:0] CSR_MCYCLE   = 12'hb00;
	localparam logic [11:0] CSR_MHARTID  = 12'hf14;

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
		logic [63:0] imm;
		logic [63:0] rs2_store;
		logic        is_load;
		logic        is_store;
		logic [2:0]  mem_size;
		logic        mem_unsigned;
		logic        is_branch;
		logic [2:0]  br_funct3;
		logic        is_jal;
		logic        is_jalr;
		logic        wb_pc4;
		logic        csr_wen;
		logic [11:0] csr_addr;
		logic [63:0] csr_wdata;
	} ex_reg_t;

	typedef struct packed {
		logic        valid;
		logic        trap;
		logic        wen;
		logic [4:0]  rd;
		logic [63:0] pc;
		logic [31:0] instr;
		logic [63:0] result;
		logic        is_load;
		logic        is_store;
		logic [2:0]  mem_size;
		logic        mem_unsigned;
		logic [63:0] mem_addr;
		logic [63:0] mem_wdata;
		logic [7:0]  mem_wstrb;
		logic        csr_wen;
		logic [11:0] csr_addr;
		logic [63:0] csr_wdata;
	} wb_like_reg_t;

	function automatic logic is_mdu_cmd(input logic [3:0] cmd);
		begin
			is_mdu_cmd = (cmd == ALU_MUL) || (cmd == ALU_DIV) || (cmd == ALU_DIVU) ||
			             (cmd == ALU_REM) || (cmd == ALU_REMU);
		end
	endfunction

	function automatic logic [63:0] sanitize_csr_write(input logic [11:0] addr, input logic [63:0] data);
		begin
			sanitize_csr_write = data;
			unique case (addr)
				CSR_MTVEC: sanitize_csr_write = {data[63:2], 1'b0, data[0]};
				CSR_MEPC : sanitize_csr_write = {data[63:1], 1'b0};
				default  : begin end
			endcase
		end
	endfunction
endpackage

`endif
