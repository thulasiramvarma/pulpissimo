// Crypto Subsystem Top — aggregates all 6 crypto IPs
// APB slave window: 0x1A14_0000 – 0x1A18_0000 (256 KB)
// IP base addresses within this window:
//   0x1A14_0000  AES-256    (4 KB)
//   0x1A14_1000  SHA-256    (4 KB)
//   0x1A14_2000  ECC-521    (4 KB)
//   0x1A14_3000  PQC Kyber  (4 KB)
//   0x1A14_4000  TRNG       (4 KB)
//   0x1A14_5000  OTP_CTRL   (4 KB)
// Private key bus: OTP→AES (root_key), OTP→ECC (device_key) — internal only.
// TCDM master: AES and Kyber share port 7 via round-robin arbiter.
// SPDX-License-Identifier: SHL-0.51

`include "periph_bus_defines.sv"

module crypto_subsystem_top #(
  parameter int unsigned APB_ADDR_WIDTH = 32,
  parameter int unsigned APB_DATA_WIDTH = 32,
  parameter int unsigned TCDM_ADDR_WIDTH = 32,
  parameter int unsigned TCDM_DATA_WIDTH = 32
)(
  input  logic                       clk_i,
  input  logic                       rst_ni,

  // APB slave (from peripheral bus master[11])
  input  logic [APB_ADDR_WIDTH-1:0]  apb_paddr_i,
  input  logic [APB_DATA_WIDTH-1:0]  apb_pwdata_i,
  input  logic                       apb_pwrite_i,
  input  logic                       apb_psel_i,
  input  logic                       apb_penable_i,
  output logic [APB_DATA_WIDTH-1:0]  apb_prdata_o,
  output logic                       apb_pready_o,
  output logic                       apb_pslverr_o,

  // uDMA FIFO for SHA-256 data stream
  input  logic [31:0]                sha_udma_data_i,
  input  logic                       sha_udma_valid_i,
  output logic                       sha_udma_ready_o,
  output logic [31:0]                sha_udma_data_o,
  output logic                       sha_udma_valid_o,
  input  logic                       sha_udma_ready_i,

  // Shared TCDM master port 7 (AES + Kyber DMA, arbitrated)
  output logic                       tcdm_req_o,
  input  logic                       tcdm_gnt_i,
  output logic [TCDM_ADDR_WIDTH-1:0] tcdm_add_o,
  output logic                       tcdm_wen_o,
  output logic [TCDM_DATA_WIDTH-1:0] tcdm_wdata_o,
  output logic [3:0]                 tcdm_be_o,
  input  logic [TCDM_DATA_WIDTH-1:0] tcdm_r_rdata_i,
  input  logic                       tcdm_r_valid_i,

  // OTP analog supply sense (from pad_otp_vpp/vref in pulpissimo.sv)
  input  logic                       otp_vpp_sense_i,
  input  logic                       otp_vref_sense_i,

  // DFT (TRNG RO bypass)
  input  logic                       dft_test_en_i,

  // Interrupts to event unit (one per IP)
  output logic [5:0]                 irq_o
);

  // -------------------------------------------------------------------------
  // APB address decode (4 KB per IP, bits [14:12] select IP)
  // -------------------------------------------------------------------------
  logic [5:0] ip_sel; // one-hot IP select
  always_comb begin
    ip_sel = 6'b0;
    case (apb_paddr_i[14:12])
      3'd0: ip_sel = 6'b000001; // AES-256
      3'd1: ip_sel = 6'b000010; // SHA-256
      3'd2: ip_sel = 6'b000100; // ECC-521
      3'd3: ip_sel = 6'b001000; // Kyber
      3'd4: ip_sel = 6'b010000; // TRNG
      3'd5: ip_sel = 6'b100000; // OTP_CTRL
      default: ip_sel = 6'b0;
    endcase
  end

  // Mux APB read data + pready + pslverr from selected IP
  logic [31:0] prdata  [0:5];
  logic        pready  [0:5];
  logic        pslverr [0:5];

  always_comb begin
    apb_prdata_o  = '0;
    apb_pready_o  = 1'b1;
    apb_pslverr_o = 1'b0;
    for (int i = 0; i < 6; i++) begin
      if (ip_sel[i]) begin
        apb_prdata_o  = prdata[i];
        apb_pready_o  = pready[i];
        apb_pslverr_o = pslverr[i];
      end
    end
  end

  // Private key bus (OTP outputs, never reaches APB)
  logic [255:0] root_key, device_key;
  logic         root_key_valid, device_key_valid;

  // -------------------------------------------------------------------------
  // TCDM arbiter — round-robin between AES and Kyber
  // -------------------------------------------------------------------------
  logic        aes_tcdm_req,    kyber_tcdm_req;
  logic        aes_tcdm_gnt,    kyber_tcdm_gnt;
  logic [31:0] aes_tcdm_add,    kyber_tcdm_add;
  logic        aes_tcdm_wen,    kyber_tcdm_wen;
  logic [31:0] aes_tcdm_wdata,  kyber_tcdm_wdata;
  logic [3:0]  aes_tcdm_be,     kyber_tcdm_be;

  logic arb_sel_q; // 0=AES, 1=Kyber

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) arb_sel_q <= 1'b0;
    else if (tcdm_gnt_i) arb_sel_q <= ~arb_sel_q; // round-robin
  end

  always_comb begin
    tcdm_req_o      = 1'b0;
    tcdm_add_o      = '0;
    tcdm_wen_o      = 1'b1;
    tcdm_wdata_o    = '0;
    tcdm_be_o       = 4'hF;
    aes_tcdm_gnt    = 1'b0;
    kyber_tcdm_gnt  = 1'b0;

    if (!arb_sel_q && aes_tcdm_req) begin
      tcdm_req_o   = aes_tcdm_req;
      tcdm_add_o   = aes_tcdm_add;
      tcdm_wen_o   = aes_tcdm_wen;
      tcdm_wdata_o = aes_tcdm_wdata;
      tcdm_be_o    = aes_tcdm_be;
      aes_tcdm_gnt = tcdm_gnt_i;
    end else if (kyber_tcdm_req) begin
      tcdm_req_o     = kyber_tcdm_req;
      tcdm_add_o     = kyber_tcdm_add;
      tcdm_wen_o     = kyber_tcdm_wen;
      tcdm_wdata_o   = kyber_tcdm_wdata;
      tcdm_be_o      = kyber_tcdm_be;
      kyber_tcdm_gnt = tcdm_gnt_i;
    end else if (aes_tcdm_req) begin
      tcdm_req_o   = aes_tcdm_req;
      tcdm_add_o   = aes_tcdm_add;
      tcdm_wen_o   = aes_tcdm_wen;
      tcdm_wdata_o = aes_tcdm_wdata;
      tcdm_be_o    = aes_tcdm_be;
      aes_tcdm_gnt = tcdm_gnt_i;
    end
  end

  // -------------------------------------------------------------------------
  // IP instantiations
  // -------------------------------------------------------------------------

  // 0: AES-256
  aes256_top i_aes256 (
    .clk_i, .rst_ni,
    .apb_paddr_i, .apb_pwdata_i, .apb_pwrite_i,
    .apb_psel_i   (apb_psel_i   & ip_sel[0]),
    .apb_penable_i(apb_penable_i & ip_sel[0]),
    .apb_prdata_o (prdata[0]),
    .apb_pready_o (pready[0]),
    .apb_pslverr_o(pslverr[0]),
    .tcdm_req_o   (aes_tcdm_req),
    .tcdm_gnt_i   (aes_tcdm_gnt),
    .tcdm_add_o   (aes_tcdm_add),
    .tcdm_wen_o   (aes_tcdm_wen),
    .tcdm_wdata_o (aes_tcdm_wdata),
    .tcdm_be_o    (aes_tcdm_be),
    .tcdm_r_rdata_i, .tcdm_r_valid_i,
    .root_key_i   (root_key),
    .root_key_valid_i(root_key_valid),
    .irq_o        (irq_o[0])
  );

  // 1: SHA-256
  sha256_top i_sha256 (
    .clk_i, .rst_ni,
    .apb_paddr_i, .apb_pwdata_i, .apb_pwrite_i,
    .apb_psel_i   (apb_psel_i   & ip_sel[1]),
    .apb_penable_i(apb_penable_i & ip_sel[1]),
    .apb_prdata_o (prdata[1]),
    .apb_pready_o (pready[1]),
    .apb_pslverr_o(pslverr[1]),
    .udma_data_i  (sha_udma_data_i),
    .udma_valid_i (sha_udma_valid_i),
    .udma_ready_o (sha_udma_ready_o),
    .udma_data_o  (sha_udma_data_o),
    .udma_valid_o (sha_udma_valid_o),
    .udma_ready_i (sha_udma_ready_i),
    .irq_o        (irq_o[1])
  );

  // 2: ECC-521
  ecc521_top i_ecc521 (
    .clk_i, .rst_ni,
    .apb_paddr_i, .apb_pwdata_i, .apb_pwrite_i,
    .apb_psel_i   (apb_psel_i   & ip_sel[2]),
    .apb_penable_i(apb_penable_i & ip_sel[2]),
    .apb_prdata_o (prdata[2]),
    .apb_pready_o (pready[2]),
    .apb_pslverr_o(pslverr[2]),
    .device_key_i       (device_key),
    .device_key_valid_i (device_key_valid),
    .irq_o        (irq_o[2])
  );

  // 3: PQC Kyber-1024
  kyber_top i_kyber (
    .clk_i, .rst_ni,
    .apb_paddr_i, .apb_pwdata_i, .apb_pwrite_i,
    .apb_psel_i   (apb_psel_i   & ip_sel[3]),
    .apb_penable_i(apb_penable_i & ip_sel[3]),
    .apb_prdata_o (prdata[3]),
    .apb_pready_o (pready[3]),
    .apb_pslverr_o(pslverr[3]),
    .tcdm_req_o   (kyber_tcdm_req),
    .tcdm_gnt_i   (kyber_tcdm_gnt),
    .tcdm_add_o   (kyber_tcdm_add),
    .tcdm_wen_o   (kyber_tcdm_wen),
    .tcdm_wdata_o (kyber_tcdm_wdata),
    .tcdm_be_o    (kyber_tcdm_be),
    .tcdm_r_rdata_i, .tcdm_r_valid_i,
    .irq_o        (irq_o[3])
  );

  // 4: TRNG
  trng_top i_trng (
    .clk_i, .rst_ni,
    .apb_paddr_i, .apb_pwdata_i, .apb_pwrite_i,
    .apb_psel_i   (apb_psel_i   & ip_sel[4]),
    .apb_penable_i(apb_penable_i & ip_sel[4]),
    .apb_prdata_o (prdata[4]),
    .apb_pready_o (pready[4]),
    .apb_pslverr_o(pslverr[4]),
    .dft_test_en_i,
    .irq_o        (irq_o[4])
  );

  // 5: OTP Controller
  otp_ctrl_top i_otp_ctrl (
    .clk_i, .rst_ni,
    .apb_paddr_i, .apb_pwdata_i, .apb_pwrite_i,
    .apb_psel_i   (apb_psel_i   & ip_sel[5]),
    .apb_penable_i(apb_penable_i & ip_sel[5]),
    .apb_prdata_o (prdata[5]),
    .apb_pready_o (pready[5]),
    .apb_pslverr_o(pslverr[5]),
    .vpp_sense_i  (otp_vpp_sense_i),
    .vref_sense_i (otp_vref_sense_i),
    .root_key_o         (root_key),
    .root_key_valid_o   (root_key_valid),
    .device_key_o       (device_key),
    .device_key_valid_o (device_key_valid),
    .irq_o        (irq_o[5])
  );

endmodule
