## Cadence Genus Synthesis Makefile
## Usage: make synth BLOCK=<block>
## Blocks: aes256 sha256 ecc521 kyber trng otp_ctrl crypto_subsystem pulp_soc pulpissimo
##
## Script generation via Bender:
##   bender script genus -t asic -t synthesis > scripts/bender_sources.tcl
## Then run: make synth BLOCK=pulpissimo

BLOCK         ?= pulpissimo
GENUS         ?= genus
BENDER        ?= bender
SCRIPT_DIR    := $(CURDIR)/scripts
REPORT_DIR    := $(CURDIR)/reports/$(BLOCK)
NETLIST_DIR   := $(CURDIR)/netlists

# Bender targets for ASIC synthesis
BENDER_TARGETS := -t asic -t synthesis

.PHONY: all synth bender_sources clean help

all: synth

## Generate Bender source list for Genus
bender_sources:
	mkdir -p $(SCRIPT_DIR)
	cd ../../ && $(BENDER) script genus $(BENDER_TARGETS) \
		--source-annotations > $(SCRIPT_DIR)/bender_sources.tcl
	@echo "[synth] Bender sources written to $(SCRIPT_DIR)/bender_sources.tcl"

## Run synthesis for BLOCK
synth: bender_sources
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
	@echo "Targets: synth bender_sources synth_all clean"
	@echo "BLOCK options: fc aes256 sha256 ecc521 kyber trng otp_ctrl crypto_subsystem pulp_soc pulpissimo"
	@echo "GENUS: path to genus binary (default: genus)"
