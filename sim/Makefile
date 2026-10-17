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
SW_BUILD?= $(SW_DIR)/build
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

# ---------------------------------------------------------------------------
# DECISION D1 (widened) — per-variant monitor expectations
#
# tb_ahb_cycle_monitor gates on activity MINIMA and expected ERROR counts. The
# frozen fw0 values below are the defaults, so a run that states nothing
# reproduces today's behaviour exactly. Every variant target overrides them.
#
# Phase 0 evidence for why this is per-variant rather than one frozen set:
#   - DCCM probe: P2_TB2_RESULT PASS, but AHB_RW_MONITOR FAIL on
#     dmem_rd=9 < 16 and dmem_wr=14 < 16 — a short image, not a defect.
#   - ICCM probe: def=1, bus_err=2 — deliberate unmapped access, which the old
#     hard-coded `== 0` equalities could not express.
#
# Lowering a minimum does not disable the check: the monitor still fails when a
# minimum is not met. See the negative-control run in
# doc/Phase0_ICCM_DCCM_Access_Spike_Record.md §6.
# ---------------------------------------------------------------------------
EXPECT_DEF    ?= 0
EXPECT_BUSERR ?= 0
MIN_IMEM_RD   ?= 8
MIN_DMEM_RD   ?= 16
MIN_DMEM_WR   ?= 16

# Upper bound on writes into IMEM. Default 0 keeps the original canary strict
# for every image that has no business writing code memory (fw0, the probes).
# Only the Phase-3 memory variant, whose IMEM test deliberately writes scratch
# ABOVE __imem_image_end, declares a different bound.
MAX_IMEM_WR   ?= 0

MON_EXPECT_PLUSARGS := \
    +expect_def=$(EXPECT_DEF) \
    +expect_buserr=$(EXPECT_BUSERR) \
    +min_imem_rd=$(MIN_IMEM_RD) \
    +min_dmem_rd=$(MIN_DMEM_RD) \
    +min_dmem_wr=$(MIN_DMEM_WR) \
    +max_imem_wr=$(MAX_IMEM_WR)

# Runtime testbench options, appended per target.
#   +expect_uart  require and verify the serial transcript (suite only; fw0
#                 emits none, so requiring one would fail a proven regression)
#   +uart_corrupt deliberately corrupt the first captured byte, to prove the
#                 UART gate rejects a wrong payload
#   +wave         emit an FSDB; omitted by default so routine runs stay light
TB_PLUSARGS ?=

.PHONY: all veer-config rtl sim run verdi wave clean help \
        test-fw0 test-spike-dccm test-spike-iccm test-suite test-suite-negative \
        test-suite-uart-corrupt test-memory test-memory-negative \
        test-bus test-bus-wrong-expect test-uart test-uart-corrupt
.DEFAULT_GOAL := all

all: sim

help:
	@echo "sim/ targets:"
	@echo "  veer-config  -> $(SNAP)   (D6, project-local)"
	@echo "  rtl          -> VCS compile into $(WORK)"
	@echo "  run          -> re-run simv against $(SW_BUILD)/imem.mem (no recompile)"
	@echo "  sim          -> image + run + gate on BOTH tokens"
	@echo "  test-fw0        -> frozen memory probe (frozen thresholds)"
	@echo "  test-spike-dccm -> DCCM access probe (declares its own minima)"
	@echo "  test-spike-iccm -> ICCM probe (declares expect_def=1 expect_buserr=2)"
	@echo "  test-uart       -> C-driven UART tests (Phase 4)"
	@echo "  test-uart-corrupt-> UART corruption negative control"
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

sim: rtl run

