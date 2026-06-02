// SHA-256 Testbench — NIST SHA-256 test vector ("abc" = 0x61 0x62 0x63)
`timescale 1ns/1ps

module tb_sha256;
  localparam CLK_PERIOD = 5;

  logic clk, rst_n;
  logic [31:0] apb_paddr, apb_pwdata, apb_prdata;
  logic apb_pwrite, apb_psel, apb_penable, apb_pready, apb_pslverr;
  logic [31:0] udma_in, udma_out;
  logic        udma_valid_in, udma_ready_out, udma_valid_out, udma_ready_in;
  logic        irq;

  sha256_top dut (
    .clk_i(clk), .rst_ni(rst_n),
    .apb_paddr_i(apb_paddr), .apb_pwdata_i(apb_pwdata),
    .apb_pwrite_i(apb_pwrite), .apb_psel_i(apb_psel),
    .apb_penable_i(apb_penable), .apb_prdata_o(apb_prdata),
    .apb_pready_o(apb_pready), .apb_pslverr_o(apb_pslverr),
    .udma_data_i(udma_in), .udma_valid_i(udma_valid_in),
    .udma_ready_o(udma_ready_out),
    .udma_data_o(udma_out), .udma_valid_o(udma_valid_out),
    .udma_ready_i(udma_ready_in),
    .irq_o(irq)
  );

  initial clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  task apb_write(input [31:0] addr, data);
    @(posedge clk);
    apb_paddr = addr; apb_pwdata = data; apb_pwrite = 1; apb_psel = 1; apb_penable = 0;
    @(posedge clk); apb_penable = 1;
    @(posedge clk); apb_psel = 0; apb_penable = 0;
  endtask

  // NIST expected digest for "abc" (512-bit padded block)
  localparam logic [255:0] EXPECTED =
    256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad;

  logic [255:0] got_digest;

  initial begin
    rst_n = 0; apb_psel = 0; apb_penable = 0; apb_pwrite = 0;
    udma_valid_in = 0; udma_ready_in = 1;
    repeat(4) @(posedge clk); rst_n = 1;
    repeat(2) @(posedge clk);

    // Set length = 3 bytes, start + last_block
    apb_write(32'h1A141008, 32'h3); // LENGTH = 3
    apb_write(32'h1A141000, 32'h3); // CTRL: start + last_block

    // Feed "abc" padded to 512 bits over uDMA (16 words)
    // Word 0: 0x61626380 (abc + pad bit)
    @(posedge clk);
    udma_in = 32'h61626380; udma_valid_in = 1;
    @(posedge clk); while (!udma_ready_out) @(posedge clk);
    // Words 1-13: zeros
    udma_in = 32'h0;
    repeat(13) begin
      @(posedge clk); while (!udma_ready_out) @(posedge clk);
    end
    // Word 14: 0x00000000 (length high)
    udma_in = 32'h0; @(posedge clk);
    // Word 15: 0x00000018 (length = 24 bits)
    udma_in = 32'h18; @(posedge clk);
    udma_valid_in = 0;

    @(posedge irq);
    $display("[tb_sha256] PASS: IRQ received");

    // Read digest words
    for (int i = 0; i < 8; i++) begin
      @(posedge clk);
      got_digest[i*32 +: 32] = dut.digest_q[i*32 +: 32];
    end

    $display("[tb_sha256] Digest: %h", got_digest);
    $finish;
  end

  initial begin #2_000_000; $display("[tb_sha256] TIMEOUT"); $finish; end
endmodule
