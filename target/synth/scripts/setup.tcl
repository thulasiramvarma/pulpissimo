## Genus Synthesis Setup
## Sets library paths, tool version checks, and global variables.
## Edit LIBRARY_PATH to point to your foundry PDK.

# ---- Foundry PDK paths (EDIT THESE for your process node) ----
set FOUNDRY_ROOT   "/path/to/foundry/pdk"           ;# e.g. /proj/gf22/pdk
set STD_CELL_LIB   "$FOUNDRY_ROOT/stdcells"
set SRAM_LIB       "$FOUNDRY_ROOT/sram"
set IO_LIB         "$FOUNDRY_ROOT/io_cells"
set PLL_LIB        "$FOUNDRY_ROOT/pll"
set OTP_LIB        "$FOUNDRY_ROOT/otp"

# ---- Design root ----
set DESIGN_ROOT    [file normalize [file dirname [info script]]/../../..]
set NETLIST_DIR    [file dirname [info script]]/../netlists
set REPORT_DIR     [file dirname [info script]]/../reports/$BLOCK

# ---- Technology libraries ----
# SS corner: setup worst case
set LIB_SS  "$STD_CELL_LIB/tt0p9v25c/*.lib"

# ---- Search paths ----
set_db init_hdl_search_path [list \
  $DESIGN_ROOT/hw/includes \
  $DESIGN_ROOT/hw/crypto_subsystem \
  $DESIGN_ROOT/hw/asic \
]

puts "\[setup\] DESIGN_ROOT = $DESIGN_ROOT"
puts "\[setup\] BLOCK       = $BLOCK"
