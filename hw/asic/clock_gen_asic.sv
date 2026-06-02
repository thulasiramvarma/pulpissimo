// ASIC Clock Generation — Foundry PLL Wrapper
// Replaces hw/clock_gen_generic.sv for physical implementation.
// Maintains identical port interface so soc_domain.sv needs no modification.
// Wraps two PLL instances:
//   PLL0: ref_clk → soc_clk  (target 200 MHz)
//   PLL1: ref_clk → per_clk  (target 100 MHz)
// slow_clk (32.768 kHz) taken directly from ref_clk via divider.
// APB interface configures PLL multiplication ratio.
// For tapeout: replace pll_model with foundry PLL hard macro (LEF + LIB).
// SPDX-License-Identifier: SHL-0.51

module clock_gen #(
  parameter int unsigned APB_ADDR_WIDTH = 32,
  parameter int unsigned APB_DATA_WIDTH = 32
)(
  // Reference clock input (from pad_ref_clk via IO cell)
  input  logic    ref_clk_i,
  // Active-low reset (synchronised externally)
  input  logic    rst_ni,
  // DFT bypass: when asserted all PLLs are bypassed and ref_clk drives all domains
  input  logic    dft_test_en_i,
  // Configuration clock for APB (same as ref_clk_i in most systems)
  input  logic    cfg_clk_i,
  // APB slave for PLL configuration (FLL register map compatible)
  input  logic [APB_ADDR_WIDTH-1:0] apb_paddr_i,
  input  logic [APB_DATA_WIDTH-1:0] apb_pwdata_i,
  input  logic                       apb_pwrite_i,
  input  logic                       apb_psel_i,
  input  logic                       apb_penable_i,
  output logic [APB_DATA_WIDTH-1:0]  apb_prdata_o,
  output logic                        apb_pready_o,
  output logic                        apb_pslverr_o,

  // Clock enable / bypass signals from soc_ctrl
  input  logic    soc_clk_en_i,
  input  logic    soc_clk_byp_en_i,
  input  logic    per_clk_en_i,
  input  logic    per_clk_byp_en_i,
  input  logic    slow_clk_en_i,
  input  logic    slow_clk_byp_en_i,

  // Generated clocks
  output logic    soc_clk_o,
  output logic    per_clk_o,
  output logic    slow_clk_o
);

  // -------------------------------------------------------------------------
  // PLL configuration registers
  // 0x000 SOC_PLL_CTRL  [15:0]=mult_ratio [17:16]=div_ratio [31]=bypass
  // 0x004 PER_PLL_CTRL  [15:0]=mult_ratio [17:16]=div_ratio [31]=bypass
  // 0x008 STATUS        [0]=soc_pll_lock [1]=per_pll_lock
  // -------------------------------------------------------------------------
  logic [31:0] soc_pll_ctrl_q, per_pll_ctrl_q;
  logic        soc_pll_lock, per_pll_lock;

  logic apb_access;
  assign apb_access    = apb_psel_i & apb_penable_i;
  assign apb_pready_o  = 1'b1;
  assign apb_pslverr_o = 1'b0;

  always_comb begin
    apb_prdata_o = '0;
    case (apb_paddr_i[3:2])
      2'h0: apb_prdata_o = soc_pll_ctrl_q;
      2'h1: apb_prdata_o = per_pll_ctrl_q;
      2'h2: apb_prdata_o = {30'b0, per_pll_lock, soc_pll_lock};
      default: ;
    endcase
  end

  always_ff @(posedge cfg_clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      soc_pll_ctrl_q <= 32'h0000_0140; // default: mult=320, div=1 → 200MHz @ 50MHz ref
      per_pll_ctrl_q <= 32'h0000_00A0; // default: mult=160, div=1 → 100MHz @ 50MHz ref
    end else if (apb_access && apb_pwrite_i) begin
      case (apb_paddr_i[3:2])
        2'h0: soc_pll_ctrl_q <= apb_pwdata_i;
        2'h1: per_pll_ctrl_q <= apb_pwdata_i;
        default: ;
      endcase
    end
  end

  // -------------------------------------------------------------------------
  // PLL model (behavioral — replace with foundry PLL macro for tapeout)
  // -------------------------------------------------------------------------
  logic soc_pll_clk, per_pll_clk;

  pll_model #(.DEFAULT_MULT(320)) i_soc_pll (
    .ref_clk_i  (ref_clk_i),
    .rst_ni     (rst_ni),
    .bypass_i   (soc_pll_ctrl_q[31] | dft_test_en_i),
    .mult_i     (soc_pll_ctrl_q[15:0]),
    .div_i      (soc_pll_ctrl_q[17:16]),
    .clk_o      (soc_pll_clk),
    .lock_o     (soc_pll_lock)
  );

  pll_model #(.DEFAULT_MULT(160)) i_per_pll (
    .ref_clk_i  (ref_clk_i),
    .rst_ni     (rst_ni),
    .bypass_i   (per_pll_ctrl_q[31] | dft_test_en_i),
    .mult_i     (per_pll_ctrl_q[15:0]),
    .div_i      (per_pll_ctrl_q[17:16]),
    .clk_o      (per_pll_clk),
    .lock_o     (per_pll_lock)
  );

  // Clock gating and bypass mux
  logic soc_clk_raw, per_clk_raw;
  assign soc_clk_raw = soc_clk_byp_en_i ? ref_clk_i : soc_pll_clk;
  assign per_clk_raw = per_clk_byp_en_i ? ref_clk_i : per_pll_clk;

  // Clock gates (tech_cells_generic tc_clk_gating for ASIC)
  tc_clk_gating i_soc_cg (.clk_i(soc_clk_raw), .en_i(soc_clk_en_i), .test_en_i(dft_test_en_i), .clk_o(soc_clk_o));
  tc_clk_gating i_per_cg (.clk_i(per_clk_raw), .en_i(per_clk_en_i), .test_en_i(dft_test_en_i), .clk_o(per_clk_o));

  // Slow clock: divide ref_clk by 1526 to get 32.768 kHz from 50 MHz ref
  logic [10:0] slow_div_q;
  logic slow_clk_raw;
  always_ff @(posedge ref_clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      slow_div_q   <= '0;
      slow_clk_raw <= 1'b0;
    end else if (slow_div_q == 11'd762) begin
      slow_div_q   <= '0;
      slow_clk_raw <= ~slow_clk_raw;
    end else begin
      slow_div_q <= slow_div_q + 1;
    end
  end

  tc_clk_gating i_slow_cg (.clk_i(slow_clk_raw), .en_i(slow_clk_en_i), .test_en_i(dft_test_en_i), .clk_o(slow_clk_o));

endmodule


// PLL behavioral model — replace with foundry PLL hard macro in ASIC flow
module pll_model #(
  parameter int unsigned DEFAULT_MULT = 320
)(
  input  logic        ref_clk_i,
  input  logic        rst_ni,
  input  logic        bypass_i,
  input  logic [15:0] mult_i,
  input  logic [1:0]  div_i,
  output logic        clk_o,
  output logic        lock_o
);
  // Behavioral: immediate lock, output = ref_clk (timing accurate only in sim)
  assign clk_o  = bypass_i ? ref_clk_i : ref_clk_i; // synthesis: hard macro
  assign lock_o = rst_ni;
endmodule
