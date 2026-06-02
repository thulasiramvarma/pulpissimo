## Innovus: Write Outputs for Calibre and SoC Stitch

puts "\[signoff\] Writing GDS, LEF, lib, SDF for $BLOCK..."

file mkdir $GDS_DIR
file mkdir $BLOCK_DIR

# ---- GDS (final layout for Calibre DRC/LVS and SoC stitch) ----
streamOut $GDS_DIR/${BLOCK}.gds \
  -mapFile  /path/to/foundry/pdk/streamout.map \
  -libName  $BLOCK \
  -merge    [list \
    /path/to/foundry/pdk/stdcells.gds \
    /path/to/foundry/pdk/sram_2kx8.gds \
    /path/to/foundry/pdk/pll.gds \
    /path/to/foundry/pdk/otp_8kbit.gds \
  ] \
  -units 1000

# ---- Abstract LEF (for block-level SoC stitch in Innovus top) ----
write_lef_abstract $BLOCK_DIR/${BLOCK}.lef \
  -blockages { routing }

# ---- Timing library abstract (for top-level STA) ----
do_extract_model $BLOCK_DIR/${BLOCK}_extracted.lib \
  -format lib \
  -view setup_view

# ---- SDF for gate-level simulation ----
write_sdf $BLOCK_DIR/${BLOCK}.sdf -version 3.0

# ---- Final gate-level netlist (post-route) ----
saveNetlist $BLOCK_DIR/${BLOCK}_final.v

# ---- DEF for documentation / re-import ----
defOut $BLOCK_DIR/${BLOCK}.def

puts "\[signoff\] $BLOCK complete:"
puts "  GDS  : $GDS_DIR/${BLOCK}.gds"
puts "  LEF  : $BLOCK_DIR/${BLOCK}.lef"
puts "  LIB  : $BLOCK_DIR/${BLOCK}_extracted.lib"
puts "  SDF  : $BLOCK_DIR/${BLOCK}.sdf"
