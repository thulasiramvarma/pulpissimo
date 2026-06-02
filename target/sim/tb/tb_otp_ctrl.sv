// OTP Controller Testbench — write-then-read, key load, lock test
`timescale 1ns/1ps

module tb_otp_ctrl;
  localparam CLK_PERIOD = 5;

  logic clk, rst_n;
  logic [31:0] apb_paddr, apb_pwdata, apb_prdata;
  logic apb_pwrite, apb_psel, apb_penable, apb_pready, apb_pslverr;
  logic vpp_sense, vref_sense;
  logic [255:0] root_key, device_key;
  logic root_key_valid, device_key_valid;
  logic irq;

  otp_ctrl_top dut (
    .clk_i(clk), .rst_ni(rst_n),
    .apb_paddr_i(apb_paddr), .apb_pwdata_i(apb_pwdata),
    .apb_pwrite_i(apb_pwrite), .apb_psel_i(apb_psel),
    .apb_penable_i(apb_penable), .apb_prdata_o(apb_prdata),
    .apb_pready_o(apb_pready), .apb_pslverr_o(apb_pslverr),
    .vpp_sense_i(vpp_sense), .vref_sense_i(vref_sense),
    .root_key_o(root_key), .root_key_valid_o(root_key_valid),
    .device_key_o(device_key), .device_key_valid_o(device_key_valid),
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

  logic [31:0] rd_data;

  initial begin
    rst_n = 0; vpp_sense = 0; vref_sense = 0;
    apb_psel = 0; apb_penable = 0; apb_pwrite = 0;
    repeat(4) @(posedge clk); rst_n = 1;
    repeat(2) @(posedge clk);

    // ---- Test 1: Program word 32 (user area) ----
    $display("[tb_otp] Test 1: OTP program user word");
    vpp_sense = 1; vref_sense = 1;
    apb_write(32'h1A145008, 32'h20);      // ADDR = 32
    apb_write(32'h1A14500C, 32'hA5A5A5A5); // WDATA
    apb_write(32'h1A145000, 32'h1);        // CTRL: prog_req
    repeat(10) @(posedge clk);
    apb_read(32'h1A145004, rd_data);
    if (rd_data[1]) $display("[tb_otp] PASS: prog_done asserted");
    else            $display("[tb_otp] FAIL: prog_done not asserted");
    vpp_sense = 0;

    // ---- Test 2: Read back programmed word ----
    $display("[tb_otp] Test 2: OTP read back");
    apb_write(32'h1A145008, 32'h20);  // ADDR = 32
    apb_write(32'h1A145000, 32'h2);   // CTRL: read_req
    repeat(4) @(posedge clk);
    apb_read(32'h1A145010, rd_data);
    $display("[tb_otp] Read data = 0x%h (expected 0x5A5A5A5A after blow)", rd_data);

    // ---- Test 3: Key load ----
    $display("[tb_otp] Test 3: Key load");
    apb_write(32'h1A145000, 32'h4); // CTRL: key_load
    @(posedge root_key_valid);
    $display("[tb_otp] PASS: root_key_valid asserted, key = %h", root_key);

    // ---- Test 4: Key lock ----
    $display("[tb_otp] Test 4: Key lock");
    apb_write(32'h1A145000, 32'h8); // CTRL: key_lock
    repeat(2) @(posedge clk);
    // Try to read key word 0 — should return DEADBEEF
    apb_write(32'h1A145008, 32'h0);
    apb_write(32'h1A145000, 32'h2);
    repeat(4) @(posedge clk);
    apb_read(32'h1A145010, rd_data);
    if (rd_data == 32'hDEAD_BEEF)
      $display("[tb_otp] PASS: key locked (read returned DEADBEEF)");
    else
      $display("[tb_otp] FAIL: key not locked, got 0x%h", rd_data);

    $display("[tb_otp] All tests done");
    $finish;
  end

  initial begin #5_000_000; $display("[tb_otp] TIMEOUT"); $finish; end
endmodule
