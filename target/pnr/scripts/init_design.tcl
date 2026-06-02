## Innovus: Initialize Design
## Reads gate-level netlist, LEF files, and MMMC timing

set SCRIPT_DIR   [file dirname [info script]]
set SYNTH_DIR    [file normalize $SCRIPT_DIR/../../synth]
set NETLIST_DIR  $SYNTH_DIR/netlists
set REPORT_DIR   [file normalize $SCRIPT_DIR/../reports/$BLOCK]
set GDS_DIR      [file normalize $SCRIPT_DIR/../gds]
set BLOCK_DIR    [file normalize $SCRIPT_DIR/../blocks/$BLOCK]

# ---- Foundry LEF/LIB paths (EDIT for your PDK) ----
set FOUNDRY_ROOT  "/path/to/foundry/pdk"
set TECH_LEF      "$FOUNDRY_ROOT/lef/tech.lef"
set STD_CELL_LEF  "$FOUNDRY_ROOT/lef/stdcells.lef"
set SRAM_LEF      "$FOUNDRY_ROOT/lef/sram_2kx8.lef"
set PLL_LEF       "$FOUNDRY_ROOT/lef/pll.lef"
set OTP_LEF       "$FOUNDRY_ROOT/lef/otp_8kbit.lef"
set IO_LEF        "$FOUNDRY_ROOT/lef/io_cells.lef"

# ---- Read LEF ----
read_physical -lef [list $TECH_LEF $STD_CELL_LEF $SRAM_LEF $PLL_LEF $OTP_LEF $IO_LEF]

# ---- Read gate-level netlist ----
read_netlist $NETLIST_DIR/${BLOCK}_netlist.v

# ---- MMMC timing ----
read_mmmc $SCRIPT_DIR/innovus_mmmc.tcl

# ---- Initialize design ----
init_design -top [dict get {
  aes256           aes256_top
  sha256           sha256_top
  ecc521           ecc521_top
  kyber            kyber_top
  trng             trng_top
  otp_ctrl         otp_ctrl_top
  crypto_subsystem crypto_subsystem_top
  pulp_soc         pulp_soc
  pulpissimo       pulpissimo
} $BLOCK]

puts "\[init_design\] Design initialized: $BLOCK"

# ---- Proceed to floorplan ----
source $SCRIPT_DIR/floorplan.tcl
