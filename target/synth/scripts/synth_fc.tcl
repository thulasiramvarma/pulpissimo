## Standalone Genus Synthesis Flow — FC Subsystem only
##
## What this synthesizes:
##   Top module : fc_subsystem  (pulp_soc rtl/fc/fc_subsystem.sv)
##   Core       : CV32E40P RV32IMFC + XPULP + FPU (fpnew)
##   Interfaces : XBAR_TCDM_BUS (L2 data/instr/hwpe), APB (EU + HWPE)
##   Excludes   : everything above fc_subsystem (pulp_soc, soc_domain, padframe)
##
## How to run:
##   genus -f target/synth/scripts/synth_fc.tcl
##
## This file owns ALL library (.lib/.lef) reading and RTL reading.
## mmmc_fc.tcl owns ONLY the MMMC constraint structure (corners/views).

set BLOCK       fc
set TOP_MODULE  fc_subsystem
set SCRIPT_DIR  [file dirname [info script]]
set REPORT_DIR  $SCRIPT_DIR/../reports/$BLOCK
set NETLIST_DIR $SCRIPT_DIR/../netlists

# ════════════════════════════════════════════════════════════════
# Step 1 — Foundry PDK paths   (EDIT THESE for your process node)
# ════════════════════════════════════════════════════════════════
# STD_CELL_LIB must contain per-corner sub-directories of .lib files:
#     $STD_CELL_LIB/ss_0v81_125c/*.lib
#     $STD_CELL_LIB/ff_0v99_m40c/*.lib
#     $STD_CELL_LIB/tt_0v9_25c/*.lib
# LEF_DIR must contain the technology + std-cell .lef files.
set FOUNDRY_ROOT   "/path/to/foundry/pdk"
set STD_CELL_LIB   "$FOUNDRY_ROOT/stdcells"
set LEF_DIR        "$FOUNDRY_ROOT/lef"

# Design root (two levels up from this script)
set DESIGN_ROOT    [file normalize $SCRIPT_DIR/../../..]

# ════════════════════════════════════════════════════════════════
# Step 2 — Library reading  (.lib timing libraries)
# ════════════════════════════════════════════════════════════════
# Library sets are the only PDK-dependent objects mmmc_fc.tcl references
# by name (libs_ss / libs_ff / libs_tt). They are created here so all
# .lib invocation lives in one place.
puts "\[synth_fc\] Reading timing libraries from $STD_CELL_LIB ..."

