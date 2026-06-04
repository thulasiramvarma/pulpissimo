## Standalone Genus Synthesis Flow — FC Subsystem only
##
## Top module : fc_subsystem (CV32E40P core, lean config)
## Run       : genus -f target/synth/scripts/synth_fc.tcl

set BLOCK       fc
set TOP_MODULE  fc_subsystem
set SCRIPT_DIR  [file dirname [info script]]
set REPORT_DIR  $SCRIPT_DIR/../reports/$BLOCK
set NETLIST_DIR $SCRIPT_DIR/../netlists

# ════════════════════════════════════════════════════════════════
# Step 1 — PDK paths  (EDIT for your process node)
# ════════════════════════════════════════════════════════════════
set FOUNDRY_ROOT  "/path/to/foundry/pdk"
set STD_CELL_LIB  "$FOUNDRY_ROOT/stdcells"
set TECH_LEF      "$FOUNDRY_ROOT/lef/tech.lef"
set CELL_LEF      "$FOUNDRY_ROOT/lef/stdcells.lef"

# Design root — two levels up from this script
set DESIGN_ROOT [file normalize $SCRIPT_DIR/../../..]
set BENDER_DIR  $DESIGN_ROOT/.bender/git/checkouts

# ════════════════════════════════════════════════════════════════
# Step 2 — Resolve bender checkout paths dynamically
# Checkout directory names contain a hash that differs per machine.
# Use glob so the script works on any machine after 'bender update'.
# ════════════════════════════════════════════════════════════════
set CV32E40P_DIR [lindex [glob $BENDER_DIR/cv32e40p-*]  0]
set PULP_SOC_DIR [lindex [glob $BENDER_DIR/pulp_soc-*]  0]

puts "\[synth_fc\] cv32e40p : $CV32E40P_DIR"
puts "\[synth_fc\] pulp_soc : $PULP_SOC_DIR"

# ════════════════════════════════════════════════════════════════
# Step 3 — Library reading  (.lib timing models)
# ════════════════════════════════════════════════════════════════
puts "\[synth_fc\] Reading timing libraries ..."
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
# Step 4 — LEF reading  (tech LEF first, then std-cell LEF)
# ════════════════════════════════════════════════════════════════
puts "\[synth_fc\] Reading LEF ..."
set_db init_lef_files [list $TECH_LEF $CELL_LEF]

# ════════════════════════════════════════════════════════════════
# Step 5 — RTL search paths
# Set the Tcl variable 'search_path' (not just set_db) because
# bender_sources.tcl captures it as search_path_initial and resets
# to it before every read_hdl block. Our package include paths must
# survive those resets.
# ════════════════════════════════════════════════════════════════
set search_path [list \
    $DESIGN_ROOT/hw/includes \
    $CV32E40P_DIR/rtl/include \
    $PULP_SOC_DIR/rtl/include \
]
set_db init_hdl_search_path $search_path
puts "\[synth_fc\] search_path_initial = $search_path"

# ════════════════════════════════════════════════════════════════
# Step 6 — Pre-read cv32e40p packages
# fc_subsystem.sv header: "module fc_subsystem import cv32e40p_apu_core_pkg::*"
# The package must be compiled BEFORE fc_subsystem.sv is parsed or
# Genus drops the parameter block entirely → elaborate "cannot find
# parameter CORE_TYPE". bender_sources.tcl reads it in the cv32e40p
# block but there is no compile-order guarantee across read_hdl calls.
# Explicit pre-read removes any ordering uncertainty.
# ════════════════════════════════════════════════════════════════
puts "\[synth_fc\] Pre-reading cv32e40p packages ..."
read_hdl -language sv \
    -define {TARGET_GENUS TARGET_SYNTHESIS} \
    [list \
        $CV32E40P_DIR/rtl/include/cv32e40p_apu_core_pkg.sv \
        $CV32E40P_DIR/rtl/include/cv32e40p_pkg.sv \
    ]

