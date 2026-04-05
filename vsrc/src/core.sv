`ifndef __CORE_SV
`define __CORE_SV

`ifdef VERILATOR
`include "include/common.sv"
`endif

`include "src/core/core_pkg.sv"
`include "src/core/core_decode.sv"
`include "src/core/core_execute.sv"
`include "src/core/core_mdu.sv"

module core
	import common::*;
	import core_pkg::*;(
	input  logic       clk, reset,
	output ibus_req_t  ireq,
	input  ibus_resp_t iresp,
	output dbus_req_t  dreq,
	input  dbus_resp_t dresp,
	input  logic       trint, swint, exint
);
	// The top level keeps only long-lived pipeline state and control flow.
	// Decode / execute / MDU details live in dedicated source files now.
	id_reg_t      id_r;
	ex_reg_t      ex_r;
	wb_like_reg_t mem_r;
	wb_like_reg_t wb_r;

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
	logic        fetch_req_new_fire;
	logic        fetch_resp_fire;
	logic        fetch_pop_buf;
	logic        fetch_resp_to_id;
	logic        fetch_resp_to_buf;
	logic        fetch_can_consume;
	logic [63:0] fetch_req_addr;
	logic        fetch_redirect_pending;
	logic [63:0] fetch_redirect_pc;

	logic [4:0]  id_rs1;
	logic [4:0]  id_rs2;
	logic        id_use_rs1;
	logic        id_use_rs2;
	logic        id_dec_valid;
	logic        id_dec_trap;
	logic        id_dec_wen;
	logic        id_dec_is_word;
	logic [3:0]  id_dec_alu_cmd;
	logic [63:0] id_dec_op1;
	logic [63:0] id_dec_op2;
	logic [63:0] id_dec_imm;
	logic [63:0] id_dec_rs2_store;
	logic [4:0]  id_dec_rd;
	logic        id_dec_is_load;
	logic        id_dec_is_store;
	logic [2:0]  id_dec_mem_size;
	logic        id_dec_mem_unsigned;
	logic        id_dec_is_branch;
	logic [2:0]  id_dec_br_funct3;
	logic        id_dec_is_jal;
	logic        id_dec_is_jalr;
	logic        id_dec_wb_pc4;
	logic        id_dec_csr_wen;
	logic [11:0] id_dec_csr_addr;
	logic [63:0] id_dec_csr_wdata;

	logic [63:0] csr_mstatus;
	logic [63:0] csr_mtvec;
	logic [63:0] csr_mip_raw;
	logic [63:0] csr_mip;
	logic [63:0] csr_mie;
	logic [63:0] csr_mscratch;
	logic [63:0] csr_mcause;
	logic [63:0] csr_mtval;
	logic [63:0] csr_mepc;
	logic [63:0] csr_mhartid;
	logic [63:0] csr_satp;
	logic [63:0] csr_mstatus_diff;
	logic [63:0] csr_mtvec_diff;
	logic [63:0] csr_mip_raw_diff;
	logic [63:0] csr_mip_diff;
	logic [63:0] csr_mie_diff;
	logic [63:0] csr_mscratch_diff;
	logic [63:0] csr_mcause_diff;
	logic [63:0] csr_mtval_diff;
	logic [63:0] csr_mepc_diff;
	logic [63:0] csr_satp_diff;

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
	logic        stall_mem_busy;
	logic        stall_if_mem;
	logic        raw_hazard_ex;
	logic        raw_hazard_mem;
	logic        stall_pipe;
	logic        stall_front;
	logic        mem_result_ready;
	logic        mem_access_done;
	logic [63:0] mem_stage_result;
	logic [63:0] ex_result;
	logic [63:0] ex_mem_addr;
	logic        ex_flush_front;
	logic [63:0] ex_redirect_pc;
	logic        difftest_skip;
	logic [63:0] mem_store_data_shifted;
	logic [7:0]  mem_store_strobe;
	logic        mdu_out_valid;
	logic [63:0] mdu_out_result;

	integer i;

	assign ex_is_mdu = is_mdu_cmd(ex_r.alu_cmd);

	core_decode u_decode(
		.id_r(id_r),
		.ex_r(ex_r),
		.mem_r(mem_r),
		.wb_r(wb_r),
		.gpr(gpr),
		.csr_mstatus(csr_mstatus),
		.csr_mtvec(csr_mtvec),
		.csr_mip(csr_mip),
		.csr_mie(csr_mie),
		.csr_mscratch(csr_mscratch),
		.csr_mcause(csr_mcause),
		.csr_mtval(csr_mtval),
		.csr_mepc(csr_mepc),
		.csr_mcycle(cycle_cnt),
		.csr_mhartid(csr_mhartid),
		.csr_satp(csr_satp),
		.ex_forwardable(ex_forwardable),
		.ex_result(ex_result),
		.id_rs1(id_rs1),
		.id_rs2(id_rs2),
		.id_use_rs1(id_use_rs1),
		.id_use_rs2(id_use_rs2),
		.id_dec_valid(id_dec_valid),
		.id_dec_trap(id_dec_trap),
		.id_dec_wen(id_dec_wen),
		.id_dec_is_word(id_dec_is_word),
		.id_dec_alu_cmd(id_dec_alu_cmd),
		.id_dec_op1(id_dec_op1),
		.id_dec_op2(id_dec_op2),
		.id_dec_imm(id_dec_imm),
		.id_dec_rs2_store(id_dec_rs2_store),
		.id_dec_rd(id_dec_rd),
		.id_dec_is_load(id_dec_is_load),
		.id_dec_is_store(id_dec_is_store),
		.id_dec_mem_size(id_dec_mem_size),
		.id_dec_mem_unsigned(id_dec_mem_unsigned),
		.id_dec_is_branch(id_dec_is_branch),
		.id_dec_br_funct3(id_dec_br_funct3),
		.id_dec_is_jal(id_dec_is_jal),
		.id_dec_is_jalr(id_dec_is_jalr),
		.id_dec_wb_pc4(id_dec_wb_pc4),
		.id_dec_csr_wen(id_dec_csr_wen),
		.id_dec_csr_addr(id_dec_csr_addr),
		.id_dec_csr_wdata(id_dec_csr_wdata)
	);

	core_execute u_execute(
		.ex_r(ex_r),
		.mem_r(mem_r),
		.wb_r(wb_r),
		.dresp(dresp),
		.ex_is_mdu(ex_is_mdu),
		.mdu_out_valid(mdu_out_valid),
		.mdu_out_result(mdu_out_result),
		.ex_result_ready(ex_result_ready),
		.ex_forwardable(ex_forwardable),
		.stall_ex_busy(stall_ex_busy),
		.ex_result(ex_result),
		.ex_mem_addr(ex_mem_addr),
		.ex_flush_front(ex_flush_front),
		.ex_redirect_pc(ex_redirect_pc),
		.mem_access_done(mem_access_done),
		.mem_result_ready(mem_result_ready),
		.stall_mem_busy(stall_mem_busy),
		.stall_if_mem(stall_if_mem),
		.mem_stage_result(mem_stage_result),
		.mem_store_data_shifted(mem_store_data_shifted),
		.mem_store_strobe(mem_store_strobe),
		.difftest_skip(difftest_skip)
	);

	core_mdu u_mdu(
		.clk(clk),
		.reset(reset),
		.halted(halted),
		.trap_commit(trap_commit),
		.stall_pipe(stall_pipe),
		.ex_r(ex_r),
		.ex_is_mdu(ex_is_mdu),
		.mdu_out_valid(mdu_out_valid),
		.mdu_out_result(mdu_out_result)
	);

	assign raw_hazard_ex =
		id_r.valid && ex_r.valid && ex_r.wen && (ex_r.rd != 0) && !ex_result_ready &&
		((id_use_rs1 && (id_rs1 == ex_r.rd)) || (id_use_rs2 && (id_rs2 == ex_r.rd)));
	assign raw_hazard_mem =
		id_r.valid && mem_r.valid && mem_r.wen && (mem_r.rd != 0) && stall_if_mem &&
		((id_use_rs1 && (id_rs1 == mem_r.rd)) || (id_use_rs2 && (id_rs2 == mem_r.rd)));
	assign stall_pipe  = stall_ex_busy || stall_mem_busy || raw_hazard_ex || raw_hazard_mem;
	assign stall_front = stall_ex_busy || raw_hazard_ex || raw_hazard_mem || fetch_redirect_pending || stall_if_mem;

	assign fetch_can_consume   = (!halted) && (!trap_commit) && (!stall_front) && !ex_flush_front;
	assign fetch_pop_buf       = fetch_can_consume && fetch_buf_valid;
	assign fetch_resp_fire     = fetch_pending && iresp.data_ok;
	assign fetch_resp_to_id    = fetch_can_consume && (!fetch_buf_valid) && fetch_resp_fire;
	assign fetch_resp_to_buf   = fetch_resp_fire && !fetch_resp_to_id && !fetch_redirect_pending;
	assign fetch_fire          = fetch_pop_buf || fetch_resp_to_id;
	assign fetch_req_new_fire  = fetch_can_consume && (!fetch_pending);
	assign fetch_issue_fire    = fetch_req_new_fire;
	assign fetch_req_addr      = fetch_pending ? fetch_req_pc : fetch_pc;

	assign ireq.valid = !halted && !trap_commit && (fetch_pending || fetch_issue_fire) && !stall_if_mem;
	assign ireq.addr  = fetch_req_addr;

	assign dreq.valid  = mem_r.valid && (mem_r.is_load || mem_r.is_store) && !trap_commit;
	assign dreq.addr   = mem_r.mem_addr;
	assign dreq.size   = msize_t'(mem_r.mem_size);
	assign dreq.strobe = mem_r.mem_wstrb;
	assign dreq.data   = mem_r.mem_wdata;

	assign trap_commit = wb_r.valid && wb_r.trap;
	assign csr_mip = (csr_mip_raw & ~64'h0000_0000_0000_0888) |
	                 ({63'd0, exint} << 11) |
	                 ({63'd0, trint} << 7) |
	                 ({63'd0, swint} << 3);
	assign csr_mip_diff = (csr_mip_raw_diff & ~64'h0000_0000_0000_0888) |
	                      ({63'd0, exint} << 11) |
	                      ({63'd0, trint} << 7) |
	                      ({63'd0, swint} << 3);

	always_ff @(posedge clk) begin
		if (reset) begin
			fetch_pc <= PCINIT;
			fetch_pending <= 1'b0;
			fetch_req_pc <= 64'd0;
			fetch_redirect_pending <= 1'b0;
			fetch_redirect_pc <= 64'd0;
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
			csr_mstatus <= 64'd0;
			csr_mtvec <= 64'd0;
			csr_mip_raw <= 64'd0;
			csr_mie <= 64'd0;
			csr_mscratch <= 64'd0;
			csr_mcause <= 64'd0;
			csr_mtval <= 64'd0;
			csr_mepc <= 64'd0;
			csr_mhartid <= 64'd0;
			csr_satp <= 64'd0;
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

			if (wb_r.valid && wb_r.csr_wen) begin
				unique case (wb_r.csr_addr)
					CSR_MSTATUS:  csr_mstatus <= wb_r.csr_wdata;
					CSR_MTVEC:    csr_mtvec <= wb_r.csr_wdata;
					CSR_MIP:      csr_mip_raw <= wb_r.csr_wdata;
					CSR_MIE:      csr_mie <= wb_r.csr_wdata;
					CSR_MSCRATCH: csr_mscratch <= wb_r.csr_wdata;
					CSR_MCAUSE:   csr_mcause <= wb_r.csr_wdata;
					CSR_MTVAL:    csr_mtval <= wb_r.csr_wdata;
					CSR_MEPC:     csr_mepc <= wb_r.csr_wdata;
					CSR_MCYCLE:   cycle_cnt <= wb_r.csr_wdata;
					CSR_SATP:     csr_satp <= wb_r.csr_wdata;
					default: begin end
				endcase
			end

			if (trap_commit) begin
				halted <= 1'b1;
				fetch_pending <= 1'b0;
				fetch_redirect_pending <= 1'b0;
				fetch_buf_valid <= 1'b0;
				trap_valid_latched <= 1'b1;
				trap_code_latched <= gpr[10][2:0];
				trap_pc_latched <= wb_r.pc;
				trap_cycle_latched <= cycle_cnt;
				trap_instr_latched <= instr_cnt + 64'd1;
			end

			if (!halted && !trap_commit) begin
				// Front-end state is isolated here so redirects and request buffering
				// stay easy to audit when tracking instruction flow bugs.
				if (ex_flush_front) begin
					fetch_buf_valid <= 1'b0;
					if (fetch_pending && !fetch_resp_fire) begin
						fetch_redirect_pending <= 1'b1;
						fetch_redirect_pc <= ex_redirect_pc;
					end else begin
						fetch_pending <= 1'b0;
						fetch_req_pc <= 64'd0;
						fetch_redirect_pending <= 1'b0;
						fetch_pc <= ex_redirect_pc;
					end
				end else if (fetch_resp_fire) begin
					if (fetch_redirect_pending) begin
						fetch_pending <= 1'b0;
						fetch_req_pc <= 64'd0;
						fetch_redirect_pending <= 1'b0;
						fetch_pc <= fetch_redirect_pc;
					end else begin
						fetch_pending <= 1'b0;
						fetch_req_pc <= 64'd0;
						fetch_pc <= fetch_req_pc + 64'd4;
					end
				end else if (fetch_req_new_fire) begin
					fetch_pending <= 1'b1;
					fetch_req_pc <= fetch_pc;
				end

				if (!ex_flush_front) begin
					if (fetch_resp_to_buf) begin
						fetch_buf_valid <= 1'b1;
						fetch_buf_pc <= fetch_req_pc;
						fetch_buf_instr <= iresp.data;
					end else if (fetch_pop_buf) begin
						fetch_buf_valid <= 1'b0;
					end
				end

				if (stall_mem_busy) begin
					wb_r.valid <= 1'b0;
				end else begin
					wb_r.valid <= mem_r.valid;
					wb_r.trap  <= mem_r.trap;
					wb_r.wen   <= mem_r.wen;
					wb_r.rd    <= mem_r.rd;
					wb_r.pc    <= mem_r.pc;
					wb_r.instr <= mem_r.instr;
					wb_r.result<= mem_stage_result;
					wb_r.is_load <= mem_r.is_load;
					wb_r.is_store <= mem_r.is_store;
					wb_r.mem_addr <= mem_r.mem_addr;
					wb_r.csr_wen <= mem_r.csr_wen;
					wb_r.csr_addr <= mem_r.csr_addr;
					wb_r.csr_wdata <= mem_r.csr_wdata;
				end

				if (stall_mem_busy) begin
					// Hold MEM steady until the external bus returns valid data.
					mem_r <= mem_r;
				end else if (stall_ex_busy || raw_hazard_mem || fetch_redirect_pending) begin
					mem_r <= '0;
				end else begin
					mem_r.valid <= ex_r.valid;
					mem_r.trap  <= ex_r.trap;
					mem_r.wen   <= ex_r.wen;
					mem_r.rd    <= ex_r.rd;
					mem_r.pc    <= ex_r.pc;
					mem_r.instr <= ex_r.instr;
					mem_r.result<= ex_r.wb_pc4 ? (ex_r.pc + 64'd4) : ex_result;
					mem_r.is_load <= ex_r.is_load;
					mem_r.is_store <= ex_r.is_store;
					mem_r.mem_size <= ex_r.mem_size;
					mem_r.mem_unsigned <= ex_r.mem_unsigned;
					mem_r.mem_addr <= ex_mem_addr;
					mem_r.mem_wdata <= mem_store_data_shifted;
					mem_r.mem_wstrb <= ex_r.is_store ? mem_store_strobe : 8'd0;
					mem_r.csr_wen <= ex_r.csr_wen;
					mem_r.csr_addr <= ex_r.csr_addr;
					mem_r.csr_wdata <= ex_r.csr_wdata;

					// Flush / bubble policy for the front half of the pipeline is also
					// centralized here, because it depends on both control flow and hazards.
					if (ex_flush_front) begin
						ex_r <= '0;
						id_r.valid <= 1'b0;
						id_r.pc    <= 64'd0;
						id_r.instr <= 32'd0;
					end else if (raw_hazard_ex) begin
						ex_r <= '0;
					end else begin
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
						ex_r.imm     <= id_dec_imm;
						ex_r.rs2_store <= id_dec_rs2_store;
						ex_r.is_load <= id_dec_is_load;
						ex_r.is_store <= id_dec_is_store;
						ex_r.mem_size <= id_dec_mem_size;
						ex_r.mem_unsigned <= id_dec_mem_unsigned;
						ex_r.is_branch <= id_dec_is_branch;
						ex_r.br_funct3 <= id_dec_br_funct3;
						ex_r.is_jal <= id_dec_is_jal;
						ex_r.is_jalr <= id_dec_is_jalr;
						ex_r.wb_pc4 <= id_dec_wb_pc4;
						ex_r.csr_wen <= id_dec_csr_wen;
						ex_r.csr_addr <= id_dec_csr_addr;
						ex_r.csr_wdata <= id_dec_csr_wdata;

						if (fetch_pop_buf) begin
							id_r.valid <= 1'b1;
							id_r.pc    <= fetch_buf_pc;
							id_r.instr <= fetch_buf_instr;
						end else if (fetch_resp_to_id) begin
							id_r.valid <= 1'b1;
							id_r.pc    <= fetch_req_pc;
							id_r.instr <= iresp.data;
						end else begin
							id_r.valid <= 1'b0;
							id_r.pc    <= 64'd0;
							id_r.instr <= 32'd0;
						end
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

		csr_mstatus_diff = csr_mstatus;
		csr_mtvec_diff = csr_mtvec;
		csr_mip_raw_diff = csr_mip_raw;
		csr_mie_diff = csr_mie;
		csr_mscratch_diff = csr_mscratch;
		csr_mcause_diff = csr_mcause;
		csr_mtval_diff = csr_mtval;
		csr_mepc_diff = csr_mepc;
		csr_satp_diff = csr_satp;

		if (wb_r.valid && wb_r.csr_wen) begin
			unique case (wb_r.csr_addr)
				CSR_MSTATUS:  csr_mstatus_diff = wb_r.csr_wdata;
				CSR_MTVEC:    csr_mtvec_diff = wb_r.csr_wdata;
				CSR_MIP:      csr_mip_raw_diff = wb_r.csr_wdata;
				CSR_MIE:      csr_mie_diff = wb_r.csr_wdata;
				CSR_MSCRATCH: csr_mscratch_diff = wb_r.csr_wdata;
				CSR_MCAUSE:   csr_mcause_diff = wb_r.csr_wdata;
				CSR_MTVAL:    csr_mtval_diff = wb_r.csr_wdata;
				CSR_MEPC:     csr_mepc_diff = wb_r.csr_wdata;
				CSR_SATP:     csr_satp_diff = wb_r.csr_wdata;
				default: begin end
			endcase
		end
	end

`ifdef VERILATOR
	DifftestInstrCommit DifftestInstrCommit(
		.clock              (clk),
		.coreid             (0),
		.index              (0),
		.valid              (wb_r.valid),
		.pc                 (wb_r.pc),
		.instr              (wb_r.instr),
		.skip               (difftest_skip),
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
		.mstatus            (csr_mstatus_diff),
		.sstatus            (0),
		.mepc               (csr_mepc_diff),
		.sepc               (0),
		.mtval              (csr_mtval_diff),
		.stval              (0),
		.mtvec              (csr_mtvec_diff),
		.stvec              (0),
		.mcause             (csr_mcause_diff),
		.scause             (0),
		.satp               (csr_satp_diff),
		.mip                (csr_mip_diff),
		.mie                (csr_mie_diff),
		.mscratch           (csr_mscratch_diff),
		.sscratch           (0),
		.mideleg            (0),
		.medeleg            (0)
	);
`endif
endmodule

`endif
