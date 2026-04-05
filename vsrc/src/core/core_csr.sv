`ifndef __CORE_CSR_SV
`define __CORE_CSR_SV

module core_csr
	import common::*;
	import core_pkg::*;(
	input  logic         clk,
	input  logic         reset,
	input  wb_like_reg_t wb_r,
	input  logic         trint,
	input  logic         swint,
	input  logic         exint,
	output logic [63:0]  csr_mstatus,
	output logic [63:0]  csr_mtvec,
	output logic [63:0]  csr_mip,
	output logic [63:0]  csr_mie,
	output logic [63:0]  csr_mscratch,
	output logic [63:0]  csr_mcause,
	output logic [63:0]  csr_mtval,
	output logic [63:0]  csr_mepc,
	output logic [63:0]  csr_mhartid,
	output logic [63:0]  csr_satp,
	output logic [63:0]  csr_mstatus_diff,
	output logic [63:0]  csr_mtvec_diff,
	output logic [63:0]  csr_mip_diff,
	output logic [63:0]  csr_mie_diff,
	output logic [63:0]  csr_mscratch_diff,
	output logic [63:0]  csr_mcause_diff,
	output logic [63:0]  csr_mtval_diff,
	output logic [63:0]  csr_mepc_diff,
	output logic [63:0]  csr_satp_diff
);
	logic [63:0] csr_mip_raw;
	logic [63:0] csr_mip_raw_diff;

	assign csr_mhartid = 64'd0;
	// External interrupt pins override the architecturally visible pending bits,
	// while software writes only affect the stored raw image.
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
			csr_mstatus  <= 64'd0;
			csr_mtvec    <= 64'd0;
			csr_mip_raw  <= 64'd0;
			csr_mie      <= 64'd0;
			csr_mscratch <= 64'd0;
			csr_mcause   <= 64'd0;
			csr_mtval    <= 64'd0;
			csr_mepc     <= 64'd0;
			csr_satp     <= 64'd0;
		end else if (wb_r.valid && wb_r.csr_wen) begin
			unique case (wb_r.csr_addr)
				CSR_MSTATUS:  csr_mstatus  <= wb_r.csr_wdata;
				CSR_MTVEC:    csr_mtvec    <= wb_r.csr_wdata;
				CSR_MIP:      csr_mip_raw  <= wb_r.csr_wdata;
				CSR_MIE:      csr_mie      <= wb_r.csr_wdata;
				CSR_MSCRATCH: csr_mscratch <= wb_r.csr_wdata;
				CSR_MCAUSE:   csr_mcause   <= wb_r.csr_wdata;
				CSR_MTVAL:    csr_mtval    <= wb_r.csr_wdata;
				CSR_MEPC:     csr_mepc     <= wb_r.csr_wdata;
				CSR_SATP:     csr_satp     <= wb_r.csr_wdata;
				default: begin end
			endcase
		end
	end

	always_comb begin
		csr_mstatus_diff  = csr_mstatus;
		csr_mtvec_diff    = csr_mtvec;
		csr_mip_raw_diff  = csr_mip_raw;
		csr_mie_diff      = csr_mie;
		csr_mscratch_diff = csr_mscratch;
		csr_mcause_diff   = csr_mcause;
		csr_mtval_diff    = csr_mtval;
		csr_mepc_diff     = csr_mepc;
		csr_satp_diff     = csr_satp;

		// Difftest needs the value that becomes architecturally visible this cycle,
		// so preview the in-flight CSR write before the next clock edge.
		if (wb_r.valid && wb_r.csr_wen) begin
			unique case (wb_r.csr_addr)
				CSR_MSTATUS:  csr_mstatus_diff  = wb_r.csr_wdata;
				CSR_MTVEC:    csr_mtvec_diff    = wb_r.csr_wdata;
				CSR_MIP:      csr_mip_raw_diff  = wb_r.csr_wdata;
				CSR_MIE:      csr_mie_diff      = wb_r.csr_wdata;
				CSR_MSCRATCH: csr_mscratch_diff = wb_r.csr_wdata;
				CSR_MCAUSE:   csr_mcause_diff   = wb_r.csr_wdata;
				CSR_MTVAL:    csr_mtval_diff    = wb_r.csr_wdata;
				CSR_MEPC:     csr_mepc_diff     = wb_r.csr_wdata;
				CSR_SATP:     csr_satp_diff     = wb_r.csr_wdata;
				default: begin end
			endcase
		end
	end
endmodule

`endif
