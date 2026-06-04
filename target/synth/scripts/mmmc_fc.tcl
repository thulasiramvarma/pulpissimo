## MMMC Setup — FC Subsystem only
##
## Three corners:
##   worst_setup : SS / 0.81 V / 125 °C   ← times setup-critical paths
##   best_hold   : FF / 0.99 V / -40 °C   ← times hold-critical paths
##   typical     : TT / 0.90 V /  25 °C   ← QoR reference / power estimate
##
## Edit FOUNDRY_ROOT below to point to your PDK before running.

# ── PDK paths ───────────────────────────────────────────────────
# FOUNDRY_ROOT: top of your foundry PDK installation.
# STD_CELL_LIB: directory that contains per-corner sub-directories, e.g.:
#     $STD_CELL_LIB/ss_0v81_125c/*.lib
#     $STD_CELL_LIB/ff_0v99_m40c/*.lib
#     $STD_CELL_LIB/tt_0v9_25c/*.lib
# Adjust the corner directory names to match your PDK.

set FOUNDRY_ROOT   "/path/to/foundry/pdk"
set STD_CELL_LIB   "$FOUNDRY_ROOT/stdcells"

# Design root (two levels up from this script)
set SCRIPT_DIR [file dirname [info script]]
set DESIGN_ROOT [file normalize $SCRIPT_DIR/../../..]

# ── HDL search paths needed by Genus elaboration ────────────────
set_db init_hdl_search_path [list \
    $DESIGN_ROOT/hw/includes \
]

# ── Library sets ────────────────────────────────────────────────
create_library_set -name libs_ss \
    -timing  [glob $STD_CELL_LIB/ss_0v81_125c/*.lib] \
    -library [glob $STD_CELL_LIB/ss_0v81_125c/*.lib]

create_library_set -name libs_ff \
    -timing  [glob $STD_CELL_LIB/ff_0v99_m40c/*.lib] \
    -library [glob $STD_CELL_LIB/ff_0v99_m40c/*.lib]

create_library_set -name libs_tt \
    -timing  [glob $STD_CELL_LIB/tt_0v9_25c/*.lib] \
    -library [glob $STD_CELL_LIB/tt_0v9_25c/*.lib]

# ── RC corners ──────────────────────────────────────────────────
create_rc_corner -name rc_worst \
    -preRoute_res 1.0 -postRoute_res 1.1 -postRoute_cap 1.1

create_rc_corner -name rc_best \
    -preRoute_res 0.9 -postRoute_res 0.9 -postRoute_cap 0.9

create_rc_corner -name rc_typ \
    -preRoute_res 1.0 -postRoute_res 1.0 -postRoute_cap 1.0

# ── Timing conditions ───────────────────────────────────────────
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

# ── Constraint mode (FC SDC only) ───────────────────────────────
create_constraint_mode -name func \
    -sdc_files [list $SCRIPT_DIR/constraints_fc.sdc]

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

puts "\[mmmc_fc\] Libraries : $STD_CELL_LIB"
puts "\[mmmc_fc\] Corners   : SS/0.81V/125°C (setup)  FF/0.99V/-40°C (hold)"
puts "\[mmmc_fc\] SDC       : $SCRIPT_DIR/constraints_fc.sdc"
