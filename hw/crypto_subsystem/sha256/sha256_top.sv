// SHA-256 Top — APB slave + uDMA FIFO interface
// Computes SHA-256 digest over a message stream.
// Data sourced via uDMA FIFO (rx channel); digest written back via uDMA tx.
// SPDX-License-Identifier: SHL-0.51

module sha256_top #(
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

  // uDMA FIFO interface (data in)
  input  logic [31:0]                udma_data_i,
  input  logic                       udma_valid_i,
  output logic                       udma_ready_o,

  // uDMA FIFO interface (digest out — 8 × 32-bit = 256-bit)
  output logic [31:0]                udma_data_o,
  output logic                       udma_valid_o,
  input  logic                       udma_ready_i,

  // Interrupt to event unit
  output logic                       irq_o
);

  // -------------------------------------------------------------------------
  // Register map
  // 0x00 CTRL   [0]=start [1]=last_block
  // 0x04 STATUS [0]=busy [1]=done
  // 0x08 LENGTH  total message byte length (for padding)
  // 0x0C-0x28 DIGEST[7:0]  256-bit read-back digest
  // -------------------------------------------------------------------------

  logic [31:0]  ctrl_q;
  logic [31:0]  length_q;
  logic [255:0] digest_q;
  logic         busy_q, done_q;

  logic apb_access;
  assign apb_access    = apb_psel_i & apb_penable_i;
  assign apb_pready_o  = 1'b1;
  assign apb_pslverr_o = 1'b0;

  logic [3:0] apb_word;
  assign apb_word = apb_paddr_i[5:2];

  always_comb begin
    apb_prdata_o = '0;
    case (apb_word)
      4'h0: apb_prdata_o = ctrl_q;
      4'h1: apb_prdata_o = {30'b0, done_q, busy_q};
      4'h2: apb_prdata_o = length_q;
      default: begin
        if (apb_word >= 4'h3 && apb_word <= 4'hA)
          apb_prdata_o = digest_q[(apb_word - 4'h3)*32 +: 32];
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      ctrl_q   <= '0;
      length_q <= '0;
    end else if (apb_access && apb_pwrite_i) begin
      case (apb_word)
        4'h0: ctrl_q   <= apb_pwdata_i;
        4'h2: length_q <= apb_pwdata_i;
        default: ;
      endcase
    end
  end

  // -------------------------------------------------------------------------
  // SHA-256 core (behavioral — 64 rounds per 512-bit block)
  // -------------------------------------------------------------------------
  sha256_core i_sha256_core (
    .clk_i        (clk_i),
    .rst_ni       (rst_ni),
    .start_i      (ctrl_q[0] && !busy_q),
    .last_block_i (ctrl_q[1]),
    .msg_len_i    (length_q),
    .data_i       (udma_data_i),
    .data_valid_i (udma_valid_i),
    .data_ready_o (udma_ready_o),
    .digest_o     (digest_q),
    .digest_valid_o(done_q),
    .busy_o       (busy_q)
  );

  // Output digest words over uDMA tx FIFO after done
  logic [2:0] out_word_q;
  logic       out_active_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      out_word_q   <= '0;
      out_active_q <= 1'b0;
      irq_o        <= 1'b0;
    end else begin
      irq_o <= 1'b0;
      if (done_q && !out_active_q) begin
        out_active_q <= 1'b1;
        out_word_q   <= '0;
        irq_o        <= 1'b1;
      end else if (out_active_q && udma_ready_i) begin
        if (out_word_q == 3'd7) out_active_q <= 1'b0;
        else out_word_q <= out_word_q + 1;
      end
    end
  end

  assign udma_valid_o = out_active_q;
  assign udma_data_o  = digest_q[out_word_q*32 +: 32];

endmodule


// SHA-256 core — behavioral model
module sha256_core (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        start_i,
  input  logic        last_block_i,
  input  logic [31:0] msg_len_i,
  input  logic [31:0] data_i,
  input  logic        data_valid_i,
  output logic        data_ready_o,
  output logic [255:0] digest_o,
  output logic        digest_valid_o,
  output logic        busy_o
);
  // SHA-256 initial hash values H0-H7
  localparam logic [255:0] H_INIT = {
    32'h6a09e667, 32'hbb67ae85, 32'h3c6ef372, 32'ha54ff53a,
    32'h510e527f, 32'h9b05688c, 32'h1f83d9ab, 32'h5be0cd19
  };

  // 64 round constants (first 8 shown; full set needed for production)
  logic [31:0] K [0:63];
  initial begin
    K[0]=32'h428a2f98; K[1]=32'h71374491; K[2]=32'hb5c0fbcf; K[3]=32'he9b5dba5;
    K[4]=32'h3956c25b; K[5]=32'h59f111f1; K[6]=32'h923f82a4; K[7]=32'hab1c5ed5;
    // Remaining 56 constants set to zero in behavioral stub
    for (int i = 8; i < 64; i++) K[i] = 32'h0;
  end

  logic [255:0] hash_q;
  logic [511:0] block_buf_q;
  logic [5:0]   word_cnt_q;
  logic [5:0]   round_q;
  logic         active_q;

  typedef enum logic [1:0] { IDLE, LOAD, COMPRESS, OUTPUT } state_t;
  state_t state_q;

  assign busy_o       = (state_q != IDLE);
  assign data_ready_o = (state_q == LOAD);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q      <= IDLE;
      hash_q       <= H_INIT;
      block_buf_q  <= '0;
      word_cnt_q   <= '0;
      round_q      <= '0;
      digest_o     <= '0;
      digest_valid_o <= 1'b0;
    end else begin
      digest_valid_o <= 1'b0;
      case (state_q)
        IDLE: if (start_i) begin
          state_q    <= LOAD;
          word_cnt_q <= '0;
          hash_q     <= H_INIT;
        end

        LOAD: if (data_valid_i) begin
          block_buf_q[word_cnt_q*32 +: 32] <= data_i;
          if (word_cnt_q == 6'd15) begin
            state_q    <= COMPRESS;
            round_q    <= '0;
          end else begin
            word_cnt_q <= word_cnt_q + 1;
          end
        end

        COMPRESS: begin
          // Behavioral placeholder: XOR compression
          hash_q  <= hash_q ^ {8{block_buf_q[round_q*32 +: 32]}};
          if (round_q == 6'd63) begin
            state_q <= OUTPUT;
          end else begin
            round_q <= round_q + 1;
          end
        end

        OUTPUT: begin
          digest_o       <= hash_q;
          digest_valid_o <= 1'b1;
          state_q        <= IDLE;
        end
      endcase
    end
  end
endmodule
