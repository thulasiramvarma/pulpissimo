## Cadence Genus Synthesis Makefile
## Usage: make synth BLOCK=<block>
## Blocks: fc aes256 sha256 ecc521 kyber trng otp_ctrl crypto_subsystem pulp_soc pulpissimo
##
## Manual bender installation (one-time, on your EDA machine):
##   Option A — precompiled binary (recommended):
##     wget https://github.com/pulp-platform/bender/releases/download/v0.28.1/bender-0.28.1-x86_64-linux-gnu-ubuntu22.04.tar.gz
##     tar xzf bender-*.tar.gz
##     sudo mv bender /usr/local/bin/
##
##   Option B — build from source (requires Rust):
##     cargo install bender
##
## First-time setup after bender is installed:
##   1. cd /path/to/pulpissimo && bender update
##   2. cd target/synth && make bender_sources
##   3. Edit scripts/setup.tcl → set FOUNDRY_ROOT to your PDK
##   4. make synth BLOCK=fc

BLOCK         ?= pulpissimo
GENUS         ?= genus
BENDER        ?= bender
SCRIPT_DIR    := $(CURDIR)/scripts
REPORT_DIR    := $(CURDIR)/reports/$(BLOCK)
NETLIST_DIR   := $(CURDIR)/netlists

# Bender targets for ASIC synthesis
BENDER_TARGETS := -t asic -t synthesis

.PHONY: all synth bender_sources synth_all clean help

all: synth

## Generate Bender source list for Genus.
## Run once after 'bender update' in the repo root.
bender_sources:
	mkdir -p $(SCRIPT_DIR)
	cd ../../ && $(BENDER) script genus $(BENDER_TARGETS) \
		> $(SCRIPT_DIR)/bender_sources.tcl
	@# Fix bender 0.28.x genus template bugs: '{{' '}}' braces and 'set X = "..."'
	@sed -i -e 's/{{/{/g' -e 's/}}/}/g' \
		-e 's/^set ROOT = "/set ROOT "/' \
		$(SCRIPT_DIR)/bender_sources.tcl
	@echo "[synth] Bender sources written to $(SCRIPT_DIR)/bender_sources.tcl"

## Run synthesis for BLOCK
synth:
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
	@echo "  synth            Run Genus for BLOCK (default: pulpissimo)"
	@echo "  synth_all        Synthesize all blocks in order"
	@echo "  clean            Remove reports/netlist for BLOCK"
	@echo ""
	@echo "BLOCK options:"
	@echo "  fc               FC core (fc_subsystem / cv32e40p)"
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
