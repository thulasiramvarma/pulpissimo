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
## Outputs land in:
##   target/synth/netlists/fc_netlist.v   (mapped gate netlist)
##   target/synth/netlists/fc.sdc         (back-annotated constraints)
##   target/synth/netlists/fc.sdf         (SDF for gate-level sim)
##   target/synth/reports/fc/             (timing / area / power)

set BLOCK      fc
set TOP_MODULE fc_subsystem
set SCRIPT_DIR [file dirname [info script]]
set REPORT_DIR $SCRIPT_DIR/../reports/$BLOCK
set NETLIST_DIR $SCRIPT_DIR/../netlists

# ───────────────────────────────────────────────────────────────
# Step 1 — PDK / library / MMMC setup
# ───────────────────────────────────────────────────────────────
source $SCRIPT_DIR/mmmc_fc.tcl
puts "\[synth_fc\] MMMC loaded: SS/0.81V/125°C (setup), FF/0.99V/-40°C (hold)"

# ───────────────────────────────────────────────────────────────
# Step 2 — Read HDL
# Source the full bender-generated list (all deps of fc_subsystem
# are included); Genus only compiles what elaborate() actually needs.
# ───────────────────────────────────────────────────────────────
puts "\[synth_fc\] Reading HDL sources from bender_sources.tcl..."
source $SCRIPT_DIR/bender_sources.tcl

# ───────────────────────────────────────────────────────────────
# Step 3 — Elaborate fc_subsystem
# Parameters match pulp_soc/rtl/pulp_soc.sv instantiation defaults.
# ───────────────────────────────────────────────────────────────
puts "\[synth_fc\] Elaborating $TOP_MODULE..."
elaborate $TOP_MODULE \
    -parameters {CORE_TYPE=0 USE_XPULP=1 USE_FPU=1 USE_ZFINX=1 \
                 USE_HWPE=1 NB_HWPE_PORTS=4 PULP_SECURE=1 \
                 N_EXT_PERF_COUNTERS=1 EVENT_ID_WIDTH=8 PER_ID_WIDTH=32 \
                 CORE_ID=0 CLUSTER_ID=31}

# Attach MMMC after elaboration
init_design -top $TOP_MODULE

# ───────────────────────────────────────────────────────────────
# Step 4 — syn_generic  (technology-independent)
# ───────────────────────────────────────────────────────────────
puts "\[synth_fc\] syn_generic..."
syn_generic

file mkdir $REPORT_DIR
report_qor    > $REPORT_DIR/fc_qor_generic.rpt
report_timing -nworst 10 > $REPORT_DIR/fc_timing_generic.rpt
puts "\[synth_fc\] Generic done — check $REPORT_DIR/fc_timing_generic.rpt for WNS"

# ───────────────────────────────────────────────────────────────
# Step 5 — syn_map  (map to standard cells)
# ───────────────────────────────────────────────────────────────
puts "\[synth_fc\] syn_map..."
syn_map

report_qor    > $REPORT_DIR/fc_qor_map.rpt
report_timing -nworst 10 > $REPORT_DIR/fc_timing_map.rpt
report_area   > $REPORT_DIR/fc_area_map.rpt
puts "\[synth_fc\] Map done — check $REPORT_DIR/fc_area_map.rpt for cell count"

# ───────────────────────────────────────────────────────────────
# Step 6 — syn_opt  (post-map optimization)
# ───────────────────────────────────────────────────────────────
puts "\[synth_fc\] syn_opt..."
syn_opt

# ───────────────────────────────────────────────────────────────
# Step 7 — Final reports
# ───────────────────────────────────────────────────────────────
puts "\[synth_fc\] Writing final reports..."
report_qor                                       > $REPORT_DIR/fc_qor_final.rpt
report_timing -nworst 20                         > $REPORT_DIR/fc_timing_final.rpt
report_area                                      > $REPORT_DIR/fc_area_final.rpt
report_power                                     > $REPORT_DIR/fc_power_final.rpt
report_cell                                      > $REPORT_DIR/fc_cells.rpt
report_timing -check_type setup -nworst 5        > $REPORT_DIR/fc_setup_paths.rpt
report_timing -check_type hold  -nworst 5        > $REPORT_DIR/fc_hold_paths.rpt

# Quick pass/fail summary to stdout
set wns [get_db [get_timing_paths -view setup_view -nworst 1] .slack]
puts "\[synth_fc\] WNS (setup) = $wns ns"
if {$wns < 0} {
    puts "\[synth_fc\] WARNING: Setup timing VIOLATED — check fc_setup_paths.rpt"
} else {
    puts "\[synth_fc\] Setup timing MET"
}

# ───────────────────────────────────────────────────────────────
# Step 8 — Write outputs
# ───────────────────────────────────────────────────────────────
puts "\[synth_fc\] Writing netlist..."
file mkdir $NETLIST_DIR

write_hdl                      > $NETLIST_DIR/fc_netlist.v
write_sdf -version 3.0         > $NETLIST_DIR/fc.sdf
write_sdc                      > $NETLIST_DIR/fc.sdc
write_db                         $NETLIST_DIR/fc.db

puts "\[synth_fc\] ─────────────────────────────────────────────"
puts "\[synth_fc\] COMPLETE"
puts "\[synth_fc\]   Netlist : $NETLIST_DIR/fc_netlist.v"
puts "\[synth_fc\]   Reports : $REPORT_DIR/"
puts "\[synth_fc\] ─────────────────────────────────────────────"