create_library_set -name libs_ss \
    -timing  [glob $STD_CELL_LIB/ss_0v81_125c/*.lib] \
    -library [glob $STD_CELL_LIB/ss_0v81_125c/*.lib]

create_library_set -name libs_ff \
    -timing  [glob $STD_CELL_LIB/ff_0v99_m40c/*.lib] \
    -library [glob $STD_CELL_LIB/ff_0v99_m40c/*.lib]

create_library_set -name libs_tt \
    -timing  [glob $STD_CELL_LIB/tt_0v9_25c/*.lib] \
    -library [glob $STD_CELL_LIB/tt_0v9_25c/*.lib]

# ════════════════════════════════════════════════════════════════
# Step 3 — Physical library reading  (.lef for area/congestion-aware syn)
# ════════════════════════════════════════════════════════════════
# Optional but recommended for physically-aware synthesis. Comment out
# if you only want a logical (wireload) run.
puts "\[synth_fc\] Reading LEF from $LEF_DIR ..."
set_db init_lef_files [glob $LEF_DIR/*.lef] -quiet

# ════════════════════════════════════════════════════════════════
# Step 4 — RTL search paths + read HDL
# ════════════════════════════════════════════════════════════════
set_db init_hdl_search_path [list \
    $DESIGN_ROOT/hw/includes \
]

puts "\[synth_fc\] Reading HDL sources from bender_sources.tcl ..."
source $SCRIPT_DIR/bender_sources.tcl

# ════════════════════════════════════════════════════════════════
# Step 5 — SDC file path  (consumed by mmmc_fc.tcl)
# ════════════════════════════════════════════════════════════════
# Declared here so all file references are owned by this script.
# mmmc_fc.tcl reads $FC_SDC when creating the constraint mode.
set FC_SDC $SCRIPT_DIR/constraints_fc.sdc
puts "\[synth_fc\] SDC : $FC_SDC"

# ════════════════════════════════════════════════════════════════
# Step 6 — MMMC constraint structure  (corners / views)
# ════════════════════════════════════════════════════════════════
# mmmc_fc.tcl references library sets (Step 2) and $FC_SDC (Step 5).
source $SCRIPT_DIR/mmmc_fc.tcl
puts "\[synth_fc\] MMMC loaded: SS/0.81V/125°C (setup), FF/0.99V/-40°C (hold)"

# ════════════════════════════════════════════════════════════════
# Step 7 — Elaborate fc_subsystem
# Parameters match pulp_soc/rtl/pulp_soc.sv instantiation defaults.
# ════════════════════════════════════════════════════════════════
puts "\[synth_fc\] Elaborating $TOP_MODULE ..."
elaborate $TOP_MODULE \
    -parameters {CORE_TYPE=0 USE_XPULP=1 USE_FPU=1 USE_ZFINX=1 \
                 USE_HWPE=1 NB_HWPE_PORTS=4 PULP_SECURE=1 \
                 N_EXT_PERF_COUNTERS=1 EVENT_ID_WIDTH=8 PER_ID_WIDTH=32 \
                 CORE_ID=0 CLUSTER_ID=31}

# Attach MMMC to the elaborated design
init_design -top $TOP_MODULE

# ════════════════════════════════════════════════════════════════
# Step 8 — syn_generic  (technology-independent)
# ════════════════════════════════════════════════════════════════
puts "\[synth_fc\] syn_generic ..."
syn_generic

file mkdir $REPORT_DIR
report_qor                > $REPORT_DIR/fc_qor_generic.rpt
report_timing -nworst 10  > $REPORT_DIR/fc_timing_generic.rpt
puts "\[synth_fc\] Generic done — check $REPORT_DIR/fc_timing_generic.rpt for WNS"

# ════════════════════════════════════════════════════════════════
# Step 9 — syn_map  (map to standard cells)
# ════════════════════════════════════════════════════════════════
puts "\[synth_fc\] syn_map ..."
syn_map

report_qor                > $REPORT_DIR/fc_qor_map.rpt
report_timing -nworst 10  > $REPORT_DIR/fc_timing_map.rpt
report_area               > $REPORT_DIR/fc_area_map.rpt
puts "\[synth_fc\] Map done — check $REPORT_DIR/fc_area_map.rpt for cell count"

# ════════════════════════════════════════════════════════════════
# Step 10 — syn_opt  (post-map optimization)
# ════════════════════════════════════════════════════════════════
puts "\[synth_fc\] syn_opt ..."
syn_opt

# ════════════════════════════════════════════════════════════════
# Step 11 — Final reports
# ════════════════════════════════════════════════════════════════
puts "\[synth_fc\] Writing final reports ..."
report_qor                                > $REPORT_DIR/fc_qor_final.rpt
report_timing -nworst 20                  > $REPORT_DIR/fc_timing_final.rpt
report_area                               > $REPORT_DIR/fc_area_final.rpt
report_power                              > $REPORT_DIR/fc_power_final.rpt
report_cell                               > $REPORT_DIR/fc_cells.rpt
report_timing -check_type setup -nworst 5 > $REPORT_DIR/fc_setup_paths.rpt
report_timing -check_type hold  -nworst 5 > $REPORT_DIR/fc_hold_paths.rpt

# Quick pass/fail summary to stdout
set wns [get_db [get_timing_paths -view setup_view -nworst 1] .slack]
puts "\[synth_fc\] WNS (setup) = $wns ns"
if {$wns < 0} {
    puts "\[synth_fc\] WARNING: Setup timing VIOLATED — check fc_setup_paths.rpt"
} else {
    puts "\[synth_fc\] Setup timing MET"
}

# ════════════════════════════════════════════════════════════════
# Step 12 — Write outputs
# ════════════════════════════════════════════════════════════════
puts "\[synth_fc\] Writing netlist ..."
file mkdir $NETLIST_DIR

write_hdl              > $NETLIST_DIR/fc_netlist.v
write_sdf -version 3.0 > $NETLIST_DIR/fc.sdf
write_sdc              > $NETLIST_DIR/fc.sdc
write_db                 $NETLIST_DIR/fc.db

puts "\[synth_fc\] ─────────────────────────────────────────────"
puts "\[synth_fc\] COMPLETE"
puts "\[synth_fc\]   Netlist : $NETLIST_DIR/fc_netlist.v"
puts "\[synth_fc\]   Reports : $REPORT_DIR/"
puts "\[synth_fc\] ─────────────────────────────────────────────"
