`ifndef __CORE_HAZARD_UNIT_SV
`define __CORE_HAZARD_UNIT_SV

module core_hazard_unit(
    input  logic       mem_read_ex,
    input  logic [4:0] rd_ex,
    input  logic [4:0] rs1_id,
    input  logic [4:0] rs2_id,
    output logic       load_use_hazard
);
    always_comb begin
        load_use_hazard = mem_read_ex && (rd_ex != 5'b0) &&
                          ((rd_ex == rs1_id) || (rd_ex == rs2_id));
    end
endmodule

`endif
