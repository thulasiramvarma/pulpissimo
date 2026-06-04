## MMMC Constraints — FC Subsystem only
##
## This file contains ONLY the multi-mode multi-corner structure:
##   RC corners → timing conditions → delay corners → constraint mode → views.
##
## It does NOT read any libraries or RTL. The library sets it references
## (libs_ss / libs_ff / libs_tt) and all .lib/.lef/RTL reading are owned by
## synth_fc.tcl, which sources this file AFTER creating those library sets.
##
## Corners:
##   worst_setup : SS / 0.81 V / 125 °C   ← times setup-critical paths
##   best_hold   : FF / 0.99 V / -40 °C   ← times hold-critical paths
##   typical     : TT / 0.90 V /  25 °C   ← QoR reference / power estimate

set MMMC_SCRIPT_DIR [file dirname [info script]]

# ── RC corners ──────────────────────────────────────────────────
create_rc_corner -name rc_worst \
    -preRoute_res 1.0 -postRoute_res 1.1 -postRoute_cap 1.1

create_rc_corner -name rc_best \
    -preRoute_res 0.9 -postRoute_res 0.9 -postRoute_cap 0.9

create_rc_corner -name rc_typ \
    -preRoute_res 1.0 -postRoute_res 1.0 -postRoute_cap 1.0

# ── Timing conditions  (reference library sets from synth_fc.tcl) ─
create_timing_condition -name tc_ss -library_sets {libs_ss}
create_timing_condition -name tc_ff -library_sets {libs_ff}
create_timing_condition -name tc_tt -library_sets {libs_tt}

# ── Delay corners ───────────────────────────────────────────────
create_delay_corner -name worst_setup \
    -timing_condition tc_ss -rc_corner rc_worst

create_delay_corner -name best_hold \
    -timing_condition tc_ff -rc_corner rc_best

create_delay_corner -name typical \
    -timing_condition tc_tt -rc_corner rc_typ

# ── Constraint mode  (FC SDC only) ──────────────────────────────
create_constraint_mode -name func \
    -sdc_files [list $MMMC_SCRIPT_DIR/constraints_fc.sdc]

# ── Analysis views ──────────────────────────────────────────────
create_analysis_view -name setup_view \
    -constraint_mode func -delay_corner worst_setup

create_analysis_view -name hold_view \
    -constraint_mode func -delay_corner best_hold

create_analysis_view -name typ_view \
    -constraint_mode func -delay_corner typical

# ── Activate setup + hold views ─────────────────────────────────
set_analysis_view \
    -setup {setup_view} \
    -hold  {hold_view}

puts "\[mmmc_fc\] MMMC structure ready: setup=SS/0.81V/125°C  hold=FF/0.99V/-40°C"
puts "\[mmmc_fc\] SDC: $MMMC_SCRIPT_DIR/constraints_fc.sdc"
