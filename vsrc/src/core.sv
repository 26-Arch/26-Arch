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
	localparam logic [31:0] TRAP_INST = 32'h0005006b;

	// ========== 1. Register File ==========
	logic [63:0] wb_data;
	logic        reg_write_wb;
	logic [4:0]  rd_wb;
	logic [63:0] rs1_data_id_r, rs2_data_id_r;
	logic [31:0][63:0] rf_dbg;
	logic [63:0] cycle_cnt, instr_cnt;
	logic        trap_valid_wb, is_trap_wb;
	logic [7:0]  trap_code_wb;

	// ========== 2. PC & IF ==========
	logic [63:0] pc, next_pc;
	logic        stall, fetch_wait;

	assign next_pc = pc + 64'd4;

	always_ff @(posedge clk) begin
		if (reset)
			pc <= PCINIT;
		else if (!stall)
			pc <= next_pc;
	end

	// Keep request stable until data_ok, per Lab1 ibus requirement.
	assign ireq.valid = ~load_use_hazard;
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
	decode_out_t decode_id;
	logic [4:0]  rd_id, rs1_id, rs2_id;
	logic [2:0]  funct3_id;
	logic [6:0]  funct7_id;
	logic [63:0] imm_id;
	alu_op_t     alu_op_id;
	logic        alu_src_id;
	logic        mem_read_id, mem_write_id, reg_write_id;
	logic        wb_sel_id;

	core_decode decode(
		.instr      (instr_id),
		.decode_out (decode_id)
	);

	assign rd_id       = decode_id.rd;
	assign rs1_id      = decode_id.rs1;
	assign rs2_id      = decode_id.rs2;
	assign funct3_id   = decode_id.funct3;
	assign funct7_id   = decode_id.funct7;
	assign imm_id      = decode_id.imm;
	assign alu_op_id   = decode_id.alu_op;
	assign alu_src_id  = decode_id.alu_src;
	assign mem_read_id = decode_id.mem_read;
	assign mem_write_id = decode_id.mem_write;
	assign reg_write_id = decode_id.reg_write;
	assign wb_sel_id    = decode_id.wb_sel;

	core_regfile regfile(
		.clk      (clk),
		.reset    (reset),
		.wen      (reg_write_wb),
		.waddr    (rd_wb),
		.wdata    (wb_data),
		.raddr1   (rs1_id),
		.raddr2   (rs2_id),
		.rdata1   (rs1_data_id_r),
		.rdata2   (rs2_data_id_r),
		.regs_dbg (rf_dbg)
	);

	// ========== 5. ID_EX Reg ==========
	logic [63:0] pc_ex, rs1_data_ex, rs2_data_ex, imm_ex;
	logic [31:0] instr_ex;
	logic [4:0]  rd_ex, rs1_ex, rs2_ex;
	logic [2:0]  funct3_ex;
	logic [6:0]  funct7_ex;
	alu_op_t     alu_op_ex;
	logic        alu_src_ex;
	logic        inst_valid_ex, mem_read_ex, mem_write_ex, reg_write_ex;
	logic        wb_sel_ex;

	always_ff @(posedge clk) begin
		if (reset) begin
			// Bubble: clear all control signals
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
			alu_op_ex     <= ALU_ADD;
			alu_src_ex    <= 1'b0;
			mem_read_ex   <= 1'b0;
			mem_write_ex  <= 1'b0;
			reg_write_ex  <= 1'b0;
			wb_sel_ex     <= 1'b0;
		end else if (load_use_hazard) begin
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
			alu_op_ex     <= ALU_ADD;
			alu_src_ex    <= 1'b0;
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
			alu_src_ex    <= alu_src_id;
			mem_read_ex   <= mem_read_id;
			mem_write_ex  <= mem_write_id;
			reg_write_ex  <= reg_write_id;
			wb_sel_ex     <= wb_sel_id;
		end
	end

	// ========== Phase 3: Hazard Detection & Stall ==========
	logic load_use_hazard;

	core_hazard_unit hazard_unit(
		.mem_read_ex     (mem_read_ex),
		.rd_ex           (rd_ex),
		.rs1_id          (rs1_id),
		.rs2_id          (rs2_id),
		.load_use_hazard (load_use_hazard)
	);

	assign fetch_wait = ireq.valid && !iresp.data_ok;
	assign stall = load_use_hazard || fetch_wait;

	// ========== 6. EX ALU (Phase 3: Forwarding) ==========
	logic [63:0] alu_opA, alu_opB, rs2_forwarded;
	logic [63:0] alu_result_ex;

	core_forwarding_unit forwarding_unit(
		.rs1_ex         (rs1_ex),
		.rs2_ex         (rs2_ex),
		.rs1_data_ex    (rs1_data_ex),
		.rs2_data_ex    (rs2_data_ex),
		.reg_write_mem  (reg_write_mem),
		.rd_mem         (rd_mem),
		.alu_result_mem (alu_result_mem),
		.reg_write_wb   (reg_write_wb),
		.rd_wb          (rd_wb),
		.wb_data        (wb_data),
		.op_a_forwarded (alu_opA),
		.rs2_forwarded  (rs2_forwarded)
	);

	assign alu_opB = alu_src_ex ? imm_ex : rs2_forwarded;

	core_alu alu(
		.alu_op (alu_op_ex),
		.op_a   (alu_opA),
		.op_b   (alu_opB),
		.result (alu_result_ex)
	);

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
		end else if (!fetch_wait) begin
			// Phase 3: advance even when stall (let Load flow, avoid deadlock)
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
	logic        inst_valid_wb, mem_read_wb, commit_valid_wb;
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
		end else if (!fetch_wait) begin
			// Phase 3: advance even when stall (let Load flow, avoid deadlock)
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
	assign is_trap_wb = inst_valid_wb && (instr_wb == TRAP_INST);
	assign commit_valid_wb = inst_valid_wb && !fetch_wait;
	assign trap_valid_wb = is_trap_wb && !fetch_wait;
	assign trap_code_wb = rf_dbg[10][7:0];

	always_ff @(posedge clk) begin
		if (reset) begin
			cycle_cnt <= 64'b0;
			instr_cnt <= 64'b0;
		end else begin
			cycle_cnt <= cycle_cnt + 64'd1;
			if (commit_valid_wb && !is_trap_wb)
				instr_cnt <= instr_cnt + 64'd1;
		end
	end

	// ========== Difftest: gpr with bypass ==========
	logic [63:0] gpr_dt [32];
	always_comb begin
		for (int i = 0; i < 32; i++) begin
			if (i == 0)
				gpr_dt[i] = 64'b0;
			else if (reg_write_wb && rd_wb == i[4:0])
				gpr_dt[i] = wb_data;
			else
				gpr_dt[i] = rf_dbg[i];
		end
	end

`ifdef VERILATOR
	DifftestInstrCommit DifftestInstrCommit(
		.clock              (clk),
		.coreid             (8'b0),
		.index              (8'b0),
		.valid              (commit_valid_wb),
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
		.valid              (trap_valid_wb),
		.code               (trap_code_wb[2:0]),
		.pc                 (pc_wb),
		.cycleCnt           (cycle_cnt),
		.instrCnt           (instr_cnt)
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