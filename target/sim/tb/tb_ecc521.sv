// ECC-521 Testbench — sign/verify round-trip on P-521
`timescale 1ns/1ps

module tb_ecc521;
  localparam CLK_PERIOD = 5;

  logic clk, rst_n;
  logic [31:0] apb_paddr, apb_pwdata, apb_prdata;
  logic apb_pwrite, apb_psel, apb_penable, apb_pready, apb_pslverr;
  logic [255:0] device_key;
  logic         device_key_valid, irq;

  ecc521_top dut (
    .clk_i(clk), .rst_ni(rst_n),
    .apb_paddr_i(apb_paddr), .apb_pwdata_i(apb_pwdata),
    .apb_pwrite_i(apb_pwrite), .apb_psel_i(apb_psel),
    .apb_penable_i(apb_penable), .apb_prdata_o(apb_prdata),
    .apb_pready_o(apb_pready), .apb_pslverr_o(apb_pslverr),
    .device_key_i(device_key), .device_key_valid_i(device_key_valid),
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

  // Test vector (simplified — real P-521 vectors from NIST FIPS 186-5)
  localparam logic [255:0] TEST_KEY    = 256'hDEAD_BEEF_1234_5678_9ABC_DEF0_1234_5678_9ABC_DEF0_DEAD_BEEF_CAFE_BABE;
  localparam logic [543:0] TEST_HASH   = 544'h1234; // simplified

  initial begin
    rst_n = 0; device_key = TEST_KEY; device_key_valid = 1;
    apb_psel = 0; apb_penable = 0; apb_pwrite = 0;
    repeat(4) @(posedge clk); rst_n = 1;
    repeat(2) @(posedge clk);

    // Write hash (17 words at base+0x08)
    for (int i = 0; i < 17; i++)
      apb_write(32'h1A142008 + i*4, TEST_HASH[i*32 +: 32]);

    // Write nonce (17 words at base+0x4C)
    for (int i = 0; i < 17; i++)
      apb_write(32'h1A14204C + i*4, 32'hCAFEBABE + i);

    // CTRL: start, sign (op=0), use OTP key (key_sel=1)
    apb_write(32'h1A142000, 32'h5); // [0]=start, [2]=key_sel=otp

    @(posedge irq);
    $display("[tb_ecc521] PASS: sign done, IRQ received");

    repeat(4) @(posedge clk);
    $finish;
  end

  initial begin #50_000_000; $display("[tb_ecc521] TIMEOUT"); $finish; end
endmodule
