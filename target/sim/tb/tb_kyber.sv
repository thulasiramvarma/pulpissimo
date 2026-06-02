// PQC Kyber-1024 Testbench — keygen operation
`timescale 1ns/1ps

module tb_kyber;
  localparam CLK_PERIOD = 5;

  logic clk, rst_n;
  logic [31:0] apb_paddr, apb_pwdata, apb_prdata;
  logic apb_pwrite, apb_psel, apb_penable, apb_pready, apb_pslverr;
  logic        tcdm_req, tcdm_gnt, tcdm_wen, tcdm_r_valid;
  logic [31:0] tcdm_add, tcdm_wdata, tcdm_r_rdata;
  logic [3:0]  tcdm_be;
  logic        irq;

  kyber_top dut (
    .clk_i(clk), .rst_ni(rst_n),
    .apb_paddr_i(apb_paddr), .apb_pwdata_i(apb_pwdata),
    .apb_pwrite_i(apb_pwrite), .apb_psel_i(apb_psel),
    .apb_penable_i(apb_penable), .apb_prdata_o(apb_prdata),
    .apb_pready_o(apb_pready), .apb_pslverr_o(apb_pslverr),
    .tcdm_req_o(tcdm_req), .tcdm_gnt_i(tcdm_gnt),
    .tcdm_add_o(tcdm_add), .tcdm_wen_o(tcdm_wen),
    .tcdm_wdata_o(tcdm_wdata), .tcdm_be_o(tcdm_be),
    .tcdm_r_rdata_i(tcdm_r_rdata), .tcdm_r_valid_i(tcdm_r_valid),
    .irq_o(irq)
  );

  // TCDM model
  logic [31:0] tcdm_mem [0:4095];
  assign tcdm_gnt = tcdm_req;
  always_ff @(posedge clk) begin
    tcdm_r_valid <= tcdm_req & tcdm_wen;
    if (tcdm_req) begin
      if (tcdm_wen) tcdm_r_rdata <= tcdm_mem[tcdm_add[13:2]];
      else          tcdm_mem[tcdm_add[13:2]] <= tcdm_wdata;
    end
  end

  initial clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  task apb_write(input [31:0] addr, data);
    @(posedge clk);
    apb_paddr = addr; apb_pwdata = data; apb_pwrite = 1; apb_psel = 1; apb_penable = 0;
    @(posedge clk); apb_penable = 1;
    @(posedge clk); apb_psel = 0; apb_penable = 0;
  endtask

  initial begin
    rst_n = 0; apb_psel = 0; apb_penable = 0; apb_pwrite = 0;
    repeat(4) @(posedge clk); rst_n = 1;
    repeat(2) @(posedge clk);

    // Configure: op=keygen(00), src=0x1C010000, dst=0x1C020000, len=2048
    apb_write(32'h1A143008, 32'h1C010000); // SRC
    apb_write(32'h1A14300C, 32'h1C020000); // DST
    apb_write(32'h1A143010, 32'h800);       // LENGTH = 2048B

    // CTRL: op=00 (keygen), start
    apb_write(32'h1A143000, 32'h4); // [2]=start

    @(posedge irq);
    $display("[tb_kyber] PASS: keygen done, IRQ received");

    repeat(4) @(posedge clk);
    $finish;
  end

  initial begin #20_000_000; $display("[tb_kyber] TIMEOUT"); $finish; end
endmodule
