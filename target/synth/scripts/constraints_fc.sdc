## SDC Constraints — FC Subsystem (fc_subsystem) standalone
##
## Top module  : fc_subsystem
## Core        : CV32E40P  RV32IMFC + XPULP  (CORE_TYPE=0)
## FPU         : fpnew  USE_FPU=1  USE_ZFINX=1
## Clock       : single domain — soc_clk enters on clk_i
## Target freq : 200 MHz  →  period = 5.0 ns
##
## Port reference: pulp_soc rtl/fc/fc_subsystem.sv
##
##   Inputs  : clk_i, rst_ni, test_en_i
##             l2_data_master.* (TCDM), l2_instr_master.* (TCDM)
##             l2_hwpe_master[0:3].* (TCDM x4)
##             apb_slave_eu.*, apb_slave_hwpe.*
##             fetch_en_i, boot_addr_i[31:0], debug_req_i
##             event_fifo_valid_i, event_fifo_data_i[7:0]
##             interrupts_i[31:0]
##   Outputs : event_fifo_fulln_o, hwpe_events_o[1:0], supervisor_mode_o

# ════════════════════════════════════════════════════════════════
# 1. Primary clock
# ════════════════════════════════════════════════════════════════
# clk_i is the SoC clock.  In context this is soc_clk from the PLL,
# but for standalone FC synthesis we define it as the primary clock.
create_clock -name fc_clk -period 5.0 [get_ports clk_i]

# ════════════════════════════════════════════════════════════════
# 2. Clock quality  (conservative pre-CTS values)
# ════════════════════════════════════════════════════════════════
# Uncertainty covers jitter + clock-tree skew before CTS.
# Reduce to ~0.05 / 0.02 after CTS and back-annotate.
set_clock_uncertainty -setup 0.10 [get_clocks fc_clk]
set_clock_uncertainty -hold  0.05 [get_clocks fc_clk]

# Slew at clock port (drive from pad / buffer assumed clean).
set_clock_transition  0.05 [get_clocks fc_clk]

# ════════════════════════════════════════════════════════════════
# 3. Generated clocks (clock gates inside fc_subsystem)
# ════════════════════════════════════════════════════════════════
# cv32e40p has an internal clock gate (core_clock_en / clock_gate_i).
# The gated clock is a divided/gated version of fc_clk — declare it
# as a generated clock so Genus times hold paths correctly.
# The exact pin name below is inside cv32e40p_top → cv32e40p_sleep_unit.
# Use -quiet so the script doesn't abort if pin name differs in this version.
create_generated_clock -name core_gclk \
    -source [get_ports clk_i] \
    -divide_by 1 \
    -master_clock fc_clk \
    [get_pins -hier -filter "name=~*sleep_unit*clk_o" -quiet] \
    -quiet

# ════════════════════════════════════════════════════════════════
# 4. I/O delays  (10 % of period = 0.5 ns)
# ════════════════════════════════════════════════════════════════
# All registered data ports relative to fc_clk.
# clk_i and rst_ni are excluded explicitly.

set _all_data_in  [remove_from_collection [all_inputs]  [get_ports {clk_i rst_ni}]]
set _all_data_out [all_outputs]

set_input_delay  -clock fc_clk -max 0.5 $_all_data_in
set_input_delay  -clock fc_clk -min 0.1 $_all_data_in
set_output_delay -clock fc_clk -max 0.5 $_all_data_out
set_output_delay -clock fc_clk -min 0.1 $_all_data_out

# ════════════════════════════════════════════════════════════════
# 5. False paths
# ════════════════════════════════════════════════════════════════

# Asynchronous reset — not timed
set_false_path -from [get_ports rst_ni]

# Async control inputs — synchronized inside FC before use
set_false_path -from [get_ports fetch_en_i]         -quiet
set_false_path -from [get_ports debug_req_i]        -quiet
set_false_path -from [get_ports interrupts_i*]      -quiet
set_false_path -from [get_ports event_fifo_valid_i] -quiet
set_false_path -from [get_ports event_fifo_data_i*] -quiet

# boot_addr_i — static configuration strapped at power-on, constant at runtime
set_false_path -from [get_ports boot_addr_i*] -quiet

# DFT test enable — not active during functional mode
set_false_path -from [get_ports test_en_i] -quiet

# ════════════════════════════════════════════════════════════════
# 6. Multi-cycle paths
# ════════════════════════════════════════════════════════════════

# fpnew FMA (fused multiply-add) — 2-cycle execution unit.
# Genus must NOT try to close this in a single cycle.
set_multicycle_path 2 -setup \
    -through [get_pins -hier -filter "name=~*fma*" -quiet] -quiet
set_multicycle_path 1 -hold \
    -through [get_pins -hier -filter "name=~*fma*" -quiet] -quiet

# Integer divider inside CV32E40P — iterative, takes up to 32 cycles.
# SDC only needs to guard the combinational datapath per iteration.
set_multicycle_path 2 -setup \
    -through [get_pins -hier -filter "name=~*div*" -quiet] -quiet
set_multicycle_path 1 -hold \
    -through [get_pins -hier -filter "name=~*div*" -quiet] -quiet

# FPU div/sqrt MVP — iterative, multi-cycle by architecture.
set_multicycle_path 2 -setup \
    -through [get_pins -hier -filter "name=~*fdsu*" -quiet] -quiet
set_multicycle_path 1 -hold \
    -through [get_pins -hier -filter "name=~*fdsu*" -quiet] -quiet

# ════════════════════════════════════════════════════════════════
# 7. Drive / load  (for I/O optimization, adjust to actual pad spec)
# ════════════════════════════════════════════════════════════════
# Assume 50 fF load on all outputs (typical routing estimate).
set_load 0.05 [all_outputs]

# Assume outputs are driven by a standard BUF_X4-equivalent (0.5 ns max).
set_driving_cell -lib_cell BUF_X4 -pin Z [all_inputs] -quiet
