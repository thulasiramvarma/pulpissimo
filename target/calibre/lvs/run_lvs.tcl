## Calibre LVS Runset
## Edit FOUNDRY_RULES to point to your process LVS deck.

# ---- Foundry LVS rules (EDIT for your PDK) ----
set FOUNDRY_RULES "/path/to/foundry/pdk/lvs/calibre_lvs.rules"

# ---- Include the foundry deck ----
INCLUDE $FOUNDRY_RULES

# ---- LVS options ----
LVS REPORT MAXIMUM 5000
LVS POWER NAME VDD
LVS GROUND NAME VSS

# ---- Spice mapping for SRAM, PLL, OTP macros ----
# These must match the hard macro CDL/SPICE netlists from foundry
LVS RECOGNIZE GATES NONE

# Explicit SPICE for hard macros
SPICE NETLIST "/path/to/foundry/pdk/cdl/sram_2kx8.cdl"
SPICE NETLIST "/path/to/foundry/pdk/cdl/pll.cdl"
SPICE NETLIST "/path/to/foundry/pdk/cdl/otp_8kbit.cdl"

# ---- OTP supply isolation check ----
# VPP and VREF must connect to dedicated nets (not VDD/VSS)
LVS REPORT POWER NETS { VPP VREF VDD VSS }

# ---- Port ordering ----
LVS PORT SWAP ORDER NONE
