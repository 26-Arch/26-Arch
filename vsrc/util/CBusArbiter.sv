`ifndef __CBUSARBITER_SV
`define __CBUSARBITER_SV

`ifdef VERILATOR
`include "include/common.sv"
`else

`endif
module CBusArbiter
	import common::*;#(
    parameter int NUM_INPUTS = 2,  // NOTE: NUM_INPUTS >= 1

    localparam int MAX_INDEX = NUM_INPUTS - 1
) (
    input logic clk, reset,

    input  cbus_req_t  [MAX_INDEX:0] ireqs,
    output cbus_resp_t [MAX_INDEX:0] iresps,
    output cbus_req_t  oreq,
    input  cbus_resp_t oresp
);
    int select;
    int lock_select;
    logic any_valid;
    cbus_req_t selected_req;
    cbus_req_t lock_req;
    logic lock_valid;

    assign selected_req = any_valid ? ireqs[select] : '0;
    assign oreq = lock_valid ? lock_req : selected_req;

    // select a preferred request
    always_comb begin
        select = 0;
        any_valid = 1'b0;

        for (int i = 0; i < NUM_INPUTS; i++) begin
            if (!any_valid && (ireqs[i].valid === 1'b1)) begin
                select = i;
                any_valid = 1'b1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            lock_valid  <= 1'b0;
            lock_req    <= '0;
            lock_select <= 0;
        end else begin
            if (lock_valid) begin
                if (oresp.ready && oresp.last) begin
                    lock_valid <= 1'b0;
                end
            end else if (any_valid && !(oresp.ready && oresp.last)) begin
                // Hold one accepted request stable until RAM reports completion.
                lock_valid  <= 1'b1;
                lock_req    <= selected_req;
                lock_select <= select;
            end
        end
    end

    // feedback to selected request
    always_comb begin
        iresps = '0;

        if (lock_valid) begin
            iresps[lock_select] = oresp;
        end else if (any_valid) begin
            iresps[select] = oresp;
        end
    end
endmodule



`endif
