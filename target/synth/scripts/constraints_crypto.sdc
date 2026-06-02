## Crypto Subsystem SDC Constraints
## All crypto IPs run on soc_clk (200 MHz, 5ns period).
## Multicycle paths reflect actual pipeline depths; false paths for physical sources.

# ---- AES-256: 14-round pipeline, MCP=2 (2-cycle round function) ----
set_multicycle_path 2 -setup \
  -from [get_cells -hierarchical *i_aes_core*] \
  -to   [get_cells -hierarchical *i_aes_core*]
set_multicycle_path 1 -hold \
  -from [get_cells -hierarchical *i_aes_core*] \
  -to   [get_cells -hierarchical *i_aes_core*]

# Optionally restrict to round registers only (more precise)
set_multicycle_path 2 -setup \
  -from [get_cells -hierarchical *aes256*round_q*] \
  -to   [get_cells -hierarchical *aes256*round_q*]

# ---- ECC-521 scalar multiplier: MCP=8 (8-cycle per iteration) ----
set_multicycle_path 8 -setup \
  -from [get_cells -hierarchical *i_ecc_core*] \
  -to   [get_cells -hierarchical *i_ecc_core*]
set_multicycle_path 7 -hold \
  -from [get_cells -hierarchical *i_ecc_core*] \
  -to   [get_cells -hierarchical *i_ecc_core*]

# ECC output registers (sig_r_o, sig_s_o) — captured after long compute
set_multicycle_path 8 -setup \
  -from [get_cells -hierarchical *ecc521*cycle_cnt_q*] \
  -to   [get_cells -hierarchical *ecc521*sig_r_o*]
set_multicycle_path 8 -setup \
  -from [get_cells -hierarchical *ecc521*cycle_cnt_q*] \
  -to   [get_cells -hierarchical *ecc521*sig_s_o*]

# ---- PQC Kyber-1024 NTT butterfly: MCP=4 ----
set_multicycle_path 4 -setup \
  -from [get_cells -hierarchical *i_ntt*] \
  -to   [get_cells -hierarchical *i_ntt*]
set_multicycle_path 3 -hold \
  -from [get_cells -hierarchical *i_ntt*] \
  -to   [get_cells -hierarchical *i_ntt*]

# NTT SRAM write → read path (SRAM macro timing closure via .lib)
set_multicycle_path 4 -setup \
  -from [get_cells -hierarchical *ntt_sram*] \
  -to   [get_cells -hierarchical *kyber_ntt*]

# ---- TRNG ring oscillators: false path (physical entropy source) ----
# RO cells are inserted by PnR; no logical timing analysis needed
set_false_path -from [get_cells -hierarchical *trng*lfsr_q*]
set_false_path -from [get_cells -hierarchical *trng*ro_out*]
set_false_path -to   [get_cells -hierarchical *trng*sample_q*]

# ---- OTP: false path (analog macro, timing via .lib characterisation) ----
set_false_path -from [get_cells -hierarchical *otp_ctrl*]
set_false_path -to   [get_cells -hierarchical *otp_ctrl*i_otp_macro*]

# ---- Private key bus: false path (OTP output, not in normal timing cone) ----
# Key is loaded once at boot; no cycle-accurate timing needed
set_false_path -from [get_cells -hierarchical *otp_ctrl*root_key_q*]
set_false_path -from [get_cells -hierarchical *otp_ctrl*dev_key_q*]

# ---- SHA-256: 64-round compress, behavioral — no MCP needed if unrolled ----
# If pipelined, add MCP here:
# set_multicycle_path 2 -setup -from [get_cells -hierarchical *sha256*hash_q*]

# ---- Output delay for IRQ lines (single-cycle delivery to event unit) ----
set_output_delay -clock soc_clk -max 0.3 [get_ports irq_o*]
