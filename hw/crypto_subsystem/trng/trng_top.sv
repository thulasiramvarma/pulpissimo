// TRNG Top — APB slave, register-driven
// True Random Number Generator using ring oscillator entropy source.
// Ring oscillator paths are set as false_path in SDC (not synthesized as logic).
// Entropy rate: ~1-4 MB/s; firmware reads 32-bit words on interrupt.
// SPDX-License-Identifier: SHL-0.51

module trng_top #(
  parameter int unsigned APB_ADDR_WIDTH = 32,
  parameter int unsigned APB_DATA_WIDTH = 32,
  // Number of ring oscillator stages (replaced with analog RO in ASIC)
  parameter int unsigned NB_RO_STAGES   = 31
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

  // DFT: ring oscillators must be bypassed during scan
  input  logic                       dft_test_en_i,

  // Interrupt — fired each time a new 32-bit word is ready
  output logic                       irq_o
);

  // -------------------------------------------------------------------------
  // Register map
  // 0x00 CTRL    [0]=enable [1]=irq_en [2]=health_test_en
  // 0x04 STATUS  [0]=data_ready [1]=health_fail [2]=fifo_full
  // 0x08 DATA    32-bit random word (read clears data_ready, fires next sample)
  // 0x0C FIFO_LEVEL  number of valid 32-bit words in output FIFO (depth=8)
  // 0x10 HEALTH_CNT  number of health test failures since last clear
  // -------------------------------------------------------------------------

  logic [31:0] ctrl_q;
  logic        health_fail_q;
  logic [3:0]  fifo_level_q;
  logic [31:0] health_cnt_q;

  // FIFO for entropy words (depth 8)
  logic [31:0] fifo_q [0:7];
  logic [2:0]  fifo_wr_ptr_q, fifo_rd_ptr_q;
  logic        fifo_full, fifo_empty;
  assign fifo_full  = (fifo_wr_ptr_q[2:0] == fifo_rd_ptr_q[2:0]) &&
                      (fifo_wr_ptr_q != fifo_rd_ptr_q);
  assign fifo_empty = (fifo_wr_ptr_q == fifo_rd_ptr_q);
  assign fifo_level_q = fifo_wr_ptr_q - fifo_rd_ptr_q;

  // -------------------------------------------------------------------------
  // Ring oscillator entropy source (NB_RO_STAGES free-running inverters)
  // In simulation: behavioral LFSR feeds entropy.
  // In ASIC: physical RO cells inserted by place-and-route.
  // set_false_path -from [get_cells *trng*ro*] in SDC.
  // -------------------------------------------------------------------------
  logic [NB_RO_STAGES-1:0] ro_out;
  logic [31:0] sample_q;
  logic [5:0]  sample_bit_q;
  logic        sample_done;

  // Behavioral RO: LFSR feedback (synthesis: false path)
  logic [NB_RO_STAGES-1:0] lfsr_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) lfsr_q <= {NB_RO_STAGES{1'b1}};
    else if (ctrl_q[0] && !dft_test_en_i)
      lfsr_q <= {lfsr_q[NB_RO_STAGES-2:0], lfsr_q[NB_RO_STAGES-1] ^ lfsr_q[NB_RO_STAGES-3]};
  end
  assign ro_out = lfsr_q;

  // Sample XOR of all RO outputs one bit at a time into 32-bit word
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sample_q     <= '0;
      sample_bit_q <= '0;
      sample_done  <= 1'b0;
    end else begin
      sample_done <= 1'b0;
      if (ctrl_q[0] && !dft_test_en_i) begin
        sample_q[sample_bit_q[4:0]] <= ^ro_out;
        if (sample_bit_q == 6'd31) begin
          sample_bit_q <= '0;
          sample_done  <= 1'b1;
        end else begin
          sample_bit_q <= sample_bit_q + 1;
        end
      end
    end
  end

  // Push samples into FIFO
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      fifo_wr_ptr_q <= '0;
      fifo_rd_ptr_q <= '0;
    end else begin
      if (sample_done && !fifo_full) begin
        fifo_q[fifo_wr_ptr_q[2:0]] <= sample_q;
        fifo_wr_ptr_q <= fifo_wr_ptr_q + 1;
      end
    end
  end

  // -------------------------------------------------------------------------
  // APB register interface
  // -------------------------------------------------------------------------
  logic apb_access, data_read;
  assign apb_access    = apb_psel_i & apb_penable_i;
  assign apb_pready_o  = 1'b1;
  assign apb_pslverr_o = 1'b0;

  logic [2:0] apb_word;
  assign apb_word = apb_paddr_i[4:2];

  assign data_read = apb_access && !apb_pwrite_i && apb_word == 3'h2;

  always_comb begin
    apb_prdata_o = '0;
    case (apb_word)
      3'h0: apb_prdata_o = ctrl_q;
      3'h1: apb_prdata_o = {29'b0, fifo_full, health_fail_q, !fifo_empty};
      3'h2: apb_prdata_o = fifo_empty ? '0 : fifo_q[fifo_rd_ptr_q[2:0]];
      3'h3: apb_prdata_o = {28'b0, fifo_level_q};
      3'h4: apb_prdata_o = health_cnt_q;
      default: ;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      ctrl_q        <= '0;
      health_fail_q <= 1'b0;
      health_cnt_q  <= '0;
      irq_o         <= 1'b0;
    end else begin
      irq_o <= 1'b0;
      if (apb_access && apb_pwrite_i && apb_word == 3'h0)
        ctrl_q <= apb_pwdata_i;
      // Pop FIFO on read
      if (data_read && !fifo_empty)
        fifo_rd_ptr_q <= fifo_rd_ptr_q + 1;
      // Interrupt when word available and irq_en
      if (sample_done && ctrl_q[1])
        irq_o <= 1'b1;
    end
  end

endmodule
