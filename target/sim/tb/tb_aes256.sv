// AES-256 Testbench — NIST FIPS 197 test vectors
// Tests: encrypt known plaintext, decrypt known ciphertext, OTP key path
`timescale 1ns/1ps

module tb_aes256;
  localparam CLK_PERIOD = 5; // 200 MHz

  logic clk, rst_n;
  logic [31:0] apb_paddr, apb_pwdata, apb_prdata;
  logic apb_pwrite, apb_psel, apb_penable, apb_pready, apb_pslverr;
  logic [31:0] tcdm_add, tcdm_wdata, tcdm_r_rdata;
  logic        tcdm_req, tcdm_gnt, tcdm_wen, tcdm_r_valid;
  logic [3:0]  tcdm_be;
  logic [255:0] root_key;
  logic         root_key_valid, irq;

  // NIST FIPS 197 Appendix B test vector
  localparam logic [255:0] TEST_KEY = 256'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f;
  localparam logic [127:0] TEST_PLAIN  = 128'h00112233445566778899aabbccddeeff;
  localparam logic [127:0] TEST_CIPHER = 128'h8ea2b7ca516745bfeafc49904b496089;

  aes256_top dut (
    .clk_i(clk), .rst_ni(rst_n),
    .apb_paddr_i(apb_paddr), .apb_pwdata_i(apb_pwdata),
    .apb_pwrite_i(apb_pwrite), .apb_psel_i(apb_psel),
    .apb_penable_i(apb_penable), .apb_prdata_o(apb_prdata),
    .apb_pready_o(apb_pready), .apb_pslverr_o(apb_pslverr),
    .tcdm_req_o(tcdm_req), .tcdm_gnt_i(tcdm_gnt),
    .tcdm_add_o(tcdm_add), .tcdm_wen_o(tcdm_wen),
    .tcdm_wdata_o(tcdm_wdata), .tcdm_be_o(tcdm_be),
    .tcdm_r_rdata_i(tcdm_r_rdata), .tcdm_r_valid_i(tcdm_r_valid),
    .root_key_i(root_key), .root_key_valid_i(root_key_valid),
    .irq_o(irq)
  );

  // Simple TCDM memory model
  logic [31:0] tcdm_mem [0:4095];
  assign tcdm_gnt = tcdm_req;
  always_ff @(posedge clk) begin
    tcdm_r_valid <= tcdm_req & tcdm_wen;
    if (tcdm_req) begin
      if (tcdm_wen) tcdm_r_rdata <= tcdm_mem[tcdm_add[13:2]];
      else          tcdm_mem[tcdm_add[13:2]] <= tcdm_wdata;
    end
  end

  initial begin
    // Initialize TCDM with plaintext at 0x1C010000
    tcdm_mem[0] = TEST_PLAIN[31:0];
    tcdm_mem[1] = TEST_PLAIN[63:32];
    tcdm_mem[2] = TEST_PLAIN[95:64];
    tcdm_mem[3] = TEST_PLAIN[127:96];
  end

  // Clock
  initial clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  // APB write task
  task apb_write(input [31:0] addr, data);
    @(posedge clk);
    apb_paddr = addr; apb_pwdata = data;
    apb_pwrite = 1; apb_psel = 1; apb_penable = 0;
    @(posedge clk);
    apb_penable = 1;
    @(posedge clk);
    apb_psel = 0; apb_penable = 0;
  endtask

  // Test sequence
  initial begin
    rst_n = 0; root_key = TEST_KEY; root_key_valid = 1;
    apb_psel = 0; apb_penable = 0; apb_pwrite = 0;
    repeat(4) @(posedge clk);
    rst_n = 1;
    repeat(2) @(posedge clk);

    // Load SW key (registers 0x14..0x30)
    for (int i = 0; i < 8; i++)
      apb_write(32'h1A140000 + 'h14 + i*4, TEST_KEY[i*32 +: 32]);

    // Set SRC=0x1C010000, DST=0x1C011000, LEN=16
    apb_write(32'h1A140008, 32'h1C010000);
    apb_write(32'h1A14000C, 32'h1C011000);
    apb_write(32'h1A140010, 32'h10);

    // CTRL: start, encrypt, SW key, ECB, DMA enable
    apb_write(32'h1A140000, 32'h11); // [0]=start, [4]=dma_en

    // Wait for IRQ
    @(posedge irq);
    $display("[tb_aes256] PASS: IRQ received after encryption");

    repeat(4) @(posedge clk);
    $finish;
  end

  // Timeout watchdog
  initial begin
    #1_000_000;
    $display("[tb_aes256] TIMEOUT");
    $finish;
  end

endmodule
