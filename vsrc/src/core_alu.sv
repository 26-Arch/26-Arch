`ifndef __CORE_ALU_SV
`define __CORE_ALU_SV

module core_alu import common::*;(
    input  alu_op_t     alu_op,
    input  logic [63:0] op_a,
    input  logic [63:0] op_b,
    output logic [63:0] result
);
    logic [31:0] result_32;

    always_comb begin
        result    = op_a;
        result_32 = 32'b0;

        case (alu_op)
            ALU_ADD:  result = op_a + op_b;
            ALU_SUB:  result = op_a - op_b;
            ALU_AND:  result = op_a & op_b;
            ALU_OR:   result = op_a | op_b;
            ALU_XOR:  result = op_a ^ op_b;
            ALU_ADDW: begin
                result_32 = op_a[31:0] + op_b[31:0];
                result    = {{32{result_32[31]}}, result_32};
            end
            ALU_SUBW: begin
                result_32 = op_a[31:0] - op_b[31:0];
                result    = {{32{result_32[31]}}, result_32};
            end
            default: ;
        endcase
    end
endmodule

`endif
