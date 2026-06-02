## PULPissimo SoC SDC Constraints
## Three clock domains: soc_clk (200MHz), per_clk (100MHz), slow_clk (32.768kHz)

# ---- Primary clocks ----
create_clock -name soc_clk  -period 5.0  [get_ports soc_clk_o]
create_clock -name per_clk  -period 10.0 [get_ports per_clk_o]
create_clock -name slow_clk -period 30517.6 [get_ports slow_clk_o]
create_clock -name ref_clk  -period 20.0 [get_ports ref_clk_i]

# ---- Clock uncertainty ----
set_clock_uncertainty -setup 0.1 [get_clocks soc_clk]
set_clock_uncertainty -setup 0.1 [get_clocks per_clk]
set_clock_uncertainty -hold  0.05 [get_clocks soc_clk]
set_clock_uncertainty -hold  0.05 [get_clocks per_clk]

# ---- Clock transition ----
set_clock_transition 0.05 [get_clocks soc_clk]
set_clock_transition 0.08 [get_clocks per_clk]

# ---- Input/output delays (10% of clock period) ----
set_input_delay  -clock soc_clk -max 0.5 [all_inputs]
set_output_delay -clock soc_clk -max 0.5 [all_outputs]

# ---- Asynchronous CDC: false paths across clock domain crossings ----
set_false_path -from [get_clocks soc_clk]  -to [get_clocks slow_clk]
set_false_path -from [get_clocks slow_clk] -to [get_clocks soc_clk]
set_false_path -from [get_clocks per_clk]  -to [get_clocks slow_clk]
set_false_path -from [get_clocks slow_clk] -to [get_clocks per_clk]

# ---- JTAG clock (TCK, asynchronous to all other clocks) ----
create_clock -name jtag_tck -period 100.0 [get_ports jtag_tck_i]
set_false_path -from [get_clocks jtag_tck] -to [get_clocks soc_clk]
set_false_path -from [get_clocks soc_clk]  -to [get_clocks jtag_tck]
set_false_path -from [get_clocks jtag_tck] -to [get_clocks per_clk]

# ---- DFT signals: don't time (connect during DFT insertion) ----
set_false_path -from [get_ports dft_test_en_i]
set_false_path -from [get_ports dft_cg_enable_i]

# ---- PLL output clocks (generated) ----
create_generated_clock -name soc_pll_clk \
  -source [get_ports ref_clk_i] \
  -multiply_by 4 \
  [get_pins i_clock_gen/i_soc_pll/clk_o]

create_generated_clock -name per_pll_clk \
  -source [get_ports ref_clk_i] \
  -multiply_by 2 \
  [get_pins i_clock_gen/i_per_pll/clk_o]

# ---- Reset (asynchronous, false path for timing) ----
set_false_path -from [get_ports pad_reset_n]
