// PQC Kyber-1024 Top — APB slave + TCDM master + NTT SRAM
// Implements CRYSTALS-Kyber-1024 (NIST PQC finalist) key encapsulation.
// NTT butterfly uses dedicated 2KB SRAM (256×64-bit, 8 coefficients/word).
// MCP=4 set in SDC for NTT datapath (ntt_* registers).
// SPDX-License-Identifier: SHL-0.51

module kyber_top #(
  parameter int unsigned APB_ADDR_WIDTH = 32,
  parameter int unsigned APB_DATA_WIDTH = 32,
  parameter int unsigned TCDM_ADDR_WIDTH = 32,
  parameter int unsigned TCDM_DATA_WIDTH = 32
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

  // TCDM master port (lint protocol — DMA for plaintext/ciphertext)
  output logic                       tcdm_req_o,
  input  logic                       tcdm_gnt_i,
  output logic [TCDM_ADDR_WIDTH-1:0] tcdm_add_o,
  output logic                       tcdm_wen_o,
  output logic [TCDM_DATA_WIDTH-1:0] tcdm_wdata_o,
  output logic [3:0]                 tcdm_be_o,
  input  logic [TCDM_DATA_WIDTH-1:0] tcdm_r_rdata_i,
  input  logic                       tcdm_r_valid_i,

  // Interrupt to event unit
  output logic                       irq_o
);

  // -------------------------------------------------------------------------
  // Register map
  // 0x00 CTRL    [1:0]=op (00=keygen, 01=encap, 10=decap) [2]=start
  // 0x04 STATUS  [0]=busy [1]=done
  // 0x08 SRC_ADDR  TCDM source (input polynomial / ciphertext)
  // 0x0C DST_ADDR  TCDM destination (output key / ciphertext)
  // 0x10 LENGTH    byte length of DMA transfer
  // -------------------------------------------------------------------------

  logic [31:0] ctrl_q, src_addr_q, dst_addr_q, length_q;
  logic        busy_q, done_q;

  logic apb_access;
  assign apb_access    = apb_psel_i & apb_penable_i;
  assign apb_pready_o  = 1'b1;
  assign apb_pslverr_o = 1'b0;

  logic [2:0] apb_word;
  assign apb_word = apb_paddr_i[4:2];

  always_comb begin
    apb_prdata_o = '0;
    case (apb_word)
      3'h0: apb_prdata_o = ctrl_q;
      3'h1: apb_prdata_o = {30'b0, done_q, busy_q};
      3'h2: apb_prdata_o = src_addr_q;
      3'h3: apb_prdata_o = dst_addr_q;
      3'h4: apb_prdata_o = length_q;
      default: ;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      ctrl_q     <= '0;
      src_addr_q <= '0;
      dst_addr_q <= '0;
      length_q   <= '0;
    end else if (apb_access && apb_pwrite_i) begin
      case (apb_word)
        3'h0: ctrl_q     <= apb_pwdata_i;
        3'h2: src_addr_q <= apb_pwdata_i;
        3'h3: dst_addr_q <= apb_pwdata_i;
        3'h4: length_q   <= apb_pwdata_i;
        default: ;
      endcase
    end
  end

  // -------------------------------------------------------------------------
  // NTT SRAM — 2KB, 256×64-bit (8 Kyber coefficients × 12-bit packed per word)
  // In RTL simulation: behavioral SRAM model
  // In ASIC PnR: replaced with foundry SRAM macro via sram_wrapper
  // -------------------------------------------------------------------------
  logic [7:0]  ntt_sram_addr;
  logic [63:0] ntt_sram_wdata, ntt_sram_rdata;
  logic        ntt_sram_we;

  sram_2kx8 i_ntt_sram (
    .clk_i   (clk_i),
    .addr_i  (ntt_sram_addr),
    .wdata_i (ntt_sram_wdata),
    .we_i    (ntt_sram_we),
    .rdata_o (ntt_sram_rdata)
  );

  // Kyber NTT engine (MCP=4)
  kyber_ntt_engine i_ntt (
    .clk_i        (clk_i),
    .rst_ni       (rst_ni),
    .start_i      (ctrl_q[2] && !busy_q),
    .op_i         (ctrl_q[1:0]),
    .sram_addr_o  (ntt_sram_addr),
    .sram_wdata_o (ntt_sram_wdata),
    .sram_we_o    (ntt_sram_we),
    .sram_rdata_i (ntt_sram_rdata),
    .tcdm_req_o,
    .tcdm_gnt_i,
    .tcdm_add_o,
    .tcdm_wen_o,
    .tcdm_wdata_o,
    .tcdm_be_o,
    .tcdm_r_rdata_i,
    .tcdm_r_valid_i,
    .src_addr_i   (src_addr_q),
    .dst_addr_i   (dst_addr_q),
    .length_i     (length_q),
    .busy_o       (busy_q),
    .done_o       (done_q)
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) irq_o <= 1'b0;
    else         irq_o <= done_q;
  end

endmodule


// 2KB SRAM behavioral model — replaced with foundry macro during PnR
module sram_2kx8 (
  input  logic        clk_i,
  input  logic [7:0]  addr_i,
  input  logic [63:0] wdata_i,
  input  logic        we_i,
  output logic [63:0] rdata_o
);
  logic [63:0] mem [0:255];
  always_ff @(posedge clk_i) begin
    if (we_i) mem[addr_i] <= wdata_i;
    rdata_o <= mem[addr_i];
  end
endmodule


// Kyber-1024 NTT engine — behavioral stub
// MCP=4: NTT butterfly registers are multicycle (set in constraints_crypto.sdc)
module kyber_ntt_engine (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        start_i,
  input  logic [1:0]  op_i,
  output logic [7:0]  sram_addr_o,
  output logic [63:0] sram_wdata_o,
  output logic        sram_we_o,
  input  logic [63:0] sram_rdata_i,
  output logic        tcdm_req_o,
  input  logic        tcdm_gnt_i,
  output logic [31:0] tcdm_add_o,
  output logic        tcdm_wen_o,
  output logic [31:0] tcdm_wdata_o,
  output logic [3:0]  tcdm_be_o,
  input  logic [31:0] tcdm_r_rdata_i,
  input  logic        tcdm_r_valid_i,
  input  logic [31:0] src_addr_i,
  input  logic [31:0] dst_addr_i,
  input  logic [31:0] length_i,
  output logic        busy_o,
  output logic        done_o
);
  // NTT butterfly: 256 coefficients, 8 stages = 256*8 = 2048 butterfly ops
  // At MCP=4 (4 cycles per butterfly): ~8192 cycles per NTT
  logic [12:0] cnt_q;

  assign tcdm_req_o   = 1'b0;
  assign tcdm_add_o   = src_addr_i;
  assign tcdm_wen_o   = 1'b1;
  assign tcdm_wdata_o = '0;
  assign tcdm_be_o    = 4'hF;
  assign sram_addr_o  = cnt_q[7:0];
  assign sram_wdata_o = {sram_rdata_i, sram_rdata_i};
  assign sram_we_o    = busy_o;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      cnt_q  <= '0;
      busy_o <= 1'b0;
      done_o <= 1'b0;
    end else begin
      done_o <= 1'b0;
      if (start_i && !busy_o) begin
        busy_o <= 1'b1;
        cnt_q  <= '0;
      end else if (busy_o) begin
        cnt_q <= cnt_q + 1;
        if (cnt_q == 13'd8191) begin
          busy_o <= 1'b0;
          done_o <= 1'b1;
        end
      end
    end
  end
endmodule
