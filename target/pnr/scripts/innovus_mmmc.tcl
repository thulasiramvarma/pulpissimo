## Innovus MMMC configuration (mirrors Genus mmmc.tcl)

set FOUNDRY_ROOT "/path/to/foundry/pdk"
set STD_CELL_LIB "$FOUNDRY_ROOT/stdcells"

create_library_set -name libs_ss \
  -timing [glob $STD_CELL_LIB/ss_0v81_125c/*.lib]

create_library_set -name libs_ff \
  -timing [glob $STD_CELL_LIB/ff_0v99_m40c/*.lib]

create_library_set -name libs_tt \
  -timing [glob $STD_CELL_LIB/tt_0v9_25c/*.lib]

create_rc_corner -name rc_worst -postRoute_res 1.1 -postRoute_cap 1.1
create_rc_corner -name rc_best  -postRoute_res 0.9 -postRoute_cap 0.9
create_rc_corner -name rc_typ   -postRoute_res 1.0 -postRoute_cap 1.0

create_timing_condition -name tc_ss -library_sets {libs_ss}
create_timing_condition -name tc_ff -library_sets {libs_ff}
create_timing_condition -name tc_tt -library_sets {libs_tt}

create_delay_corner -name worst_setup -timing_condition tc_ss -rc_corner rc_worst
create_delay_corner -name best_hold   -timing_condition tc_ff -rc_corner rc_best
create_delay_corner -name typical     -timing_condition tc_tt -rc_corner rc_typ

set SYNTH_SDC [file normalize [file dirname [info script]]/../../synth/scripts]

create_constraint_mode -name func \
  -sdc_files [list \
    $SYNTH_SDC/constraints_soc.sdc \
    $SYNTH_SDC/constraints_crypto.sdc \
  ]

create_analysis_view -name setup_view -constraint_mode func -delay_corner worst_setup
create_analysis_view -name hold_view  -constraint_mode func -delay_corner best_hold

set_analysis_view -setup {setup_view} -hold {hold_view}
