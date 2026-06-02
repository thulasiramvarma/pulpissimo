## Innovus: Floorplan
## Per-block die/core area estimates based on area budget from synthesis.
## All dimensions in microns. Adjust after actual synthesis area report.

# ---- Block-specific floorplan parameters ----
# Format: {die_width die_height core_margin utilization}
array set FP_PARAMS {
  aes256           {200  200  5  0.70}
  sha256           {120  120  5  0.70}
  ecc521           {600  600  5  0.65}
  kyber            {500  500  5  0.65}
  trng             {80   80   5  0.60}
  otp_ctrl         {100  100  5  0.70}
  crypto_subsystem {900  900  5  0.65}
  pulp_soc         {1200 1200 10 0.70}
  pulpissimo       {2000 2000 20 0.65}
}

if {![info exists FP_PARAMS($BLOCK)]} {
  error "\[floorplan\] No floorplan params for: $BLOCK"
}

set fp [lindex $FP_PARAMS($BLOCK) 0]
set die_w [lindex $fp 0]
set die_h [lindex $fp 1]
set margin [lindex $fp 2]
set util   [lindex $fp 3]

# Floorplan die
floorPlan -die [list 0 0 $die_w $die_h] \
          -core [list $margin $margin [expr $die_w - $margin] [expr $die_h - $margin]] \
          -site core

puts "\[floorplan\] $BLOCK: die=${die_w}x${die_h}um, margin=${margin}um, util=${util}"

# ---- Place hard macros (block-specific) ----
if {$BLOCK eq "kyber"} {
  # NTT SRAM macro: place in top-left of core
  placeInstance i_ntt_sram [expr $margin + 5] [expr $die_h - $margin - 50] R0 -fixed
}

if {$BLOCK eq "pulpissimo"} {
  # Place crypto_subsystem block at bottom-right
  placeInstance i_soc_domain/i_crypto_subsystem 1100 100 R0 -fixed
  # Place PLL macros at top
  placeInstance i_clock_gen/i_soc_pll 200 1800 R0 -fixed
  placeInstance i_clock_gen/i_per_pll 600 1800 R0 -fixed
  # OTP macro at left edge (close to VPP/VREF pads)
  placeInstance i_soc_domain/i_crypto_subsystem/i_otp_ctrl/i_otp_macro 50 900 R0 -fixed
}

# ---- Proceed to place & route ----
source $SCRIPT_DIR/place_route.tcl