# ════════════════════════════════════════════════════════════════
# Step 7 — Read all RTL (bender-generated file list)
# ════════════════════════════════════════════════════════════════
puts "\[synth_fc\] Reading HDL sources ..."
source $SCRIPT_DIR/bender_sources.tcl

# ════════════════════════════════════════════════════════════════
# Step 8 — MMMC  (corners + analysis views)
# ════════════════════════════════════════════════════════════════
set FC_SDC $SCRIPT_DIR/constraints_fc.sdc
puts "\[synth_fc\] SDC : $FC_SDC"
source $SCRIPT_DIR/mmmc_fc.tcl
puts "\[synth_fc\] MMMC loaded"

# ════════════════════════════════════════════════════════════════
# Step 9 — Elaborate
# Do NOT use -parameters: some Genus versions reject name=value pairs
# and others reject name/value pairs. The RTL defaults for fc_subsystem
# already match the lean config we want (CV32E40P, no FPU, no HWPE).
# If you need to override a specific parameter, use the set_db form
# AFTER elaborate:
#   set_db [get_db designs $TOP_MODULE] .param:CORE_TYPE 0
# ════════════════════════════════════════════════════════════════
puts "\[synth_fc\] Elaborating $TOP_MODULE ..."
elaborate $TOP_MODULE

init_design -top $TOP_MODULE

# ════════════════════════════════════════════════════════════════
# Step 10 — syn_generic
# ════════════════════════════════════════════════════════════════
puts "\[synth_fc\] syn_generic ..."
syn_generic
file mkdir $REPORT_DIR
report_qor               > $REPORT_DIR/fc_qor_generic.rpt
report_timing -nworst 10 > $REPORT_DIR/fc_timing_generic.rpt

# ════════════════════════════════════════════════════════════════
# Step 11 — syn_map
# ════════════════════════════════════════════════════════════════
puts "\[synth_fc\] syn_map ..."
syn_map
report_qor               > $REPORT_DIR/fc_qor_map.rpt
report_timing -nworst 10 > $REPORT_DIR/fc_timing_map.rpt
report_area              > $REPORT_DIR/fc_area_map.rpt

# ════════════════════════════════════════════════════════════════
# Step 12 — syn_opt
# ════════════════════════════════════════════════════════════════
puts "\[synth_fc\] syn_opt ..."
syn_opt

# ════════════════════════════════════════════════════════════════
# Step 13 — Final reports
# ════════════════════════════════════════════════════════════════
puts "\[synth_fc\] Writing reports ..."
file mkdir $REPORT_DIR
report_qor                                > $REPORT_DIR/fc_qor_final.rpt
report_timing -nworst 20                  > $REPORT_DIR/fc_timing_final.rpt
report_area                               > $REPORT_DIR/fc_area_final.rpt
report_power                              > $REPORT_DIR/fc_power_final.rpt
report_cell                               > $REPORT_DIR/fc_cells.rpt
report_timing -check_type setup -nworst 5 > $REPORT_DIR/fc_setup_paths.rpt
report_timing -check_type hold  -nworst 5 > $REPORT_DIR/fc_hold_paths.rpt

set wns [get_db [get_timing_paths -view setup_view -nworst 1] .slack]
puts "\[synth_fc\] WNS = $wns ns  ([expr {$wns >= 0 ? {PASS} : {FAIL - check fc_setup_paths.rpt}}])"

# ════════════════════════════════════════════════════════════════
# Step 14 — Write outputs
# ════════════════════════════════════════════════════════════════
puts "\[synth_fc\] Writing netlist ..."
file mkdir $NETLIST_DIR
write_hdl              > $NETLIST_DIR/fc_netlist.v
write_sdf -version 3.0 > $NETLIST_DIR/fc.sdf
write_sdc              > $NETLIST_DIR/fc.sdc
write_db                 $NETLIST_DIR/fc.db

puts "\[synth_fc\] COMPLETE — netlist: $NETLIST_DIR/fc_netlist.v"
