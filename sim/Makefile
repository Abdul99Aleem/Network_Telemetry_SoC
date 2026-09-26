# ============================================================================
# Project : RISC-V Network Telemetry SoC
# Script  : sim/Makefile
# Desc    : VCS / Verdi side of the fw0 flow (spec §8.3, plan §5.1 S5/S6/S9).
#
#           Decision D6: the VeeR snapshot is PROJECT-LOCAL
#           (build/snapshots/p2_soc). /tmp/opencode/veer_p2 is root-owned and
#           unwritable (plan finding N4), so run/p2_veer_soc_run.f's hardcoded
#           path is unusable — sim/filelist.f takes $FW_SNAP from the env.
#
#           Targets:
#             veer-config   generate build/snapshots/p2_soc   (S5)
#             rtl           VCS compile                       (S6)
#             sim           build image + run + gate          (S11, plan G13)
#             verdi         open the FSDB with run/fw_wave.rc
#             clean
# ============================================================================

REPO    := $(abspath $(CURDIR)/..)
SW_DIR  := $(REPO)/sw
SW_BUILD:= $(SW_DIR)/build
SNAP    := $(REPO)/build/snapshots/p2_soc
WORK    := $(REPO)/build/sim/fw0

RV_ROOT ?= $(REPO)/core/Cores-VeeR-EL2

# ---- Synopsys tool environment (spec §8.3; mirrors run/p2_full_flow.csh) ----
# VCS_HOME/VERDI_HOME must be *exported*, not just used to build PATH: the
# vcs wrapper resolves its own scripts (vcsMsgReport etc.) from $VCS_HOME/bin.
VCS_HOME  ?= /home/student/snps_tools_target/vcs/U-2023.03
VERDI_HOME?= /home/student/snps_tools_target/verdi/U-2023.03-SP1
export VCS_HOME
export VERDI_HOME
export PATH := $(VCS_HOME)/bin:$(VERDI_HOME)/bin:$(PATH)
export SNPSLMD_LICENSE_FILE ?= 27021@14.139.1.126

# ---- filelist environment (sim/filelist.f expands these) ----
export FW_PROJ := $(REPO)
export FW_SNAP := $(SNAP)
export RV_ROOT

FILELIST  := $(REPO)/sim/filelist.f
VCS_FLAGS := -full64 -sverilog -debug_access+all -kdb \
             +define+RV_OPENSOURCE +error+500 -timescale=1ns/10ps

.PHONY: all veer-config rtl sim verdi wave clean help
.DEFAULT_GOAL := all

all: sim

help:
	@echo "sim/ targets:"
	@echo "  veer-config  -> $(SNAP)   (D6, project-local)"
	@echo "  rtl          -> VCS compile into $(WORK)"
	@echo "  sim          -> image + run + gate on BOTH tokens"
	@echo "  verdi        -> open FW_FSDB with run/fw_wave.rc"
	@echo "  clean        -> remove $(WORK)"

# ---------------------------------------------------------------------------
# S5 — VeeR snapshot, project-local (decision D6)
# ---------------------------------------------------------------------------
veer-config: $(SNAP)/common_defines.vh

$(SNAP)/common_defines.vh:
	@mkdir -p $(SNAP)
	@echo "[SIM] veer-config -> $(SNAP)  (target=default_ahb snapshot=p2_soc reset_vec=0)"
	env BUILD_PATH=$(SNAP) RV_ROOT=$(RV_ROOT) \
	    $(RV_ROOT)/configs/veer.config -target=default_ahb -snapshot=p2_soc \
	    -set=reset_vec=0x00000000 > $(REPO)/build/veer_config.log 2>&1 || \
	    { echo "[SIM] FAIL veer-config:"; tail -20 $(REPO)/build/veer_config.log; exit 1; }
	@test -f $(SNAP)/el2_param.vh || { echo "[SIM] FAIL: el2_param.vh not generated"; exit 1; }
	@echo "[SIM] PASS snapshot: $$(ls $(SNAP) | tr '\n' ' ')"

