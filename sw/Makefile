# ============================================================================
# Project : RISC-V Network Telemetry SoC
# Script  : sw/Makefile
# Desc    : Compiler flags, link, and image generation for the p2_soc
#           firmware.  Frozen variables per spec §8.2; delegation is
#           root Makefile -> sw/Makefile (this file) + sim/Makefile.
#
#           Spec : doc/RISC_V_SW_Build_and_Simulation_Image_Architecture_
#                  Specification.md  §6, §7, §8.2, §16 L1-L4
#           Plan : doc/Firmware_Build_and_AHB_RW_Verification_Plan.md §4
#
#           Amendment A1 (frozen review): spec §8.2 lists only
#           -nostartfiles.  That still passes -lgcc/-lc, but as archives
#           nothing is pulled until a symbol is referenced — so fw0 links
#           today.  The first 64-bit helper (__udivdi3) or memcpy use then
#           aborts with `libgcc.a(div.o): file class ELFCLASS64 incompatible
#           with ELFCLASS32` (verified on this toolchain: /opt/riscv has no
#           rv32 multilib, only ELF64).  -nostdlib turns that into a plain
#           `undefined reference to __udivdi3` at the offending source.
#           Never add -lgcc.
# ============================================================================

CROSS_COMPILE ?= riscv64-unknown-elf-
# recipes below use bash process substitution / 16# radix arithmetic
SHELL := /bin/bash

CC      := $(CROSS_COMPILE)gcc
OBJCOPY := $(CROSS_COMPILE)objcopy
OBJDUMP := $(CROSS_COMPILE)objdump
READELF := $(CROSS_COMPILE)readelf
NM      := $(CROSS_COMPILE)nm
SIZE    := $(CROSS_COMPILE)size

MARCH   := rv32imc_zicsr_zifencei
MABI    := ilp32
OPT     ?= -O0 -g
BUILD   ?= build

# Which translation unit supplies main(). Default is the fw0 memory probe
# (doc/Firmware_Build_and_AHB_RW_Verification_Plan.md). Phase 0 of
# doc/Complete_Updated_C_Peripheral_and_Memory_Test_Suite_Plan.md overrides
# this to build the ICCM/DCCM access spike into its own BUILD dir without
# disturbing the fw0 artifacts, e.g.
#     make -C sw BUILD=build/spike MAIN_SRC=probes/spike.c all
# Later phases use the same hook for -DTEST_SELECT_* variants (§6.1).
MAIN_SRC ?= src/main.c

# Extra flags appended to CFLAGS. Used by the Phase 0 spike to select a single
# probe region (-DSPIKE_ONLY_DCCM / -DSPIKE_ONLY_ICCM): a faulting access traps
# and startup.S parks forever, so ICCM and DCCM cannot share one run. Also
# carries -DTEST_SELECT_* / -DTEST_NEGATIVE_CONTROL for the suite (Phase 1).
EXTRA_CFLAGS ?=

