// ASIC simplification: clock gate bypassed — clk_i passed directly to clk_o.
// en_i and scan_cg_en_i are ignored. Replace with foundry ICG cell when
// clock gating is required for power optimization.
module cv32e40p_clock_gate (
  input  logic clk_i,
  input  logic en_i,
  input  logic scan_cg_en_i,
  output logic clk_o
);
  assign clk_o = clk_i;
endmodule
