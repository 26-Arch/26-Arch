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

`ifdef VERILATOR
	DifftestInstrCommit DifftestInstrCommit(
		.clock              (clk),
		.coreid             (0),
		.index              (0),
		.valid              (1'b1),
		.pc                 (PCINIT),
		.instr              (0),
		.skip               (0),
		.isRVC              (0),
		.scFailed           (0),
		.wen                (0),
		.wdest              (0),
		.wdata              (0)
	);

	DifftestArchIntRegState DifftestArchIntRegState (
		.clock              (clk),
		.coreid             (0),
		.gpr_0              (0),
		.gpr_1              (0),
		.gpr_2              (0),
		.gpr_3              (0),
		.gpr_4              (0),
		.gpr_5              (0),
		.gpr_6              (0),
		.gpr_7              (0),
		.gpr_8              (0),
		.gpr_9              (0),
		.gpr_10             (0),
		.gpr_11             (0),
		.gpr_12             (0),
		.gpr_13             (0),
		.gpr_14             (0),
		.gpr_15             (0),
		.gpr_16             (0),
		.gpr_17             (0),
		.gpr_18             (0),
		.gpr_19             (0),
		.gpr_20             (0),
		.gpr_21             (0),
		.gpr_22             (0),
		.gpr_23             (0),
		.gpr_24             (0),
		.gpr_25             (0),
		.gpr_26             (0),
		.gpr_27             (0),
		.gpr_28             (0),
		.gpr_29             (0),
		.gpr_30             (0),
		.gpr_31             (0)
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
		.sstatus            (0 /* mstatus & SSTATUS_MASK */),
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