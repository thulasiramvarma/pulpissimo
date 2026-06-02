## Innovus: Place → CTS → Route → Filler

puts "\[pnr\] === Placement ==="

# Power rings and stripes
addRing -spacing 1 -width 2 -nets {VDD VSS} -type core_rings \
  -center 1 -layer_top M8 -layer_bottom M8 -layer_left M9 -layer_right M9

# Standard cell placement
place_design -floorplan

# Placement optimization
optDesign -preCTS -hold -setup

report_timing -nworst 10 > $REPORT_DIR/${BLOCK}_timing_place.rpt
report_area               > $REPORT_DIR/${BLOCK}_area_place.rpt

puts "\[pnr\] === Clock Tree Synthesis ==="

# CTS
create_clock_tree_spec -output $BLOCK_DIR/cts.spec
clock_design
optDesign -postCTS -hold

report_clock_timing -type skew   > $REPORT_DIR/${BLOCK}_cts_skew.rpt
report_timing -nworst 10         > $REPORT_DIR/${BLOCK}_timing_cts.rpt

puts "\[pnr\] === Routing ==="

# Route
routeDesign -globalDetail

# Post-route optimization
optDesign -postRoute -hold -setup

report_timing -nworst 20 > $REPORT_DIR/${BLOCK}_timing_route.rpt

puts "\[pnr\] === Filler Insertion ==="

# Add filler cells
addFiller -cell [list FILL1 FILL2 FILL4 FILL8 FILL16 FILL32 FILL64] -prefix FILLER

# Antenna fix (if violations exist)
addAntennaFix

puts "\[pnr\] === Signoff Checks ==="

# DRC check (internal Innovus DRC)
verify_drc -limit 1000 -report $REPORT_DIR/${BLOCK}_innovus_drc.rpt

# Connectivity check
verify_connectivity -error 10 -warning 100

# Timing signoff
report_timing -nworst 50 -check_type setup > $REPORT_DIR/${BLOCK}_signoff_setup.rpt
report_timing -nworst 50 -check_type hold  > $REPORT_DIR/${BLOCK}_signoff_hold.rpt

# ---- Proceed to write outputs ----
source $SCRIPT_DIR/signoff.tcl
