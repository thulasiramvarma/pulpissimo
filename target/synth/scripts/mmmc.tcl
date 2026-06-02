## Multi-Mode Multi-Corner (MMMC) Setup for Genus
## Three corners:
##   worst_setup : SS / 0.81V / 125°C  (setup critical path)
##   best_hold   : FF / 0.99V / -40°C  (hold critical path)
##   typical     : TT / 0.9V  / 25°C   (nominal QoR reference)

source [file dirname [info script]]/setup.tcl

# ---- Library sets ----
create_library_set -name libs_ss \
  -timing [glob $STD_CELL_LIB/ss_0v81_125c/*.lib] \
  -library [glob $STD_CELL_LIB/ss_0v81_125c/*.lib]

create_library_set -name libs_ff \
  -timing [glob $STD_CELL_LIB/ff_0v99_m40c/*.lib] \
  -library [glob $STD_CELL_LIB/ff_0v99_m40c/*.lib]

create_library_set -name libs_tt \
  -timing [glob $STD_CELL_LIB/tt_0v9_25c/*.lib] \
  -library [glob $STD_CELL_LIB/tt_0v9_25c/*.lib]

# ---- RC corners ----
create_rc_corner -name rc_worst -preRoute_res 1.0 -postRoute_res 1.1 -postRoute_cap 1.1
create_rc_corner -name rc_best  -preRoute_res 0.9 -postRoute_res 0.9 -postRoute_cap 0.9
create_rc_corner -name rc_typ   -preRoute_res 1.0 -postRoute_res 1.0 -postRoute_cap 1.0

# ---- Timing conditions ----
create_timing_condition -name tc_ss -library_sets {libs_ss}
create_timing_condition -name tc_ff -library_sets {libs_ff}
create_timing_condition -name tc_tt -library_sets {libs_tt}

# ---- Delay corners ----
create_delay_corner -name worst_setup -timing_condition tc_ss -rc_corner rc_worst
create_delay_corner -name best_hold   -timing_condition tc_ff -rc_corner rc_best
create_delay_corner -name typical     -timing_condition tc_tt -rc_corner rc_typ

# ---- Constraint modes ----
create_constraint_mode -name func \
  -sdc_files [list \
    [file dirname [info script]]/constraints_soc.sdc \
    [file dirname [info script]]/constraints_crypto.sdc \
  ]

# ---- Analysis views ----
create_analysis_view -name setup_view -constraint_mode func -delay_corner worst_setup
create_analysis_view -name hold_view  -constraint_mode func -delay_corner best_hold
create_analysis_view -name typ_view   -constraint_mode func -delay_corner typical

# ---- Set active analysis views ----
set_analysis_view \
  -setup {setup_view} \
  -hold  {hold_view}

puts "\[mmmc\] MMMC setup complete: setup=SS/0.81V/125C, hold=FF/0.99V/-40C"
