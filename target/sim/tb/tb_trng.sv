// TRNG Testbench — check entropy output statistics
`timescale 1ns/1ps

module tb_trng;
  localparam CLK_PERIOD = 5;
  localparam int SAMPLES = 1000;

  logic clk, rst_n;
  logic [31:0] apb_paddr, apb_pwdata, apb_prdata;
  logic apb_pwrite, apb_psel, apb_penable, apb_pready, apb_pslverr;
  logic irq;

  trng_top dut (
    .clk_i(clk), .rst_ni(rst_n),
    .apb_paddr_i(apb_paddr), .apb_pwdata_i(apb_pwdata),
    .apb_pwrite_i(apb_pwrite), .apb_psel_i(apb_psel),
    .apb_penable_i(apb_penable), .apb_prdata_o(apb_prdata),
    .apb_pready_o(apb_pready), .apb_pslverr_o(apb_pslverr),
    .dft_test_en_i(1'b0),
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

  task apb_read(input [31:0] addr, output [31:0] data);
    @(posedge clk);
    apb_paddr = addr; apb_pwrite = 0; apb_psel = 1; apb_penable = 0;
    @(posedge clk); apb_penable = 1;
    @(posedge clk); data = apb_prdata; apb_psel = 0; apb_penable = 0;
  endtask

  int unsigned ones_count;
  logic [31:0] sample;

  initial begin
    rst_n = 0; apb_psel = 0; apb_penable = 0; apb_pwrite = 0;
    repeat(4) @(posedge clk); rst_n = 1;
    repeat(2) @(posedge clk);

    // Enable TRNG, enable IRQ
    apb_write(32'h1A144000, 32'h3); // CTRL: enable + irq_en

    ones_count = 0;
    for (int i = 0; i < SAMPLES; i++) begin
      @(posedge irq);
      apb_read(32'h1A144008, sample); // Read DATA
      ones_count += $countones(sample);
    end

    // Statistical check: ones_count should be ~50% ± 5% of total bits
    automatic int total_bits = SAMPLES * 32;
    automatic real ratio = real'(ones_count) / real'(total_bits);
    $display("[tb_trng] Ones ratio: %0.3f (expected ~0.5)", ratio);
    if (ratio > 0.45 && ratio < 0.55)
      $display("[tb_trng] PASS: entropy within statistical bounds");
    else
      $display("[tb_trng] WARN: entropy outside bounds (check RO)");

    $finish;
  end

  initial begin #10_000_000; $display("[tb_trng] TIMEOUT"); $finish; end
endmodule
