## Calibre DRC Runset
## Edit FOUNDRY_RULES to point to your process DRC deck.

# ---- Foundry DRC rules (EDIT for your PDK) ----
set FOUNDRY_RULES "/path/to/foundry/pdk/drc/calibre_drc.rules"

# ---- Include the foundry deck ----
INCLUDE $FOUNDRY_RULES

# ---- DRC options ----
DRC MAXIMUM RESULTS 5000
DRC MAXIMUM VERTEX 4096

# ---- Layer map (GDS layer numbers → foundry layer names) ----
# EDIT: replace with foundry-specific layer mapping
LAYER MAP
  M1    = 30
  M2    = 31
  M3    = 32
  M4    = 33
  M5    = 34
  M6    = 35
  M7    = 36
  M8    = 37
  M9    = 38
  VIA12 = 41
  VIA23 = 42
  CONT  = 20
  NDIFF = 1
  PDIFF = 2
  POLY  = 10
END LAYER MAP

# ---- Additional checks for crypto subsystem ----
# OTP VPP/VREF pads must be isolated from digital supply
CONNECTIVITY CHECK {
  NETS { VPP VREF }
  EXCLUDE_FROM { VDD VSS }
}
