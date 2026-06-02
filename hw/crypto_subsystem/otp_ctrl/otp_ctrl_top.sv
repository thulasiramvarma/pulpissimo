// OTP Controller Top — APB slave + analog macro interface
// Controls access to the 8kbit OTP hard macro.
// Exports root_key[255:0] and device_key[255:0] on private key bus.
// APB access restricted to non-key regions (key words are write-once, read-locked).
// SPDX-License-Identifier: SHL-0.51

module otp_ctrl_top #(
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

  // Analog supply sense from top-level pads
  input  logic                       vpp_sense_i,
  input  logic                       vref_sense_i,

  // Private key bus outputs (to AES and ECC — never on APB)
  output logic [255:0]               root_key_o,
  output logic                       root_key_valid_o,
  output logic [255:0]               device_key_o,
  output logic                       device_key_valid_o,

  // Interrupt to event unit
  output logic                       irq_o
);

  // -------------------------------------------------------------------------
  // OTP layout (256 × 32-bit = 8 kbit)
  // Words 0-7   (256 bit) : Root key (AES-256) — read-locked after boot
  // Words 8-15  (256 bit) : Device key (ECC-521, lower 256 bits of 521-bit key)
  // Words 16-31 (512 bit) : Provisioning data / certificates
  // Words 32-255           : User/application NVM space
  // -------------------------------------------------------------------------

  localparam int ROOT_KEY_BASE   = 0;
  localparam int ROOT_KEY_WORDS  = 8;
  localparam int DEV_KEY_BASE    = 8;
  localparam int DEV_KEY_WORDS   = 8;
  localparam int OTP_DEPTH       = 256;

  // -------------------------------------------------------------------------
  // Register map (APB offset from crypto subsystem base + OTP offset)
  // 0x000 CTRL   [0]=prog_req [1]=read_req [2]=key_load [3]=key_lock
  // 0x004 STATUS [0]=busy [1]=prog_done [2]=prog_fail [3]=key_loaded [4]=key_locked
  // 0x008 ADDR   OTP word address for APB access
  // 0x00C WDATA  write data for programming
  // 0x010 RDATA  read data (non-key region only)
  // -------------------------------------------------------------------------

  logic [31:0] ctrl_q;
  logic [7:0]  otp_addr_q;
  logic [31:0] otp_wdata_q;
  logic [31:0] otp_rdata_raw;
  logic        otp_rdata_valid;
  logic        otp_prog_done, otp_prog_fail;
  logic        key_loaded_q, key_locked_q;
  logic        busy_q;

  // OTP macro interface
  logic otp_prog_en, otp_read_en;
  assign otp_prog_en = ctrl_q[0] && vpp_sense_i;
  assign otp_read_en = ctrl_q[1] && vref_sense_i;

  otp_analog_macro #(.DEPTH(OTP_DEPTH), .WIDTH(32)) i_otp_macro (
    .clk_i         (clk_i),
    .rst_ni        (rst_ni),
    .prog_en_i     (otp_prog_en),
    .read_en_i     (otp_read_en),
    .addr_i        (otp_addr_q),
    .wdata_i       (otp_wdata_q),
    .rdata_o       (otp_rdata_raw),
    .rdata_valid_o (otp_rdata_valid),
    .vpp_sense_i   (vpp_sense_i),
    .vref_sense_i  (vref_sense_i),
    .prog_done_o   (otp_prog_done),
    .prog_fail_o   (otp_prog_fail)
  );

  // -------------------------------------------------------------------------
  // Key load FSM — reads words 0-7 (root key) and 8-15 (device key) at boot
  // -------------------------------------------------------------------------
  typedef enum logic [1:0] { KL_IDLE, KL_ROOT, KL_DEVICE, KL_DONE } kl_state_t;
  kl_state_t kl_state_q;
  logic [2:0] kl_word_q;
  logic [255:0] root_key_q, dev_key_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      kl_state_q       <= KL_IDLE;
      kl_word_q        <= '0;
      root_key_q       <= '0;
      dev_key_q        <= '0;
      key_loaded_q     <= 1'b0;
      busy_q           <= 1'b0;
      otp_addr_q       <= '0;
    end else begin
      case (kl_state_q)
        KL_IDLE: begin
          if (ctrl_q[2] && !key_loaded_q && vref_sense_i) begin
            kl_state_q <= KL_ROOT;
            kl_word_q  <= '0;
            busy_q     <= 1'b1;
            otp_addr_q <= ROOT_KEY_BASE;
          end
        end

        KL_ROOT: begin
          if (otp_rdata_valid) begin
            root_key_q[kl_word_q*32 +: 32] <= otp_rdata_raw;
            if (kl_word_q == 3'd7) begin
              kl_state_q <= KL_DEVICE;
              kl_word_q  <= '0;
              otp_addr_q <= DEV_KEY_BASE;
            end else begin
              kl_word_q  <= kl_word_q + 1;
              otp_addr_q <= otp_addr_q + 1;
            end
          end
        end

        KL_DEVICE: begin
          if (otp_rdata_valid) begin
            dev_key_q[kl_word_q*32 +: 32] <= otp_rdata_raw;
            if (kl_word_q == 3'd7) begin
              kl_state_q   <= KL_DONE;
              key_loaded_q <= 1'b1;
              busy_q       <= 1'b0;
            end else begin
              kl_word_q  <= kl_word_q + 1;
              otp_addr_q <= otp_addr_q + 1;
            end
          end
        end

        KL_DONE: kl_state_q <= KL_DONE; // stay until reset
      endcase

      // APB-driven address override (non-key region access)
      if (apb_psel_i & apb_penable_i & apb_pwrite_i) begin
        case (apb_paddr_i[4:2])
          3'h0: ; // ctrl handled separately
          3'h2: otp_addr_q  <= apb_pwdata_i[7:0];
          3'h3: otp_wdata_q <= apb_pwdata_i;
          default: ;
        endcase
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) ctrl_q <= '0;
    else if (apb_psel_i & apb_penable_i & apb_pwrite_i & (apb_paddr_i[4:2] == 3'h0))
      ctrl_q <= apb_pwdata_i;
  end

  // Key lock: once locked, key words cannot be read via APB
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) key_locked_q <= 1'b0;
    else if (ctrl_q[3]) key_locked_q <= 1'b1; // one-way latch
  end

  // -------------------------------------------------------------------------
  // APB read path — block access to key words when locked
  // -------------------------------------------------------------------------
  logic [4:0] apb_word_idx;
  assign apb_word_idx = apb_paddr_i[6:2];

  logic apb_access;
  assign apb_access    = apb_psel_i & apb_penable_i;
  assign apb_pready_o  = 1'b1;
  assign apb_pslverr_o = 1'b0;

  always_comb begin
    apb_prdata_o = '0;
    case (apb_paddr_i[4:2])
      3'h0: apb_prdata_o = ctrl_q;
      3'h1: apb_prdata_o = {27'b0, key_locked_q, key_loaded_q,
                             otp_prog_fail, otp_prog_done, busy_q};
      3'h2: apb_prdata_o = {24'b0, otp_addr_q};
      3'h3: apb_prdata_o = otp_wdata_q;
      3'h4: apb_prdata_o = (key_locked_q &&
                             otp_addr_q < 8'(DEV_KEY_BASE + DEV_KEY_WORDS))
                           ? 32'hDEAD_BEEF // locked
                           : otp_rdata_raw;
      default: ;
    endcase
  end

  // -------------------------------------------------------------------------
  // Private key outputs
  // -------------------------------------------------------------------------
  assign root_key_o        = root_key_q;
  assign root_key_valid_o  = key_loaded_q;
  assign device_key_o      = dev_key_q;
  assign device_key_valid_o = key_loaded_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) irq_o <= 1'b0;
    else         irq_o <= otp_prog_done || (kl_state_q == KL_DONE && !key_loaded_q);
  end

endmodule
