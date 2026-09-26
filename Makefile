# ============================================================================
# Project : RISC-V Network Telemetry SoC
# Script  : Makefile  (root delegator)
# Desc    : Single entry point for the fw0 flow. Never holds build logic —
#           spec §8.1 delegates to sw/Makefile (compiler) and sim/Makefile
#           (VCS/Verdi). "Never one enormous Makefile; never modifying RTL
#           from the SW build."
#
#           make all   =  firmware -> images -> snapshot -> compile -> run -> gate
#
#           Layout (decision D6):
#             sw/build/                       firmware + memory images
#             build/snapshots/p2_soc/         VeeR snapshot, project-local
#             build/sim/fw0/                  VCS work dir, simv, logs, FSDB
# ============================================================================

REPO := $(CURDIR)

.PHONY: all firmware inspect mem dis veer-config rtl sim verdi wave clean help
.DEFAULT_GOAL := all

all: firmware mem veer-config rtl sim
	@echo "[ROOT] fw0 flow complete — both tokens gated in 'make sim'"

help:
	@echo "Root targets (spec §8.1):"
	@echo "  firmware     -> sw/ build/firmware.elf"
	@echo "  inspect      -> sw/ ELF gates G1-G7, G11"
	@echo "  mem          -> sw/ imem.mem + dmem.mem + firmware.ihex (G8-G10, G12)"
	@echo "  veer-config  -> build/snapshots/p2_soc   (D6, project-local)"
	@echo "  rtl          -> VCS compile"
	@echo "  sim          -> run + gate on P2_TB2_RESULT and AHB_RW_MONITOR"
	@echo "  verdi        -> open FSDB with run/fw_wave.rc"
	@echo "  wave         -> print the verdi command instead of launching"
	@echo "  clean        -> remove build/sim and sw/build"

# ---- software (spec §8.2) ----
firmware inspect mem dis clean-sw:
	$(MAKE) -C sw $(if $(filter clean-sw,$@),clean,$@)

# ---- simulation (spec §8.3) ----
veer-config rtl sim verdi wave:
	$(MAKE) -C sim $@

clean:
	$(MAKE) -C sw clean
	$(MAKE) -C sim clean
	rm -rf $(REPO)/build/snapshots
	@echo "[ROOT] cleaned sw/build and build/"
