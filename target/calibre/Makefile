## Mentor Calibre DRC/LVS Makefile
## Usage: make drc BLOCK=<block>
##        make lvs BLOCK=<block>

BLOCK      ?= pulpissimo
CALIBRE    ?= calibre
GDS_DIR    := $(CURDIR)/../pnr/gds
REPORT_DIR := $(CURDIR)/reports/$(BLOCK)
DRC_SCRIPT := $(CURDIR)/drc/run_drc.tcl
LVS_SCRIPT := $(CURDIR)/lvs/run_lvs.tcl

.PHONY: all drc lvs drc_all lvs_all clean help

all: drc lvs

drc:
	mkdir -p $(REPORT_DIR)
	$(CALIBRE) -drc -hier $(DRC_SCRIPT) \
		-64 \
		-turbo \
		+drc.in=$(GDS_DIR)/$(BLOCK).gds \
		+drc.top=$(BLOCK) \
		+drc.results=$(REPORT_DIR)/$(BLOCK)_drc.results \
		+drc.summary=$(REPORT_DIR)/$(BLOCK)_drc.summary
	@echo "[drc] Done. Check $(REPORT_DIR)/$(BLOCK)_drc.summary"

lvs:
	mkdir -p $(REPORT_DIR)
	$(CALIBRE) -lvs -hier $(LVS_SCRIPT) \
		-64 \
		+lvs.layout=$(GDS_DIR)/$(BLOCK).gds \
		+lvs.layout_top=$(BLOCK) \
		+lvs.netlist=$(CURDIR)/../pnr/blocks/$(BLOCK)/$(BLOCK)_final.v \
		+lvs.netlist_top=$(BLOCK) \
		+lvs.report=$(REPORT_DIR)/$(BLOCK)_lvs.report \
		+lvs.summary=$(REPORT_DIR)/$(BLOCK)_lvs.summary
	@echo "[lvs] Done. Check $(REPORT_DIR)/$(BLOCK)_lvs.summary"

drc_all:
	for b in aes256 sha256 ecc521 kyber trng otp_ctrl crypto_subsystem pulp_soc pulpissimo; do \
	  $(MAKE) drc BLOCK=$$b; done

lvs_all:
	for b in aes256 sha256 ecc521 kyber trng otp_ctrl crypto_subsystem pulp_soc pulpissimo; do \
	  $(MAKE) lvs BLOCK=$$b; done

clean:
	rm -rf $(REPORT_DIR)

help:
	@echo "Targets: drc lvs drc_all lvs_all clean"
	@echo "BLOCK: aes256 sha256 ecc521 kyber trng otp_ctrl crypto_subsystem pulp_soc pulpissimo"