# Re-run the already-elaborated simv against $(SW_BUILD)/imem.mem. Split out
# from `sim` so per-area test variants can swap the image and run without a
# full VCS recompile — $readmemh runs in an `initial` block at t=0, so the same
# binary picks up whatever p2_prog.hex is present. This is decision D2 in
# doc/Complete_Updated_C_Peripheral_and_Memory_Test_Suite_Plan.md §6.1.
run:
	@test -x $(WORK)/simv || \
	    { echo "[SIM] FAIL: no simv in $(WORK) — run 'make -C sim rtl'"; exit 1; }
	@test -s $(SW_BUILD)/imem.mem || \
	    { echo "[SIM] FAIL: $(SW_BUILD)/imem.mem missing — run 'make -C sw mem'"; exit 1; }
	@cp $(SW_BUILD)/imem.mem $(FW_HEX)
	@echo "[SIM] image: $(SW_BUILD)/imem.mem ($$(wc -c < $(SW_BUILD)/imem.mem) bytes) -> $(FW_HEX)"
	@echo "[SIM] expect: $(MON_EXPECT_PLUSARGS) $(TB_PLUSARGS)"
	cd $(WORK) && ./simv $(MON_EXPECT_PLUSARGS) $(TB_PLUSARGS) -l $(WORK)/sim.log
	@echo "[SIM] ---- gate: plan §5.2, both tokens required ----"
	@case "$(TB_PLUSARGS)" in *+bus_watch*) \
	    grep -q "BUS_CHECK_RESULT: PASS" $(WORK)/sim.log || \
	    { echo "[SIM] FAIL: BUS_CHECK_RESULT is not PASS"; \
	      grep -n "BUS_CHECK\|DEFAULT slave" $(WORK)/sim.log; exit 1; }; \
	    echo "[SIM] PASS  BUS_CHECK_RESULT: PASS   (fabric returned AHB ERROR at the declared address)"; \
	    grep -n "BUS_CHECK\|DEFAULT slave" $(WORK)/sim.log;; \
	 *) \
	    if [ "$(NEG_FAIL)" = "1" ]; then \
	      grep -q "P2_TB2_RESULT: FAIL" $(WORK)/sim.log || \
	      { echo "[SIM] FAIL: expected a deliberate FAIL token, none found"; exit 1; }; \
	      echo "[SIM] PASS  deliberate P2_TB2_RESULT: FAIL observed (NEG_FAIL=1)"; \
	    else \
	      grep -q "P2_TB2_RESULT: PASS" $(WORK)/sim.log || \
	      { echo "[SIM] FAIL: no 'P2_TB2_RESULT: PASS'"; \
	        grep -n "P2_TB2_RESULT" $(WORK)/sim.log; exit 1; }; \
	      echo "[SIM] PASS  P2_TB2_RESULT: PASS   (spec §22 fw0 — pre-existing monitor, unmodified)"; \
	    fi; \
	    grep -q "AHB_RW_MONITOR: PASS" $(WORK)/sim.log || \
	    { echo "[SIM] FAIL: no 'AHB_RW_MONITOR: PASS'"; \
	      grep -n "AHB_RW_MONITOR\|AHB_CYCLES\|FAIL reason" $(WORK)/sim.log; exit 1; }; \
	    echo "[SIM] PASS  AHB_RW_MONITOR: PASS   (plan §5.2 — read/write proof)";; \
	esac
	@# Informational only. `|| true` matters: on a +bus_watch run none of these
	@# tokens exist, and a grep with no matches would otherwise become the
	@# recipe's exit status and fail a run whose BUS_CHECK actually passed.
	@grep -n "AHB_CYCLES\|AHB_RW_MONITOR\|P2_TB2_RESULT" $(WORK)/sim.log || true
	@# When the target asked for a transcript, its absence is a failure.
	@# A missing UART_CHECK_RESULT means the bench never reached the check,
	@# which must not be mistaken for a pass.
	@# Terminal-condition dispatch. +bus_watch means the CPU cannot complete the
	@# unmapped access, so it never writes the mailbox and the mailbox tokens do
	@# not exist for this variant; its verdict is BUS_CHECK_RESULT instead.
	@case "$(TB_PLUSARGS)" in \
	 *+bus_watch*) \
	    grep -q "BUS_CHECK_RESULT: PASS" $(WORK)/sim.log || \
	    { echo "[SIM] FAIL: BUS_CHECK_RESULT is not PASS"; \
	      grep -n "BUS_CHECK" $(WORK)/sim.log; exit 1; };; \
	 *+expect_uart*) \
	    if [ "$(NEG_FAIL)" = "1" ]; then \
	      grep -q "P2_TB2_RESULT: FAIL" $(WORK)/sim.log || \
	      { echo "[SIM] FAIL: expected a deliberate failure and got none"; exit 1; }; \
	      echo "[SIM] PASS  deliberate failure observed (NEG_FAIL=1)"; \
	    else \
	      grep -q "UART_CHECK_RESULT: PASS" $(WORK)/sim.log || \
	      { echo "[SIM] FAIL: UART_CHECK_RESULT is not PASS"; \
	        grep -n "UART_CHECK" $(WORK)/sim.log; exit 1; }; \
	    fi;; \
	 *) ;; esac
	@echo "[SIM] G13  firmware.ihex never reached the sim dir:"
	@if ls $(WORK)/*.ihex >/dev/null 2>&1; then \
	    echo "[SIM] FAIL G13: Intel HEX found in $(WORK)"; exit 1; \
	 else echo "[SIM] PASS  no *.ihex in $(WORK)"; fi
	@case "$(TB_PLUSARGS)" in *+wave*) echo "[SIM] FSDB  $(WORK)/p2_veer_soc.fsdb (+wave)";; \
	  *) rm -f $(WORK)/p2_veer_soc.fsdb; \
	     echo "[SIM] FSDB  none (pass TB_PLUSARGS=+wave to enable)";; esac
	@echo "[SIM] DONE"

# ---------------------------------------------------------------------------
# Per-variant test targets (decision D1). Each declares its image AND its
# expected monitor activity minima / error counts explicitly.
# ---------------------------------------------------------------------------

# fw0 — frozen memory probe. Established counts (Phase 0 record §7):
#   imem_rd=2393 dmem_rd=366 dmem_wr=164 def=0 bus_err=0
test-fw0:
	@$(MAKE) run

# DCCM probe — PASSES P2_TB2_RESULT but makes far fewer DMEM accesses than
# fw0, so it declares its own (lower, still enforced) activity minima.
test-spike-dccm:
	@rm -rf $(SW_DIR)/build/spike_dccm
	@$(MAKE) -C $(SW_DIR) BUILD=build/spike_dccm MAIN_SRC=probes/spike.c \
	    EXTRA_CFLAGS=-DSPIKE_ONLY_DCCM all >/dev/null
	@$(MAKE) run \
	    SW_BUILD=$(SW_DIR)/build/spike_dccm \
	    MIN_IMEM_RD=8 MIN_DMEM_RD=8 MIN_DMEM_WR=8 \
	    EXPECT_DEF=0 EXPECT_BUSERR=0

# ICCM probe — deliberately provokes the default ERROR slave (one store, one
# load, both HRESP). Declares the exact expected error counts, so this is a
# precise assertion rather than a tolerated failure.
test-spike-iccm:
	@rm -rf $(SW_DIR)/build/spike_iccm
	@$(MAKE) -C $(SW_DIR) BUILD=build/spike_iccm MAIN_SRC=probes/spike.c \
	    EXTRA_CFLAGS=-DSPIKE_ONLY_ICCM all >/dev/null
	@$(MAKE) run \
	    SW_BUILD=$(SW_DIR)/build/spike_iccm \
	    MIN_IMEM_RD=8 MIN_DMEM_RD=1 MIN_DMEM_WR=1 \
	    EXPECT_DEF=1 EXPECT_BUSERR=2

# C test suite (Phase 2) — must PASS. Image built with MAIN_SRC=tests/test_main.c.
# +expect_uart: the suite reports over the serial line, so the transcript is
# decoded and cross-checked against the DMEM table. Builds its own image so the
# target is self-contained and does not depend on a stale build directory.
test-suite:
	@rm -rf $(SW_DIR)/build/suite
	@$(MAKE) -C $(SW_DIR) BUILD=build/suite MAIN_SRC=tests/test_main.c \
	    EXTRA_CFLAGS="-DTEST_SELECT_ALL $(MEM_WINDOW_FLAGS)" all >/dev/null
	@$(MAKE) run \
	    SW_BUILD=$(SW_DIR)/build/suite \
	    MIN_IMEM_RD=8 MIN_DMEM_RD=8 MIN_DMEM_WR=8 \
	    EXPECT_DEF=0 EXPECT_BUSERR=0 MAX_IMEM_WR=$(MEM_MAX_IMEM_WR) \
	    TB_PLUSARGS=+expect_uart

# Negative control — same image plus -DTEST_NEGATIVE_CONTROL, so the suite must
# FAIL. Proves the assertion machinery and the mailbox FAIL path both work.
test-suite-negative:
	@rm -rf $(SW_DIR)/build/suite_neg
	@$(MAKE) -C $(SW_DIR) BUILD=build/suite_neg MAIN_SRC=tests/test_main.c \
	    EXTRA_CFLAGS="-DTEST_NEGATIVE_CONTROL $(MEM_WINDOW_FLAGS)" all >/dev/null
	@$(MAKE) run \
	    SW_BUILD=$(SW_DIR)/build/suite_neg \
	    MIN_IMEM_RD=8 MIN_DMEM_RD=8 MIN_DMEM_WR=8 \
	    EXPECT_DEF=0 EXPECT_BUSERR=0 MAX_IMEM_WR=$(MEM_MAX_IMEM_WR) \
	    TB_PLUSARGS=+expect_uart

# Negative control for the UART gate itself: +uart_corrupt rewrites the first
# captured byte, so UART_CHECK must FAIL and the run must exit non-zero.
test-suite-uart-corrupt:
	@rm -rf $(SW_DIR)/build/suite
	@$(MAKE) -C $(SW_DIR) BUILD=build/suite MAIN_SRC=tests/test_main.c \
	    EXTRA_CFLAGS="-DTEST_SELECT_ALL $(MEM_WINDOW_FLAGS)" all >/dev/null
	@$(MAKE) run \
	    SW_BUILD=$(SW_DIR)/build/suite \
	    MIN_IMEM_RD=8 MIN_DMEM_RD=8 MIN_DMEM_WR=8 \
	    EXPECT_DEF=0 EXPECT_BUSERR=0 MAX_IMEM_WR=$(MEM_MAX_IMEM_WR) \
	    TB_PLUSARGS="+expect_uart +uart_corrupt"

# Phase 3: memory tests. Windows are deliberately bounded for the first run so
# the safe ranges and the runtime are measured before committing to a full sweep.
# Activity minima are declared explicitly per decision D1 and are NOT relaxed:
# an under-specified run fails, which is what makes the PASS meaningful.
MEM_WINDOW_FLAGS ?= -DMEMTEST_WINDOW_DMEM=512 -DMEMTEST_WINDOW_IMEM=256 \
                   -DMEMTEST_WINDOW_DCCM=512 -DMEMTEST_STRIDE=64
MEM_BUILD       ?= $(SW_DIR)/build/mem
# IMEM scratch writes are intentional here and bounded above __imem_image_end
# by the linker; the monitor still caps them so a runaway cannot go unnoticed.
MEM_MAX_IMEM_WR ?= 256

test-memory:
	@rm -rf $(SW_DIR)/build/mem
	@$(MAKE) -C $(SW_DIR) BUILD=build/mem MAIN_SRC=tests/test_main.c \
	    EXTRA_CFLAGS="-DTEST_SELECT_MEMORY $(MEM_WINDOW_FLAGS)" all >/dev/null
	@$(MAKE) run SW_BUILD=$(MEM_BUILD) \
	    MIN_IMEM_RD=8 MIN_DMEM_RD=8 MIN_DMEM_WR=8 \
	    EXPECT_DEF=0 EXPECT_BUSERR=0 MAX_IMEM_WR=$(MEM_MAX_IMEM_WR) \
	    TB_PLUSARGS=+expect_uart

# Phase 3: bus tests. These deliberately provoke three AHB ERROR responses per
# unmapped address (three probes each), so the monitor expectations are
# non-zero and must be stated, not assumed. expect_def_addrs pins WHICH
# addresses produced them -- a correct count from the wrong address fails.
BUS_BUILD ?= $(SW_DIR)/build/bus

test-bus:
	@rm -rf $(SW_DIR)/build/bus
	@$(MAKE) -C $(SW_DIR) BUILD=build/bus MAIN_SRC=tests/test_main.c \
	    EXTRA_CFLAGS="-DTEST_SELECT_BUS" all >/dev/null
	@$(MAKE) run SW_BUILD=$(BUS_BUILD) \
	    MIN_IMEM_RD=8 MIN_DMEM_RD=8 MIN_DMEM_WR=8 \
	    EXPECT_DEF=1 EXPECT_BUSERR=1 \
	    TB_PLUSARGS="+bus_watch +expect_def_addr=10001000"

# Phase 4: C-driven UART tests. Exercises UART-01..10 through the integrated
# VeeR path (VeeR -> AHB -> AXI -> UART -> uart_tx). The testbench decodes
# the serial line and cross-checks against the DMEM result table.
# Activity minima are relaxed vs fw0 because the UART-only image is shorter,
# but uart_wr must be non-zero (the whole point is to exercise the UART).
UART_BUILD ?= $(SW_DIR)/build/uart

test-uart:
	@rm -rf $(SW_DIR)/build/uart
	@$(MAKE) -C $(SW_DIR) BUILD=build/uart MAIN_SRC=tests/test_main.c \
	    EXTRA_CFLAGS="-DTEST_SELECT_UART" all >/dev/null
	@$(MAKE) run SW_BUILD=$(UART_BUILD) \
	    MIN_IMEM_RD=8 MIN_DMEM_RD=8 MIN_DMEM_WR=8 \
	    EXPECT_DEF=0 EXPECT_BUSERR=0 \
	    TB_PLUSARGS=+expect_uart

# Negative control for UART gate: same image as test-uart, but with a
# corrupted serial transcript. Proves the UART_CHECK gate rejects wrong output
# even when the firmware itself completes.
test-uart-corrupt:
	@rm -rf $(SW_DIR)/build/uart
	@$(MAKE) -C $(SW_DIR) BUILD=build/uart MAIN_SRC=tests/test_main.c \
	    EXTRA_CFLAGS="-DTEST_SELECT_UART" all >/dev/null
	@$(MAKE) run SW_BUILD=$(UART_BUILD) \
	    MIN_IMEM_RD=8 MIN_DMEM_RD=8 MIN_DMEM_WR=8 \
	    EXPECT_DEF=0 EXPECT_BUSERR=0 \
	    TB_PLUSARGS="+expect_uart +uart_corrupt"

# Negative control: proves the DMEM safety guard rejects windows that overlap
# the result table or the stack, and still accepts the real window. Without
# this, a regression that loosened memtest_region_safe() would let a
# destructive pattern overwrite the reporting machinery and still report PASS.
#
# This is a genuine negative control: the image is built with
# -DMEMTEST_GUARD_BROKEN, which makes memtest_region_safe() accept every window,
# so the guard test's "must refuse" assertions MUST fail. The suite therefore
# reports FAIL, and the target requires that FAIL (NEG_FAIL=1) — a guard test
# that could not detect a loosened guard would exit 0 here, which is the bug
# this target exists to catch.
test-memory-negative:
	@rm -rf $(SW_DIR)/build/mem_neg
	@$(MAKE) -C $(SW_DIR) BUILD=build/mem_neg MAIN_SRC=tests/test_main.c \
	    EXTRA_CFLAGS="-DTEST_SELECT_MEMORY -DMEMTEST_GUARD_BROKEN=1 \
	                   $(MEM_WINDOW_FLAGS)" all >/dev/null
	@$(MAKE) run SW_BUILD=$(SW_DIR)/build/mem_neg \
	    MIN_IMEM_RD=8 MIN_DMEM_RD=8 MIN_DMEM_WR=8 \
	    EXPECT_DEF=0 EXPECT_BUSERR=0 MAX_IMEM_WR=$(MEM_MAX_IMEM_WR) \
	    TB_PLUSARGS=+expect_uart \
	    NEG_FAIL=1

# Negative control: declare the WRONG expected error counts for the bus tests.
# The monitor must reject the mismatch even though the firmware did exactly what
# it was asked to do.
test-bus-wrong-expect:
	@$(MAKE) run SW_BUILD=$(BUS_BUILD) \
	    MIN_IMEM_RD=8 MIN_DMEM_RD=8 MIN_DMEM_WR=8 \
	    EXPECT_DEF=4 EXPECT_BUSERR=1 \
	    TB_PLUSARGS="+bus_watch +expect_def_addr=10001000"

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