# Which sources are compiled in.
#
#   MAIN_SRC defaults to src/main.c  -> the fw0 build: src/*.c only.
#   MAIN_SRC in tests/                -> the suite build: src/lib.c + tests/*.
#                                         src/main.c is dropped, because it is
#                                         fw0's own main() and would collide.
#   MAIN_SRC in probes/               -> a standalone probe: src/lib.c + it.
#
# probes/ is never globbed, so a probe is only ever built when named
# explicitly. Every variant lands in its own BUILD dir and therefore cannot
# disturb the proven fw0 artifacts in sw/build/.
SRCS_BASE := $(sort $(wildcard src/*.c))

ifneq ($(findstring tests/,$(MAIN_SRC)),)
# Single translation unit on purpose. tests/test_main.c #includes the area
# files (t_bus.c, t_mem.c, memtest_core.c) so that TEST_SELECT_* decides what
# gets compiled. Globbing tests/*.c as well compiled every one of them a
# SECOND time as a separate object: the static test functions and their
# TEST_CASE entries were duplicated, and the registry reported 16 cases for 8
# tests. Only the including file is built.
    SRCS := $(filter-out src/main.c src/lib.c,$(SRCS_BASE)) $(MAIN_SRC)
else ifneq ($(findstring probes/,$(MAIN_SRC)),)
    SRCS := $(filter-out src/main.c src/lib.c,$(SRCS_BASE)) $(MAIN_SRC)
else
    SRCS := $(filter-out src/lib.c,$(SRCS_BASE))
endif

# lib.o is appended explicitly below so it always carries LIBCFLAGS.
OBJS := $(BUILD)/startup.o \
        $(patsubst %.c,$(BUILD)/%.o,$(notdir $(SRCS))) \
        $(BUILD)/lib.o

# Region bases — must stay in lock-step with sw/linker/veer.ld MEMORY and
# rtl/soc_top.sv address decode (spec §9.1).
IMEM_BASE := 0x00000000
DMEM_BASE := 0x00010000

# binutils `objcopy -O verilog` terminates every record with CRLF.  IEEE 1800
# $readmemh's whitespace set is {space, tab, newline, formfeed, comment} —
# '\r' is NOT in it, so a stray CR can be read as part of a hex token
# (observed here as `00000000\r` breaking downstream parsing).  Normalize to
# LF unconditionally; costs nothing and removes an entire failure mode.
CRLF_FIX = sed -i 's/\r$$//'

LDSCRIPT := linker/veer.ld

# ---------------------------------------------------------------------------
# Frozen flags (spec §8.2) + Amendment A1
# ---------------------------------------------------------------------------
CFLAGS := \
    -march=$(MARCH) -mabi=$(MABI) \
    $(OPT) \
    -ffreestanding -fno-builtin \
    -Wall -Wextra \
    -Iinclude \
    $(EXTRA_CFLAGS)

# src/lib.c only: stop GCC recognising memcpy/memset loops and rewriting them
# into calls to themselves (spec §8.4).
LIBCFLAGS := $(CFLAGS) -fno-tree-loop-distribute-patterns

ASFLAGS := -march=$(MARCH) -mabi=$(MABI) -g

LDFLAGS := \
    -march=$(MARCH) -mabi=$(MABI) \
    -nostartfiles -nostdlib \
    -T $(LDSCRIPT) \
    -Wl,-Map=$(BUILD)/firmware.map \
    -Wl,--gc-sections

# ---------------------------------------------------------------------------
# Objects
# ---------------------------------------------------------------------------
.PHONY: all elf firmware dis ihex mem verify-images inspect manifest clean help
.DEFAULT_GOAL := all

all: elf mem manifest

# The root Makefile delegates `make firmware` here (root Makefile:39), but this
# file only ever defined `elf`, so the documented `make` / `make all` entry
# point failed with "No rule to make target 'firmware'" on a clean tree —
# reproduced on HEAD before Phase 1 touched anything. Alias kept rather than
# editing the root Makefile, so both spellings work.
firmware: elf

help:
	@echo "sw/ targets (gates = plan §4.2 G1-G13, spec §16 L1-L4):"
	@echo "  elf      -> $(BUILD)/firmware.elf          [G1, G3, G5, G7]"
	@echo "  mem      -> imem.mem + dmem.mem + firmware.ihex"
	@echo "             runs verify-images              [G8, G9, G10]"
	@echo "  dis      -> $(BUILD)/firmware.dis"
	@echo "  inspect  -> ELF/section/symbol gates   [G1-G7, G11, G14, G15]"
	@echo "  manifest -> $(BUILD)/manifest.txt           [G12]"
	@echo "  clean    -> remove $(BUILD)/"

$(BUILD):
	@mkdir -p $(BUILD)

# ---------------------------------------------------------------------------
# Compile / link
# ---------------------------------------------------------------------------
elf: $(BUILD)/firmware.elf

$(BUILD)/firmware.elf: $(OBJS) $(LDSCRIPT) | $(BUILD)
	$(CC) $(LDFLAGS) $(OBJS) -o $@
	@echo "[SW] LINK   $@"

$(BUILD)/startup.o: src/startup.S | $(BUILD)
	$(CC) $(ASFLAGS) -c $< -o $@

# One rule per tree: objects are keyed on basename, and the trees hold no
# colliding names (src/lib.c vs tests/* vs probes/*).
$(BUILD)/%.o: src/%.c include/soc.h include/test.h include/uart.h | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/%.o: tests/%.c include/soc.h include/test.h include/uart.h \
               include/memtest.h \
               tests/t_bus.c tests/t_mem.c tests/memtest_core.c \
               tests/t_uart.c | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/%.o: probes/%.c include/soc.h include/test.h include/uart.h | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

# src/lib.c alone carries the loop-distribute guard (spec §8.4).
$(BUILD)/lib.o: src/lib.c | $(BUILD)
	$(CC) $(LIBCFLAGS) -c $< -o $@

# ---------------------------------------------------------------------------
# Disassembly
# ---------------------------------------------------------------------------
dis: $(BUILD)/firmware.dis

$(BUILD)/firmware.dis: $(BUILD)/firmware.elf | $(BUILD)
	$(OBJDUMP) -d -S --no-show-raw-insn $< > $@
	@echo "[SW] DIS    $@"

# ---------------------------------------------------------------------------
# Artifacts
# ---------------------------------------------------------------------------
ihex: $(BUILD)/firmware.ihex

$(BUILD)/firmware.ihex: $(BUILD)/firmware.elf | $(BUILD)
	$(OBJCOPY) -O ihex $< $@
	@echo "[SW] IHEX   $@   (delivery artifact only — NEVER fed to \$$readmemh)"

mem: $(BUILD)/imem.mem $(BUILD)/dmem.mem $(BUILD)/firmware.ihex verify-images

# Gates G8/G9/G10 (plan §4.2) — the images must be $readmemh-legal.
verify-images: $(BUILD)/imem.mem $(BUILD)/dmem.mem
	@ok=1; \
echo "[SW] ==== G8  imem.mem / dmem.mem / firmware.ihex consistent ====="; \
	echo "[SW]     imem.mem and firmware.ihex must always exist and be non-empty"; \
	for f in $(BUILD)/imem.mem $(BUILD)/firmware.ihex; do \
	  if [ ! -s $$f ]; then echo "[SW] FAIL G8: $$f missing or empty"; ok=0; continue; fi; \
	  printf '[SW]     %-24s %6s bytes\n' "$$(basename $$f)" "$$(wc -c < $$f)"; \
	done; \
	dsize=$$($(READELF) -SW $(BUILD)/firmware.elf \
	          | awk '{for(i=1;i<=NF;i++) if($$i==".data"){print strtonum("0x" $$(i+4)); exit}}'); \
	if [ -s $(BUILD)/dmem.mem ]; then \
	  printf '[SW]     %-24s %6s bytes\n' "dmem.mem" "$$(wc -c < $(BUILD)/dmem.mem)"; \
	elif [ "$$dsize" -gt 0 ]; then \
	  echo "[SW] FAIL G8: .data is 0x$$dsize bytes but dmem.mem is empty"; ok=0; \
	else \
	  echo "[SW]     dmem.mem              empty by design (.data size 0)"; \
	fi; \
	[ $$ok -eq 1 ] || exit 1; \
	echo "[SW] PASS G8"; \
	echo "[SW] ==== G9  every @record inside the 32 KB dense array ====="; \
	for f in $(BUILD)/imem.mem $(BUILD)/dmem.mem; do \
	  if [ ! -s $$f ]; then \
	    printf '[SW]     %-10s empty by design (no .data overlay)\n' "$$(basename $$f)"; \
	    continue; \
	  fi; \
	  first=$$(grep -m1 '^@' $$f || true); \
	  if [ -z "$$first" ]; then echo "[SW] FAIL G9: $$f has no @record"; ok=0; continue; fi; \
	  if [ "$$(basename $$f)" = "imem.mem" ] && [ "$$first" != "@00000000" ]; then \
	    echo "[SW] FAIL G9: imem.mem must start at @00000000 (got $$first)"; ok=0; fi; \
	  if grep -qE '^@(-|F{8,})' $$f; then \
	    echo "[SW] FAIL G9: $$f has an out-of-range @record: $$(grep -m1 -E '^@(-|F{8,})' $$f)"; ok=0; fi; \
	  while read -r rec; do \
	    idx=$${rec#@}; \
	    case "$$idx" in *[!0-9A-Fa-f]*) echo "[SW] FAIL G9: bad token $$idx"; ok=0;; esac; \
	    dec=$$(( 0x$$idx )); \
	    if [ $$dec -ge 32768 ]; then \
	      echo "[SW] FAIL G9: $$f @$$idx >= 0x8000 (outside 32 KB array)"; ok=0; fi; \
	  done < <(grep '^@' $$f); \
	  printf '[SW]     %-10s first=%-14s @records=%s\n' "$$(basename $$f)" "$$first" "$$(grep -c '^@' $$f)"; \
	done; \
	echo "[SW] ==== G9  image covers every section the CPU must read ==="; \
	tl_start=$$($(NM) $(BUILD)/firmware.elf | awk '$$3=="__test_list_start"{print $$1}'); \
	if [ -n "$$tl_start" ]; then \
	  tl_size=$$($(READELF) -SW $(BUILD)/firmware.elf \
	             | awk '{for(i=1;i<=NF;i++) if($$i==".test_list"){print strtonum("0x" $$(i+4)); exit}}'); \
	  have=$$(awk -v want="$$tl_start" \
	            'toupper(substr($$1,2))==toupper(want){f=1;next} f{n+=NF} END{print n+0}' \
	            $(BUILD)/imem.mem); \
	  echo "[SW]     .test_list at $$tl_start, $$tl_size bytes, image holds $$have"; \
	  if [ "$$have" -ne "$$tl_size" ]; then \
	    echo "[SW] FAIL G9: .test_list is not fully present in imem.mem"; \
	    echo "[SW]     ($$have of $$tl_size bytes) — the registry would read as zeros"; ok=0; \
	  fi; \
	fi; \
	[ $$ok -eq 1 ] || exit 1; \
	echo "[SW] PASS G9"; \
	echo "[SW] ==== G10 byte-per-token, LF, never Intel HEX ============="; \
	for f in $(BUILD)/imem.mem $(BUILD)/dmem.mem; do \
	  if LC_ALL=C grep -q $$'\r' $$f; then \
	    echo "[SW] FAIL G10: $$f has CR line endings"; ok=0; fi; \
	  if grep -qE '^:[0-9A-Fa-f]{8}' $$f; then \
	    echo "[SW] FAIL G10: $$f contains Intel HEX ':' records (Correction B)"; ok=0; fi; \
	  n=$$(grep -v '^@' $$f | wc -w); \
	  echo "[SW]     $$(basename $$f): $$n hex byte tokens"; \
	  [ $$n -le 32768 ] || { echo "[SW] FAIL G10: $$f overflows its array"; ok=0; }; \
	done; \
	[ $$ok -eq 1 ] || exit 1; \
	echo "[SW] PASS G10"

# imem.mem — code + rodata + the .data load image, @ rebased to IMEM index 0.
#
# .data is emitted here from its **LMA** (its bytes really do live in IMEM),
# which is exactly what startup.S copies out of; including it is mandatory or
# the .data LMA -> VMA copy would read uninitialised SRAM.
#
# .test_list must be included for the same reason. The test registry is a
# separate output section (veer.ld), so the frozen --only-section list left it
# out of imem.mem entirely: the suite ELF put it at 0x56c..0x584 while the
# image stopped at 0x56a, so every tc_*.name and tc_*.fn would have read as
# zero in hardware and the first TEST_CASE call would have jumped to NULL.
# Gate G9 now proves the image covers it.
$(BUILD)/imem.mem: $(BUILD)/firmware.elf | $(BUILD)
	$(OBJCOPY) -O verilog --verilog-data-width 1 \
	    --only-section=.text --only-section=.rodata --only-section=.data \
	    --only-section=.test_list \
	    --change-addresses=-$(IMEM_BASE) \
	    $< $@
	@$(CRLF_FIX) $@
	@echo "[SW] IMAGE  $@   (width=1 byte/token, rebased to $(IMEM_BASE))"

# dmem.mem — the .data overlay, @ rebased to DMEM array index 0 (D11).
#
# NOTE: `objcopy -O verilog` emits @records from the section **LMA**, not its
# VMA (empirically confirmed on this toolchain: .data has VMA 0x00010010 but
# LMA 0x0000029C).  So `--change-addresses=-$(DMEM_BASE)` yields
# 0x29C-0x10000 = @FFFFFFFFFF029C — a negative index, out of range for the
# 32 KB dense array.  The fix is to override the LMA outright to the
# VMA-relative index; --change-section-lma is applied after --change-addresses
# so the two cannot be composed (verified: combining them yields 0x00010010).
$(BUILD)/dmem.mem: $(BUILD)/firmware.elf | $(BUILD)
	@vma=$$($(NM) $< | awk '$$3=="__data_start"{print "0x"$$1}'); \
	 off=$$(( vma - $(DMEM_BASE) )); \
	 hex=$$(printf '0x%08X' $$off); \
	 printf '[SW]     .data VMA=%s -> dmem array index 0x%08X\n' "$$vma" "$$off"; \
	 $(OBJCOPY) -O verilog --verilog-data-width 1 \
	     --only-section=.data --change-section-lma .data=$$hex \
	     $< $@
	@$(CRLF_FIX) $@
	@echo "[SW] IMAGE  $@   (width=1 byte/token, rebased to $(DMEM_BASE))"

# ---------------------------------------------------------------------------
# Gates — plan §4.2 G1..G13, spec §16 L1..L4.  Numbering here matches the
# plan table exactly so a reviewer can diff the log against the plan.
# ---------------------------------------------------------------------------
inspect: $(BUILD)/firmware.elf $(BUILD)/imem.mem $(BUILD)/dmem.mem
	@echo "[SW] ==== G1  firmware.elf produced by 'make elf' ============="
	@test -f $< || { echo "[SW] FAIL G1: $< missing"; exit 1; }
	@ls -l $< | sed 's/^/[SW]     /'
	@echo "[SW] PASS G1"
	@echo "[SW] ==== G2  frozen -march / -mabi echoed by the build ========"
	@echo "[SW]     MARCH=$(MARCH)  MABI=$(MABI)  OPT=$(OPT)"
	@case "$(MARCH)|$(MABI)" in \
	   "rv32imc_zicsr_zifencei|ilp32") ;; \
	   *) echo "[SW] FAIL G2: frozen pair changed"; exit 1;; esac
	@echo "[SW] PASS G2"
	@echo "[SW] ==== G3  ELF32 / RISC-V ================================="
	@$(READELF) -h $< | grep -E "Class:|Data:|Machine:|Entry point" | sed 's/^/[SW]     /'
	@$(READELF) -h $< | grep -q "ELF32"                    || { echo "[SW] FAIL G3: not ELF32"; exit 1; }
	@$(READELF) -h $< | grep -q "RISC-V"                   || { echo "[SW] FAIL G3: not RISC-V"; exit 1; }
	@echo "[SW] PASS G3"
	@echo "[SW] ==== G4  architecture string (exactly) ==================="
	@$(READELF) -A $< | grep "Tag_RISCV_arch" | sed 's/^/[SW]     /'
	@$(READELF) -A $< | grep -q 'Tag_RISCV_arch: "rv32i2p1_m2p0_c2p0_zicsr2p0_zifencei2p0_zmmul1p0_zca1p0"' \
		|| { echo "[SW] FAIL G4: arch string differs from spec §16 L2"; exit 1; }
	@$(READELF) -A $< | grep -qE '"rv32i2p1_m2p0_c2p0_zicsr2p0_zifencei2p0_[^"]*_[fd]' \
		&& { echo "[SW] FAIL G4: F/D present => MABI cannot be ilp32"; exit 1; } || true
	@echo "[SW] PASS G4"
	@echo "[SW] ==== G5  entry == _start == 0x00000000 (nm cross-check) ==="
	@$(READELF) -h $< | grep "Entry point" | sed 's/^/[SW]     /'
	@$(NM) -n $< | grep -E " (_start|main|__data_load|__data_start|__bss_start|__bss_end|__stack_top)$$" | sed 's/^/[SW]     /'
	@$(READELF) -h $< | grep -q "Entry point address: *0x0" || { echo "[SW] FAIL G5: e_entry != 0x0"; exit 1; }
	@$(NM) -n $< | grep -q "^00000000 T _start"             || { echo "[SW] FAIL G5: _start not at 0x0"; exit 1; }
	@$(NM) -n $< | grep -q " T main"                         || { echo "[SW] FAIL G5: no main"; exit 1; }
	@# Pin the ADDRESS, which is the real contract (veer.ld:108 already asserts
	@# it at link time). The nm section-type letter is deliberately not matched:
	@# __stack_top is assigned after the .bss output section (veer.ld:81), and
	@# GNU ld attributes it to whichever section is current. With a non-empty
	@# .bss that is `B`; with an EMPTY .bss (e.g. a probe image with no .bss
	@# arrays, as in build/spike) ld drops the zero-size section and reports `D`.
	@# Address is unchanged and __data_size stays 4, so there is no correctness
	@# issue — only the letter differs. Relaxed 2026-10-17 for the Phase 0 spike.
	@$(NM) -n $< | grep -qE "^00018000 [A-Z] __stack_top$$"  || { echo "[SW] FAIL G5: __stack_top != 0x00018000"; $(NM) -n $< | grep "__stack_top"; exit 1; }
	@echo "[SW] PASS G5"
	@echo "[SW] ==== G6  sections inside IMEM/DMEM, never core-local ====="
	@$(READELF) -SW $< | grep -E "\.text|\.rodata|\.data|\.bss" | sed 's/^/[SW]     /'
	@bad=$$($(NM) -n $< | awk '$$1 ~ /^(ee|f0)/ {print $$1, $$2, $$3}'); \
	 if [ -n "$$bad" ]; then echo "[SW] FAIL G6: symbol in ICCM/DCCM range:"; echo "$$bad"; exit 1; fi
	@bss_end=$$($(NM) -n $< | awk '$$3=="__bss_end"{print $$1}'); \
	 if [ -z "$$bss_end" ] || [ $$(( 0x$$bss_end )) -gt $$(( 0x00018000 )) ]; then \
	   echo "[SW] FAIL G6: __bss_end=$$bss_end escapes DMEM"; exit 1; fi; \
	 echo "[SW]     __bss_end=$$bss_end <= 0x00018000"
	@echo "[SW] PASS G6"
	@echo "[SW] ==== G7  freestanding link under -nostdlib (A1) ==========="
	@dyn=$$($(READELF) -d $< 2>&1 | grep -c "no dynamic section"); \
	 if [ "$$dyn" != "1" ] || $(READELF) -d $< 2>/dev/null | grep -q '(NEEDED)'; then \
	   echo "[SW] FAIL G7: not -nostdlib clean:"; $(READELF) -d $< 2>/dev/null | grep -E 'NEEDED'; exit 1; fi
	@undef=$$($(NM) -u $< 2>/dev/null | grep -v '^[[:space:]]*$$' || true); \
	 if [ -n "$$undef" ]; then echo "[SW] FAIL G7: undefined symbols:"; echo "$$undef"; exit 1; fi
	@echo "[SW]     'There is no dynamic section' + 0 undefined symbols"
	@test -s $(BUILD)/firmware.map || { echo "[SW] FAIL G7: no link map"; exit 1; }
	@if grep -qi "overflowed\|region .* overflows" $(BUILD)/firmware.map; then \
	   echo "[SW] FAIL G7: region overflow in link map:"; \
	   grep -i "overflowed\|region .* overflows" $(BUILD)/firmware.map; exit 1; fi
	@echo "[SW]     link map has no region overflow (veer.ld ASSERTs back this up)"
	@echo "[SW]     Amendment A1: without -nostdlib the first __udivdi3 reference"
	@echo "[SW]     aborts with 'libgcc.a file class ELFCLASS64 incompatible'"
	@echo "[SW] PASS G7"
	@echo "[SW] ==== G11 imem.mem head == first instruction ==============="
	@# The first instruction need not be 4 bytes: with -march=..._c the
	@# assembler emits 16-bit compressed forms, so `li t0,8` at _start+0 is
	@# 2 bytes and a naive 4-byte image/objdump comparison fails on a correct
	@# image (seen once Phase 1 put `li t0,8` first for MRAC). Determine the
	@# instruction's width from the objdump token and compare only that many
	@# bytes: 4 hex chars = 2 bytes, 8 hex chars = 4 bytes.
	@# objdump prints lowercase hex, so the image word is lowercased before
	@# the compare. Otherwise the test is a case test that passes only when
	@# the encoding happens to contain no letters.
	@word=$$($(OBJDUMP) -d --start-address=0 --stop-address=4 $< 2>/dev/null \
	         | awk '/^ +[0-9a-f]+:/{print $$2; exit}'); \
	 wlen=$${#word}; \
	 if [ $$wlen -le 4 ]; then nb=2; else nb=4; fi; \
	 bytes=$$(grep -m1 -A1 '^@00000000' $(BUILD)/imem.mem | tail -1 \
	          | awk '{print $$1, $$2, $$3, $$4}'); \
	 read -r b0 b1 b2 b3 <<< "$$bytes"; \
	 if [ $$nb -eq 2 ]; then img=$$(printf '%02X%02X' 0x$$b1 0x$$b0); \
	 else img=$$(printf '%02X%02X%02X%02X' 0x$$b3 0x$$b2 0x$$b1 0x$$b0); fi; \
	 img=$$(echo "$$img" | tr 'A-F' 'a-f'); \
	 echo "[SW]     objdump word  : $$word ($$(( nb * 8 ))-bit instruction)"; \
	 echo "[SW]     imem.mem word : $$img   (bytes: $$bytes)"; \
	 if [ "$$img" != "$$word" ]; then \
	   echo "[SW] FAIL G11: image head != _start encoding"; exit 1; fi
	@echo "[SW] PASS G11"
	@echo "[SW] ==== G14 no undefined symbols (freestanding, no libgcc) ====="
	@# Check the LINKED ELF, not the objects: an object legitimately shows
	@# undefined __bss_start/__data_load/main/... because those are supplied
	@# by the linker script and by other objects. What must be empty is the
	@# resolved image — anything left undefined there would mean -nostdlib
	@# let an unbacked reference through, which is exactly what happened the
	@# first time a 64-bit division was introduced (__udivdi3).
	@undef=$$($(NM) -u $< 2>/dev/null | grep -v '^$$' || true); \
	 if [ -n "$$undef" ]; then \
	   echo "[SW] FAIL G14: undefined symbols survived the -nostdlib link:"; \
	   echo "$$undef" | sed 's/^/[SW]     /'; \
	   echo "[SW]     64-bit div/mod needs __udivdi3, which does not exist here"; \
	   exit 1; fi
	@echo "[SW]     nm -u on the linked ELF is empty"
	@echo "[SW] PASS G14"
	@echo "[SW] ==== G15 IMEM image + scratch safety ======================="
	@end=$$($(NM) $< | awk '$$3=="__imem_image_end"{print $$1}'); \
	 if [ -z "$$end" ]; then echo "[SW] FAIL G15: __imem_image_end not exported"; exit 1; fi; \
	 dec=$$(( 0x$$end )); \
	 echo "[SW]     __imem_image_end = $$end ($$dec)"; \
	 if [ $$dec -gt 24576 ]; then \
	   echo "[SW] FAIL G15: loaded image leaves less than 4 KB of IMEM scratch"; \
	   echo "[SW]     (a memory test would overwrite its own code)"; exit 1; fi
	@echo "[SW]     >= 4 KB of IMEM remains below the 32 KB ceiling for test scratch"
	@echo "[SW] PASS G15"
	@echo "[SW] ---- informational: size ----------------------------------"
	@$(SIZE) $<
	@echo "[SW] inspect OK  (G1-G7, G11, G14, G15 pass here; G8-G10 run under"
	@echo "[SW]             'make mem'; G12 under 'make manifest'; G13 at sim time)"

manifest: $(BUILD)/firmware.elf $(BUILD)/imem.mem $(BUILD)/dmem.mem
	@echo "[SW] ==== G12 manifest (spec §17) ============================="
	@echo "[SW] writing $@"
	@{ \
	  echo "file            : $(notdir $<)"; \
	  echo "march           : $(MARCH)"; \
	  echo "mabi            : $(MABI)"; \
	  echo "opt             : $(OPT)"; \
	  echo "ldflags         : $(LDFLAGS)"; \
	  echo "ldscript        : $(LDSCRIPT)"; \
	  echo "Init mode       : Mode 1"; \
	  echo "addr_xor        : iccm=0 dccm=0"; \
	  echo "entry           : $$($(READELF) -h $(BUILD)/firmware.elf | awk -F: '/Entry/{gsub(/ /,"",$$2);print $$2}')"; \
	  echo "elf_class       : $$($(READELF) -h $(BUILD)/firmware.elf | awk -F: '/Class/{gsub(/ /,"",$$2);print $$2}')"; \
	  echo "arch            : $$($(READELF) -A $(BUILD)/firmware.elf | awk -F: '/Tag_RISCV_arch/{sub(/^ */,"",$$2);print $$2}')"; \
	  echo "imem_image      : $(BUILD)/imem.mem ($(shell wc -c < $(BUILD)/imem.mem 2>/dev/null || echo 0) bytes on disk)"; \
	  echo "dmem_image      : $(BUILD)/dmem.mem ($(shell wc -c < $(BUILD)/dmem.mem 2>/dev/null || echo 0) bytes on disk)"; \
	  echo "first_imem_rec  : $$(grep -m1 '^@' $(BUILD)/imem.mem 2>/dev/null || echo none)"; \
	  echo "dmem_index_rec  : $$(grep -m1 '^@' $(BUILD)/dmem.mem 2>/dev/null || echo none)"; \
	  echo "generated       : $$(date -u +%Y-%m-%dT%H:%M:%SZ)"; \
	} > $(BUILD)/manifest.txt
	@cat $(BUILD)/manifest.txt
	@grep -q "Init mode       : Mode 1" $(BUILD)/manifest.txt \
		&& grep -q "addr_xor        : iccm=0 dccm=0" $(BUILD)/manifest.txt \
		|| { echo "[SW] FAIL G12: manifest missing Mode 1 / addr_xor fields"; exit 1; }
	@echo "[SW] PASS G12"

clean:
	rm -rf $(BUILD)
	@echo "[SW] cleaned $(BUILD)/"
