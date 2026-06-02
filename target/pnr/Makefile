## Cadence Innovus Place & Route Makefile
## Usage: make pnr BLOCK=<block>
##        make pnr_top         (full SoC hierarchical stitch)

BLOCK         ?= aes256
INNOVUS       ?= innovus
SCRIPT_DIR    := $(CURDIR)/scripts
SYNTH_DIR     := $(CURDIR)/../synth
REPORT_DIR    := $(CURDIR)/reports/$(BLOCK)
GDS_DIR       := $(CURDIR)/gds

.PHONY: all pnr pnr_top clean help

all: pnr

pnr:
	mkdir -p $(REPORT_DIR) $(GDS_DIR) $(CURDIR)/blocks/$(BLOCK)
	$(INNOVUS) -batch -files $(SCRIPT_DIR)/init_design.tcl \
		-define BLOCK=$(BLOCK) \
		-logfile $(REPORT_DIR)/innovus_$(BLOCK).log
	@echo "[pnr] Done: $(GDS_DIR)/$(BLOCK).gds"

## Full SoC stitch (all blocks must have clean GDS first)
pnr_top:
	mkdir -p $(REPORT_DIR) $(GDS_DIR) $(CURDIR)/blocks/pulpissimo
	$(INNOVUS) -batch -files $(SCRIPT_DIR)/init_design.tcl \
		-define BLOCK=pulpissimo \
		-logfile $(REPORT_DIR)/innovus_pulpissimo.log

pnr_all:
	$(MAKE) pnr BLOCK=aes256
	$(MAKE) pnr BLOCK=sha256
	$(MAKE) pnr BLOCK=ecc521
	$(MAKE) pnr BLOCK=kyber
	$(MAKE) pnr BLOCK=trng
	$(MAKE) pnr BLOCK=otp_ctrl
	$(MAKE) pnr BLOCK=crypto_subsystem
	$(MAKE) pnr BLOCK=pulp_soc
	$(MAKE) pnr_top

clean:
	rm -rf $(REPORT_DIR) $(GDS_DIR)/$(BLOCK).gds
	rm -rf innovus.* *.dbs

help:
	@echo "Targets: pnr pnr_top pnr_all clean"
	@echo "BLOCK options: aes256 sha256 ecc521 kyber trng otp_ctrl crypto_subsystem pulp_soc pulpissimo"
