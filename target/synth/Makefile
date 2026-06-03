## Cadence Genus Synthesis Makefile
## Usage: make synth BLOCK=<block>
## Blocks: fc aes256 sha256 ecc521 kyber trng otp_ctrl crypto_subsystem pulp_soc pulpissimo
##
## First-time setup:
##   1. Install bender: cargo install bender  (or download from pulp-platform/bender)
##   2. Run bender update from repo root to check out all dependencies
##   3. make bender_sources    (generates scripts/bender_sources.tcl)
##   4. Edit scripts/setup.tcl → set FOUNDRY_ROOT to your PDK path
##   5. make synth BLOCK=fc

BLOCK         ?= pulpissimo
GENUS         ?= genus
BENDER        ?= bender
SCRIPT_DIR    := $(CURDIR)/scripts
REPORT_DIR    := $(CURDIR)/reports/$(BLOCK)
NETLIST_DIR   := $(CURDIR)/netlists

# Bender targets for ASIC synthesis
BENDER_TARGETS := -t asic -t synthesis

.PHONY: all synth bender_sources check_bender check_genus clean help

all: synth

## Check bender is available
check_bender:
	@command -v $(BENDER) >/dev/null 2>&1 || { \
	  echo ""; \
	  echo "ERROR: bender not found."; \
	  echo "  Install: cargo install bender"; \
	  echo "  Or download: https://github.com/pulp-platform/bender/releases"; \
	  echo "  Then run: bender update  (from repo root)"; \
	  echo ""; \
	  exit 1; \
	}

## Check genus is available
check_genus:
	@command -v $(GENUS) >/dev/null 2>&1 || { \
	  echo ""; \
	  echo "ERROR: genus not found. Add Cadence Genus to PATH."; \
	  echo "  e.g.  source /cadence/installs/GENUS211/tools.lnx86/bin/genus"; \
	  echo ""; \
	  exit 1; \
	}

## Generate Bender source list for Genus
## Run this once after 'bender update' in the repo root
bender_sources: check_bender
	mkdir -p $(SCRIPT_DIR)
	cd ../../ && $(BENDER) script genus $(BENDER_TARGETS) \
		--source-annotations > $(SCRIPT_DIR)/bender_sources.tcl
	@echo "[synth] Bender sources written to $(SCRIPT_DIR)/bender_sources.tcl"

## Run synthesis for BLOCK
## Requires scripts/bender_sources.tcl to exist (run 'make bender_sources' first)
synth: check_genus
	@test -f $(SCRIPT_DIR)/bender_sources.tcl || { \
	  echo ""; \
	  echo "ERROR: $(SCRIPT_DIR)/bender_sources.tcl not found."; \
	  echo "  Run: make bender_sources   (requires bender + bender update)"; \
	  echo ""; \
	  exit 1; \
	}
	mkdir -p $(REPORT_DIR) $(NETLIST_DIR)
	$(GENUS) -f $(SCRIPT_DIR)/synth_flow.tcl \
		-define BLOCK=$(BLOCK) \
		-log $(REPORT_DIR)/genus_$(BLOCK).log
	@echo "[synth] Done: $(NETLIST_DIR)/$(BLOCK)_netlist.v"

## Run synthesis for all blocks in dependency order
synth_all:
	$(MAKE) synth BLOCK=fc
	$(MAKE) synth BLOCK=aes256
	$(MAKE) synth BLOCK=sha256
	$(MAKE) synth BLOCK=ecc521
	$(MAKE) synth BLOCK=kyber
	$(MAKE) synth BLOCK=trng
	$(MAKE) synth BLOCK=otp_ctrl
	$(MAKE) synth BLOCK=crypto_subsystem
	$(MAKE) synth BLOCK=pulp_soc
	$(MAKE) synth BLOCK=pulpissimo

clean:
	rm -rf $(REPORT_DIR) $(NETLIST_DIR)/$(BLOCK)_netlist.v
	rm -rf genus.* fv/ work/ *.db

help:
	@echo ""
	@echo "Cadence Genus Synthesis — PULPissimo"
	@echo ""
	@echo "Targets:"
	@echo "  bender_sources   Generate RTL file list from Bender (run once)"
	@echo "  synth            Run Genus synthesis for BLOCK (default: pulpissimo)"
	@echo "  synth_all        Synthesize all blocks in order"
	@echo "  clean            Remove reports/netlist for BLOCK"
	@echo ""
	@echo "BLOCK options:"
	@echo "  fc               FC core (fc_subsystem, cv32e40p)"
	@echo "  aes256           AES-256 encrypt/decrypt"
	@echo "  sha256           SHA-256 hash"
	@echo "  ecc521           ECC P-521 sign/verify"
	@echo "  kyber            PQC Kyber-1024"
	@echo "  trng             True random number generator"
	@echo "  otp_ctrl         OTP controller"
	@echo "  crypto_subsystem All 6 crypto IPs integrated"
	@echo "  pulp_soc         Full SoC (no pads)"
	@echo "  pulpissimo       Chip top (with padframe)"
	@echo ""
	@echo "Variables:"
	@echo "  GENUS=<path>     Genus binary (default: genus)"
	@echo "  BENDER=<path>    Bender binary (default: bender)"
	@echo ""
	@echo "Quick start:"
	@echo "  cd /path/to/pulpissimo"
	@echo "  bender update"
	@echo "  cd target/synth"
	@echo "  make bender_sources"
	@echo "  # edit scripts/setup.tcl → FOUNDRY_ROOT"
	@echo "  make synth BLOCK=fc"
	@echo ""