# ---------------------------------------------------------------------------
# S6 — VCS compile
# ---------------------------------------------------------------------------
rtl: veer-config
	@mkdir -p $(WORK)
	@echo "[SIM] vcs -f $(FILELIST)"
	@echo "[SIM]     FW_SNAP=$(FW_SNAP)"
	cd $(WORK) && vcs $(VCS_FLAGS) -f $(FILELIST) -l $(WORK)/compile.log || \
	    { echo "[SIM] FAIL compile — see $(WORK)/compile.log"; exit 1; }
	@echo "[SIM] PASS compile"

# ---------------------------------------------------------------------------
# S11 — run fw0 and gate on BOTH terminal tokens (plan §5.2)
#
# NOTE ON THE IMAGE FILENAME
#   tb_veer_p2_soc passes .IMEM_HEX("p2_prog.hex") straight down to
#   ahb_sram, which $readmemh's it in its own `initial` block. A runtime
#   plusarg cannot feed an elaboration-time parameter (spec D9 proved this),
#   so the PLUSARG-owned loader (spec S7/S7b/S8) is the only correct way to
#   make the name dynamic — and that change removes ahb_sram's `initial`,
#   which would break the sibling session's committed Phase-3 flow while it
#   is in flight. Until it lands, the flow copies sw/build/imem.mem to the
#   name the bench expects. The image bytes are identical; only the name is
#   a stand-in. Tracked as a known deviation in the fw0 record.
# ---------------------------------------------------------------------------
FW_HEX := $(WORK)/p2_prog.hex

sim: rtl
	@test -s $(SW_BUILD)/imem.mem || \
	    { echo "[SIM] FAIL: $(SW_BUILD)/imem.mem missing — run 'make -C sw mem'"; exit 1; }
	@cp $(SW_BUILD)/imem.mem $(FW_HEX)
	@echo "[SIM] image: sw/build/imem.mem ($$(wc -c < $(SW_BUILD)/imem.mem) bytes) -> $(FW_HEX)"
	cd $(WORK) && ./simv -l $(WORK)/sim.log
	@echo "[SIM] ---- gate: plan §5.2, both tokens required ----"
	@grep -q "P2_TB2_RESULT: PASS" $(WORK)/sim.log || \
	    { echo "[SIM] FAIL: no 'P2_TB2_RESULT: PASS'"; \
	      grep -n "P2_TB2_RESULT" $(WORK)/sim.log; exit 1; }
	@echo "[SIM] PASS  P2_TB2_RESULT: PASS   (spec §22 fw0 — pre-existing monitor, unmodified)"
	@grep -q "AHB_RW_MONITOR: PASS" $(WORK)/sim.log || \
	    { echo "[SIM] FAIL: no 'AHB_RW_MONITOR: PASS'"; \
	      grep -n "AHB_RW_MONITOR\|AHB_CYCLES\|FAIL reason" $(WORK)/sim.log; exit 1; }
	@echo "[SIM] PASS  AHB_RW_MONITOR: PASS   (plan §5.2 — read/write proof)"
	@grep -n "AHB_CYCLES\|AHB_RW_MONITOR\|P2_TB2_RESULT" $(WORK)/sim.log
	@echo "[SIM] G13  firmware.ihex never reached the sim dir:"
	@if ls $(WORK)/*.ihex >/dev/null 2>&1; then \
	    echo "[SIM] FAIL G13: Intel HEX found in $(WORK)"; exit 1; \
	 else echo "[SIM] PASS  no *.ihex in $(WORK)"; fi
	@echo "[SIM] FSDB  $(WORK)/p2_veer_soc.fsdb"
	@echo "[SIM] DONE"

# ---------------------------------------------------------------------------
# Verdi (plan §5.3 — the waveform half of the evidence)
# ---------------------------------------------------------------------------
verdi: sim
	@echo "[SIM] opening Verdi (DISPLAY=$${DISPLAY:-unset}) on $(WORK)/p2_veer_soc.fsdb"
	cd $(WORK) && verdi -ssf p2_veer_soc.fsdb -dbdir simv.daidir \
	    -sswr $(REPO)/run/fw_wave.rc &

wave:
	@echo "cd $(WORK); setenv DISPLAY :0"
	@echo "verdi -ssf p2_veer_soc.fsdb -dbdir simv.daidir -sswr $(REPO)/run/fw_wave.rc &"

clean:
	rm -rf $(WORK)
	@echo "[SIM] cleaned $(WORK)"
