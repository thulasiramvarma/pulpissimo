## FC Core (fc_subsystem) Standalone SDC Constraints
## FC = CV32E40P RV32IMFC+XPULP, runs on soc_clk domain (200 MHz / 5.0 ns).
## Synthesized standalone: clock enters on clk_i, no internal PLL.

# ---- Primary clock ----
create_clock -name fc_clk -period 5.0 [get_ports clk_i]

# ---- Clock uncertainty / transition ----
set_clock_uncertainty -setup 0.1  [get_clocks fc_clk]
set_clock_uncertainty -hold  0.05 [get_clocks fc_clk]
set_clock_transition   0.05        [get_clocks fc_clk]

# ---- I/O delays (10% of clock period) ----
# Constrain all data ports; carve out clk/reset below.
set_input_delay  -clock fc_clk -max 0.5 [remove_from_collection [all_inputs]  [get_ports {clk_i rst_ni}]]
set_output_delay -clock fc_clk -max 0.5 [all_outputs]

# ---- Asynchronous resets (false path) ----
set_false_path -from [get_ports rst_ni]

# ---- Async control inputs into FC (synchronized internally) ----
# Boot/fetch enable, interrupt lines, and debug request are async to fc_clk.
set_false_path -from [get_ports fetch_enable_i] -quiet
set_false_path -from [get_ports irq_i*]         -quiet
set_false_path -from [get_ports debug_req_i]    -quiet

# ---- DFT signals: don't time (connected at DFT insertion) ----
set_false_path -from [get_ports test_en_i]    -quiet
set_false_path -from [get_ports scan_cg_en_i] -quiet

# ---- Clock-gate bypass note ----
# cv32e40p_clock_gate is a direct passthrough (hw/asic/cv32e40p_clock_gate_asic.sv);
# no generated clock is created for the gated core clock.
