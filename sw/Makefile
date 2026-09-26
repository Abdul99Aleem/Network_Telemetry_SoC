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
    -Iinclude

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
OBJS := $(BUILD)/startup.o $(BUILD)/main.o $(BUILD)/lib.o

.PHONY: all elf dis ihex mem verify-images inspect manifest clean help
.DEFAULT_GOAL := all

all: elf mem manifest

help:
	@echo "sw/ targets (gates = plan §4.2 G1-G13, spec §16 L1-L4):"
	@echo "  elf      -> $(BUILD)/firmware.elf          [G1, G3, G5, G7]"
	@echo "  mem      -> imem.mem + dmem.mem + firmware.ihex"
	@echo "             runs verify-images              [G8, G9, G10]"
	@echo "  dis      -> $(BUILD)/firmware.dis"
	@echo "  inspect  -> ELF/section/symbol gates        [G1-G7, G11]"
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

$(BUILD)/main.o: src/main.c include/soc.h | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/lib.o: src/lib.c | $(BUILD)
	$(CC) $(LIBCFLAGS) -c $< -o $@

# ---------------------------------------------------------------------------
# Disassembly
# ---------------------------------------------------------------------------
dis: $(BUILD)/firmware.dis

$(BUILD)/firmware.dis: $(BUILD)/firmware.elf
	$(OBJDUMP) -d -S --no-show-raw-insn $< > $@
	@echo "[SW] DIS    $@"

# ---------------------------------------------------------------------------
# Artifacts
# ---------------------------------------------------------------------------
ihex: $(BUILD)/firmware.ihex

$(BUILD)/firmware.ihex: $(BUILD)/firmware.elf
	$(OBJCOPY) -O ihex $< $@
	@echo "[SW] IHEX   $@   (delivery artifact only — NEVER fed to \$$readmemh)"

mem: $(BUILD)/imem.mem $(BUILD)/dmem.mem $(BUILD)/firmware.ihex verify-images

# Gates G8/G9/G10 (plan §4.2) — the images must be $readmemh-legal.
verify-images: $(BUILD)/imem.mem $(BUILD)/dmem.mem
	@ok=1; \
	echo "[SW] ==== G8  imem.mem / dmem.mem / firmware.ihex non-empty ==="; \
	for f in $(BUILD)/imem.mem $(BUILD)/dmem.mem $(BUILD)/firmware.ihex; do \
	  if [ ! -s $$f ]; then echo "[SW] FAIL G8: $$f missing or empty"; ok=0; continue; fi; \
	  printf '[SW]     %-24s %6s bytes\n' "$$(basename $$f)" "$$(wc -c < $$f)"; \
	done; \
	[ $$ok -eq 1 ] || exit 1; \
	echo "[SW] PASS G8"; \
	echo "[SW] ==== G9  every @record inside the 32 KB dense array ====="; \
	for f in $(BUILD)/imem.mem $(BUILD)/dmem.mem; do \
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
$(BUILD)/imem.mem: $(BUILD)/firmware.elf
	$(OBJCOPY) -O verilog --verilog-data-width 1 \
	    --only-section=.text --only-section=.rodata --only-section=.data \
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
$(BUILD)/dmem.mem: $(BUILD)/firmware.elf
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
	@$(NM) -n $< | grep -q "^00018000 B __stack_top"         || { echo "[SW] FAIL G5: __stack_top != 0x00018000"; exit 1; }
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
	@bytes=$$(grep -m1 -A1 '^@00000000' $(BUILD)/imem.mem | tail -1 | awk '{print $$1, $$2, $$3, $$4}'); \
	 word=$$($(OBJDUMP) -d --start-address=0 --stop-address=4 $< 2>/dev/null \
	         | awk '/^ +[0-9a-f]+:/{print $$2; exit}'); \
	 read -r b0 b1 b2 b3 <<< "$$bytes"; \
	 img=$$(printf '%02X%02X%02X%02X' 0x$$b3 0x$$b2 0x$$b1 0x$$b0); \
	 echo "[SW]     objdump word  : $$word"; \
	 echo "[SW]     imem.mem word : $$img   (bytes: $$bytes)"; \
	 if [ "$$img" != "$$word" ]; then \
	   echo "[SW] FAIL G11: image head != _start encoding"; exit 1; fi
	@echo "[SW] PASS G11"
	@echo "[SW] ---- informational: size ----------------------------------"
	@$(SIZE) $<
	@echo "[SW] inspect OK  (G1-G7, G11 pass here; G8-G10 run under 'make mem';"
	@echo "[SW]             G12 under 'make manifest'; G13 checked at sim time)"

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
