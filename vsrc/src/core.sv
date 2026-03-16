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
	// ========== 1. Register File ==========
	logic [63:0] rf [31:1];
	logic [63:0] wb_data;
	logic        reg_write_wb;
	logic [4:0]  rd_wb;

	// RegFile write at WB stage (no write during reset)
	always_ff @(posedge clk) begin
		if (!reset && reg_write_wb && rd_wb != 5'b0)
			rf[rd_wb] <= wb_data;
	end

	// ========== 2. PC & IF ==========
	logic [63:0] pc, next_pc;
	logic        stall;

	assign next_pc = pc + 64'd4;
	// Phase 1: assume memory responds in 1 cycle; no stall to avoid combinational loop
	assign stall   = 1'b0;

	always_ff @(posedge clk) begin
		if (reset)
			pc <= PCINIT;
		else if (!stall)
			pc <= next_pc;
	end

	assign ireq.valid = ~stall;
	assign ireq.addr  = pc;

	// ========== 3. IF_ID Reg ==========
	logic [63:0] pc_id;
	logic [31:0] instr_id;
	logic        inst_valid_id;

	always_ff @(posedge clk) begin
		if (reset) begin
			pc_id        <= 64'b0;
			instr_id     <= 32'b0;
			inst_valid_id <= 1'b0;
		end else if (!stall) begin
			pc_id        <= pc;
			instr_id     <= iresp.data;
			inst_valid_id <= iresp.data_ok;
		end
	end

	// ========== 4. ID Decode ==========
	logic [6:0]  opcode_id;
	logic [4:0]  rd_id, rs1_id, rs2_id;
	logic [2:0]  funct3_id;
	logic [6:0]  funct7_id;
	logic [63:0] imm_id;
	logic [3:0]  alu_op_id;
	logic        mem_read_id, mem_write_id, reg_write_id;
	logic        wb_sel_id;

	assign opcode_id = instr_id[6:0];
	assign rd_id     = instr_id[11:7];
	assign rs1_id    = instr_id[19:15];
	assign rs2_id    = instr_id[24:20];
	assign funct3_id = instr_id[14:12];
	assign funct7_id = instr_id[31:25];

	// I-type imm
	always_comb begin
		imm_id = 64'b0;
		case (opcode_id)
			7'b0010011, 7'b0000011, 7'b1100111: begin  // I-type
				imm_id = {{52{instr_id[31]}}, instr_id[31:20]};
			end
			7'b0100011: begin  // S-type
				imm_id = {{52{instr_id[31]}}, instr_id[31:25], instr_id[11:7]};
			end
			7'b1100011: begin  // B-type
				imm_id = {{52{instr_id[31]}}, instr_id[7], instr_id[30:25], instr_id[11:8], 1'b0};
			end
			7'b0110111, 7'b0010111: begin  // U-type
				imm_id = {{32{instr_id[31]}}, instr_id[31:12], 12'b0};
			end
			7'b1101111: begin  // J-type
				imm_id = {{44{instr_id[31]}}, instr_id[19:12], instr_id[20], instr_id[30:21], 1'b0};
			end
			default: imm_id = 64'b0;
		endcase
	end

	// Control signals (Phase 1: placeholder defaults)
	assign alu_op_id    = 4'b0;
	assign mem_read_id  = 1'b0;
	assign mem_write_id = 1'b0;
	assign reg_write_id = 1'b0;
	assign wb_sel_id    = 1'b0;

	// RegFile read - fix: use rs1_id, rs2_id
	logic [63:0] rs1_data_id_r, rs2_data_id_r;
	always_comb begin
		rs1_data_id_r = (rs1_id == 5'b0) ? 64'b0 : rf[rs1_id];
		rs2_data_id_r = (rs2_id == 5'b0) ? 64'b0 : rf[rs2_id];
	end

	// ========== 5. ID_EX Reg ==========
	logic [63:0] pc_ex, rs1_data_ex, rs2_data_ex, imm_ex;
	logic [31:0] instr_ex;
	logic [4:0]  rd_ex, rs1_ex, rs2_ex;
	logic [2:0]  funct3_ex;
	logic [6:0]  funct7_ex;
	logic [3:0]  alu_op_ex;
	logic        inst_valid_ex, mem_read_ex, mem_write_ex, reg_write_ex;
	logic        wb_sel_ex;

	always_ff @(posedge clk) begin
		if (reset) begin
			pc_ex         <= 64'b0;
			instr_ex      <= 32'b0;
			inst_valid_ex <= 1'b0;
			rs1_data_ex   <= 64'b0;
			rs2_data_ex   <= 64'b0;
			rd_ex         <= 5'b0;
			rs1_ex        <= 5'b0;
			rs2_ex        <= 5'b0;
			imm_ex        <= 64'b0;
			funct3_ex     <= 3'b0;
			funct7_ex     <= 7'b0;
			alu_op_ex     <= 4'b0;
			mem_read_ex   <= 1'b0;
			mem_write_ex  <= 1'b0;
			reg_write_ex  <= 1'b0;
			wb_sel_ex     <= 1'b0;
		end else if (!stall) begin
			pc_ex         <= pc_id;
			instr_ex      <= instr_id;
			inst_valid_ex <= inst_valid_id;
			rs1_data_ex   <= rs1_data_id_r;
			rs2_data_ex   <= rs2_data_id_r;
			rd_ex         <= rd_id;
			rs1_ex        <= rs1_id;
			rs2_ex        <= rs2_id;
			imm_ex        <= imm_id;
			funct3_ex     <= funct3_id;
			funct7_ex     <= funct7_id;
			alu_op_ex     <= alu_op_id;
			mem_read_ex   <= mem_read_id;
			mem_write_ex  <= mem_write_id;
			reg_write_ex  <= reg_write_id;
			wb_sel_ex     <= wb_sel_id;
		end
	end

	// ========== 6. EX ALU ==========
	logic [63:0] alu_result_ex;

	always_comb begin
		alu_result_ex = rs1_data_ex;
		case (alu_op_ex)
			default: alu_result_ex = rs1_data_ex;
		endcase
	end

	// ========== 7. EX_MEM Reg ==========
	logic [63:0] pc_mem, alu_result_mem, rs2_data_mem;
	logic [31:0] instr_mem;
	logic [4:0]  rd_mem;
	logic        inst_valid_mem, mem_read_mem, mem_write_mem, reg_write_mem;
	logic        wb_sel_mem;

	always_ff @(posedge clk) begin
		if (reset) begin
			pc_mem         <= 64'b0;
			instr_mem      <= 32'b0;
			inst_valid_mem <= 1'b0;
			alu_result_mem <= 64'b0;
			rs2_data_mem   <= 64'b0;
			rd_mem         <= 5'b0;
			mem_read_mem   <= 1'b0;
			mem_write_mem  <= 1'b0;
			reg_write_mem  <= 1'b0;
			wb_sel_mem     <= 1'b0;
		end else if (!stall) begin
			pc_mem         <= pc_ex;
			instr_mem      <= instr_ex;
			inst_valid_mem <= inst_valid_ex;
			alu_result_mem <= alu_result_ex;
			rs2_data_mem   <= rs2_data_ex;
			rd_mem         <= rd_ex;
			mem_read_mem   <= mem_read_ex;
			mem_write_mem  <= mem_write_ex;
			reg_write_mem  <= reg_write_ex;
			wb_sel_mem     <= wb_sel_ex;
		end
	end

	// ========== 8. MEM ==========
	assign dreq.valid  = 1'b0;
	assign dreq.addr   = 64'b0;
	assign dreq.size   = MSIZE8;
	assign dreq.strobe = 8'b0;
	assign dreq.data   = 64'b0;

	// ========== 9. MEM_WB Reg ==========
	logic [63:0] pc_wb, alu_result_wb, mem_data_wb;
	logic [31:0] instr_wb;
	logic        inst_valid_wb, mem_read_wb;
	logic        wb_sel_wb;

	always_ff @(posedge clk) begin
		if (reset) begin
			pc_wb         <= 64'b0;
			instr_wb      <= 32'b0;
			inst_valid_wb <= 1'b0;
			alu_result_wb <= 64'b0;
			mem_data_wb   <= 64'b0;
			rd_wb         <= 5'b0;
			mem_read_wb   <= 1'b0;
			reg_write_wb  <= 1'b0;
			wb_sel_wb     <= 1'b0;
		end else if (!stall) begin
			pc_wb         <= pc_mem;
			instr_wb      <= instr_mem;
			inst_valid_wb <= inst_valid_mem;
			alu_result_wb <= alu_result_mem;
			mem_data_wb   <= dresp.data;
			rd_wb         <= rd_mem;
			mem_read_wb   <= mem_read_mem;
			reg_write_wb  <= reg_write_mem;
			wb_sel_wb     <= wb_sel_mem;
		end
	end

	// ========== 10. WB ==========
	assign wb_data = wb_sel_wb ? mem_data_wb : alu_result_wb;

	// ========== Difftest: gpr with bypass ==========
	logic [63:0] gpr_dt [32];
	always_comb begin
		for (int i = 0; i < 32; i++) begin
			if (i == 0)
				gpr_dt[i] = 64'b0;
			else if (reg_write_wb && rd_wb == i[4:0])
				gpr_dt[i] = wb_data;
			else
				gpr_dt[i] = rf[i];
		end
	end

`ifdef VERILATOR
	DifftestInstrCommit DifftestInstrCommit(
		.clock              (clk),
		.coreid             (8'b0),
		.index              (8'b0),
		.valid              (inst_valid_wb),
		.pc                 (pc_wb),
		.instr              (instr_wb),
		.skip               (1'b0),
		.isRVC              (1'b0),
		.scFailed           (1'b0),
		.wen                (reg_write_wb),
		.wdest              ({3'b0, rd_wb}),
		.wdata              (wb_data)
	);

	DifftestArchIntRegState DifftestArchIntRegState (
		.clock              (clk),
		.coreid             (8'b0),
		.gpr_0              (gpr_dt[0]),
		.gpr_1              (gpr_dt[1]),
		.gpr_2              (gpr_dt[2]),
		.gpr_3              (gpr_dt[3]),
		.gpr_4              (gpr_dt[4]),
		.gpr_5              (gpr_dt[5]),
		.gpr_6              (gpr_dt[6]),
		.gpr_7              (gpr_dt[7]),
		.gpr_8              (gpr_dt[8]),
		.gpr_9              (gpr_dt[9]),
		.gpr_10             (gpr_dt[10]),
		.gpr_11             (gpr_dt[11]),
		.gpr_12             (gpr_dt[12]),
		.gpr_13             (gpr_dt[13]),
		.gpr_14             (gpr_dt[14]),
		.gpr_15             (gpr_dt[15]),
		.gpr_16             (gpr_dt[16]),
		.gpr_17             (gpr_dt[17]),
		.gpr_18             (gpr_dt[18]),
		.gpr_19             (gpr_dt[19]),
		.gpr_20             (gpr_dt[20]),
		.gpr_21             (gpr_dt[21]),
		.gpr_22             (gpr_dt[22]),
		.gpr_23             (gpr_dt[23]),
		.gpr_24             (gpr_dt[24]),
		.gpr_25             (gpr_dt[25]),
		.gpr_26             (gpr_dt[26]),
		.gpr_27             (gpr_dt[27]),
		.gpr_28             (gpr_dt[28]),
		.gpr_29             (gpr_dt[29]),
		.gpr_30             (gpr_dt[30]),
		.gpr_31             (gpr_dt[31])
	);

    DifftestTrapEvent DifftestTrapEvent(
		.clock              (clk),
		.coreid             (0),
		.valid              (0),
		.code               (0),
		.pc                 (0),
		.cycleCnt           (0),
		.instrCnt           (0)
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