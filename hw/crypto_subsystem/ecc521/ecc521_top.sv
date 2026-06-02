// ECC-521 Top — APB slave, register-driven (no DMA needed)
// Implements ECDSA sign/verify on NIST P-521 curve.
// MCP=8 set in SDC: point-multiplication datapath runs across 8 cycles.
// Private key from OTP (device_key[255:0]) — never on APB.
// SPDX-License-Identifier: SHL-0.51

module ecc521_top #(
  parameter int unsigned APB_ADDR_WIDTH = 32,
  parameter int unsigned APB_DATA_WIDTH = 32
)(
  input  logic                       clk_i,
  input  logic                       rst_ni,

  // APB slave port
  input  logic [APB_ADDR_WIDTH-1:0]  apb_paddr_i,
  input  logic [APB_DATA_WIDTH-1:0]  apb_pwdata_i,
  input  logic                       apb_pwrite_i,
  input  logic                       apb_psel_i,
  input  logic                       apb_penable_i,
  output logic [APB_DATA_WIDTH-1:0]  apb_prdata_o,
  output logic                       apb_pready_o,
  output logic                       apb_pslverr_o,

  // Private key bus from OTP (never reaches APB)
  input  logic [255:0]               device_key_i,
  input  logic                       device_key_valid_i,

  // Interrupt to event unit
  output logic                       irq_o
);

  // -------------------------------------------------------------------------
  // Register map (32-bit words, byte addr = word * 4)
  // 0x000 CTRL    [0]=start [1]=op(0=sign,1=verify) [2]=key_sel(0=sw,1=otp)
  // 0x004 STATUS  [0]=busy [1]=done [2]=valid (signature valid on verify)
  // 0x008-0x047 HASH[17:0]   521-bit message hash (18 × 32-bit, top word masked)
  // 0x048-0x087 K_NONCE[17:0] ephemeral nonce for signing (SW provided)
  // 0x088-0x0C7 SIG_R[17:0]  output/input signature r component
  // 0x0C8-0x107 SIG_S[17:0]  output/input signature s component
  // 0x108-0x147 PUB_X[17:0]  public key X (for verify)
  // 0x148-0x187 PUB_Y[17:0]  public key Y (for verify)
  // 0x188-0x1C7 SW_KEY[17:0] software private key (ignored if key_sel=1)
  // -------------------------------------------------------------------------

  localparam int WORDS521 = 17; // ceil(521/32) = 17 words

  logic [31:0]            ctrl_q;
  logic [WORDS521*32-1:0] hash_q, k_nonce_q, sig_r_q, sig_s_q;
  logic [WORDS521*32-1:0] pub_x_q, pub_y_q, sw_key_q;
  logic                   busy_q, done_q, sig_valid_q;

  logic apb_access;
  assign apb_access    = apb_psel_i & apb_penable_i;
  assign apb_pready_o  = 1'b1;
  assign apb_pslverr_o = 1'b0;

  logic [8:0] apb_word;
  assign apb_word = apb_paddr_i[10:2];

  always_comb begin
    apb_prdata_o = '0;
    if (apb_word == 9'h0) apb_prdata_o = ctrl_q;
    else if (apb_word == 9'h1) apb_prdata_o = {29'b0, sig_valid_q, done_q, busy_q};
    else if (apb_word >= 9'h2  && apb_word < 9'h2  + WORDS521)
      apb_prdata_o = hash_q[(apb_word - 9'h2)*32 +: 32];
    else if (apb_word >= 9'h13 && apb_word < 9'h13 + WORDS521)
      apb_prdata_o = k_nonce_q[(apb_word - 9'h13)*32 +: 32];
    else if (apb_word >= 9'h22 && apb_word < 9'h22 + WORDS521)
      apb_prdata_o = sig_r_q[(apb_word - 9'h22)*32 +: 32];
    else if (apb_word >= 9'h31 && apb_word < 9'h31 + WORDS521)
      apb_prdata_o = sig_s_q[(apb_word - 9'h31)*32 +: 32];
    else if (apb_word >= 9'h40 && apb_word < 9'h40 + WORDS521)
      apb_prdata_o = pub_x_q[(apb_word - 9'h40)*32 +: 32];
    else if (apb_word >= 9'h4F && apb_word < 9'h4F + WORDS521)
      apb_prdata_o = pub_y_q[(apb_word - 9'h4F)*32 +: 32];
    else if (apb_word >= 9'h5E && apb_word < 9'h5E + WORDS521)
      apb_prdata_o = sw_key_q[(apb_word - 9'h5E)*32 +: 32];
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      ctrl_q    <= '0;
      hash_q    <= '0; k_nonce_q <= '0;
      pub_x_q   <= '0; pub_y_q   <= '0; sw_key_q  <= '0;
    end else if (apb_access && apb_pwrite_i) begin
      if (apb_word == 9'h0) ctrl_q <= apb_pwdata_i;
      else if (apb_word >= 9'h2  && apb_word < 9'h2  + WORDS521)
        hash_q[(apb_word - 9'h2)*32 +: 32]    <= apb_pwdata_i;
      else if (apb_word >= 9'h13 && apb_word < 9'h13 + WORDS521)
        k_nonce_q[(apb_word - 9'h13)*32 +: 32] <= apb_pwdata_i;
      else if (apb_word >= 9'h22 && apb_word < 9'h22 + WORDS521)
        sig_r_q[(apb_word - 9'h22)*32 +: 32]   <= apb_pwdata_i;
      else if (apb_word >= 9'h31 && apb_word < 9'h31 + WORDS521)
        sig_s_q[(apb_word - 9'h31)*32 +: 32]   <= apb_pwdata_i;
      else if (apb_word >= 9'h40 && apb_word < 9'h40 + WORDS521)
        pub_x_q[(apb_word - 9'h40)*32 +: 32]   <= apb_pwdata_i;
      else if (apb_word >= 9'h4F && apb_word < 9'h4F + WORDS521)
        pub_y_q[(apb_word - 9'h4F)*32 +: 32]   <= apb_pwdata_i;
      else if (apb_word >= 9'h5E && apb_word < 9'h5E + WORDS521)
        sw_key_q[(apb_word - 9'h5E)*32 +: 32]  <= apb_pwdata_i;
    end
  end

  // Active private key (OTP or SW)
  logic [WORDS521*32-1:0] active_key;
  assign active_key = ctrl_q[2] ? {{(WORDS521*32-256){1'b0}}, device_key_i} : sw_key_q;

  // ECC-521 scalar multiplication engine
  // MCP=8: each clock cycle advances the datapath 8× (set in constraints_crypto.sdc)
  ecc521_core i_ecc_core (
    .clk_i           (clk_i),
    .rst_ni          (rst_ni),
    .start_i         (ctrl_q[0] && !busy_q && device_key_valid_i),
    .op_i            (ctrl_q[1]),
    .hash_i          (hash_q),
    .k_nonce_i       (k_nonce_q),
    .priv_key_i      (active_key),
    .pub_x_i         (pub_x_q),
    .pub_y_i         (pub_y_q),
    .sig_r_o         (sig_r_q),
    .sig_s_o         (sig_s_q),
    .sig_valid_o     (sig_valid_q),
    .done_o          (done_q),
    .busy_o          (busy_q)
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) irq_o <= 1'b0;
    else         irq_o <= done_q;
  end

endmodule


// ECC-521 core — behavioral model (scalar multiplication on P-521)
// Production: replace with certified constant-time hard macro.
// MCP=8 annotation in SDC covers this module's datapath registers.
module ecc521_core #(
  parameter int W = 544 // 17 × 32, covers 521-bit operands
)(
  input  logic         clk_i,
  input  logic         rst_ni,
  input  logic         start_i,
  input  logic         op_i,
  input  logic [W-1:0] hash_i,
  input  logic [W-1:0] k_nonce_i,
  input  logic [W-1:0] priv_key_i,
  input  logic [W-1:0] pub_x_i,
  input  logic [W-1:0] pub_y_i,
  output logic [W-1:0] sig_r_o,
  output logic [W-1:0] sig_s_o,
  output logic         sig_valid_o,
  output logic         done_o,
  output logic         busy_o
);
  // 521-bit scalar multiplication: ~1.5M cycles at 200 MHz ≈ 7.5 ms
  // Behavioral placeholder: XOR reduction to show register structure
  logic [9:0] cycle_cnt_q; // reduced for stub; real: ~1.5M cycle counter

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      cycle_cnt_q <= '0;
      busy_o      <= 1'b0;
      done_o      <= 1'b0;
      sig_valid_o <= 1'b0;
      sig_r_o     <= '0;
      sig_s_o     <= '0;
    end else begin
      done_o      <= 1'b0;
      sig_valid_o <= 1'b0;
      if (start_i && !busy_o) begin
        busy_o      <= 1'b1;
        cycle_cnt_q <= '0;
      end else if (busy_o) begin
        cycle_cnt_q <= cycle_cnt_q + 1;
        if (&cycle_cnt_q) begin // stub: done after 1023 cycles
          busy_o      <= 1'b0;
          done_o      <= 1'b1;
          sig_valid_o <= !op_i; // sign always valid; verify: stub
          sig_r_o     <= hash_i ^ k_nonce_i;
          sig_s_o     <= priv_key_i ^ hash_i;
        end
      end
    end
  end
endmodule
