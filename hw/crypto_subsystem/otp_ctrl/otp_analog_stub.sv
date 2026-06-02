// OTP Analog Macro Behavioral Stub
// 8 kbit (256 × 32-bit) one-time programmable memory.
// This file is used for RTL simulation only.
// For ASIC: replace with foundry OTP hard macro (LEF + LIB + GDS + CDL).
// Analog supply pads VPP (programming) and VREF (read reference) are
// passed through from pulpissimo top to this macro directly — they bypass
// the padframe and must connect to dedicated bump/pad cells in the floorplan.
// set_false_path -from [get_cells *otp*] in constraints_crypto.sdc.
// SPDX-License-Identifier: SHL-0.51

module otp_analog_macro #(
  parameter int unsigned DEPTH = 256, // words
  parameter int unsigned WIDTH = 32   // bits per word
)(
  input  logic                 clk_i,
  input  logic                 rst_ni,

  // Control
  input  logic                 prog_en_i,   // 1 = programming mode (requires VPP)
  input  logic                 read_en_i,   // 1 = read mode

  // Address / data
  input  logic [$clog2(DEPTH)-1:0] addr_i,
  input  logic [WIDTH-1:0]     wdata_i,
  output logic [WIDTH-1:0]     rdata_o,
  output logic                 rdata_valid_o,

  // Analog supply sense (digital representation of pad state for simulation)
  input  logic                 vpp_sense_i,  // 1 when VPP pad powered
  input  logic                 vref_sense_i, // 1 when VREF pad stable

  // Status
  output logic                 prog_done_o,
  output logic                 prog_fail_o
);

  // Behavioral memory array
  logic [WIDTH-1:0] mem_q [0:DEPTH-1];
  logic [WIDTH-1:0] prog_mask_q [0:DEPTH-1]; // blown bits (irreversible)

  integer i;
  initial begin
    for (i = 0; i < DEPTH; i++) begin
      mem_q[i]       = {WIDTH{1'b1}}; // erased state = all 1s
      prog_mask_q[i] = {WIDTH{1'b0}};
    end
  end

  logic [1:0] prog_delay_q; // simulate programming pulse duration

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rdata_o       <= '0;
      rdata_valid_o <= 1'b0;
      prog_done_o   <= 1'b0;
      prog_fail_o   <= 1'b0;
      prog_delay_q  <= '0;
    end else begin
      rdata_valid_o <= 1'b0;
      prog_done_o   <= 1'b0;
      prog_fail_o   <= 1'b0;

      if (read_en_i && vref_sense_i) begin
        rdata_o       <= mem_q[addr_i];
        rdata_valid_o <= 1'b1;
      end

      if (prog_en_i && vpp_sense_i) begin
        // Only bits that are currently 1 can be blown to 0 (OTP semantics)
        if (prog_delay_q == 2'd3) begin
          mem_q[addr_i]       <= mem_q[addr_i] & ~wdata_i; // blow bits
          prog_mask_q[addr_i] <= prog_mask_q[addr_i] | wdata_i;
          prog_done_o         <= 1'b1;
          prog_delay_q        <= '0;
          // Fail if trying to re-program already blown bits
          prog_fail_o <= |(wdata_i & prog_mask_q[addr_i]);
        end else begin
          prog_delay_q <= prog_delay_q + 1;
        end
      end
    end
  end

endmodule
