/* ============================================================================
 * Project : RISC-V Network Telemetry SoC
 * Script  : sw/linker/veer.ld
 * Desc    : VeeR EL2 (p2_soc snapshot) linker script.
 *
 *           Frozen map (arch v3 §9):
 *             IMEM  0x0000_0000 .. 0x0000_7FFF   32 KB  code + rodata + .data LMA
 *             MBOX  0x0001_0000 .. 0x0001_000F   16 B   fw0 PASS mailbox (reserved)
 *             DMEM  0x0001_0010 .. 0x0001_7FFF         .data VMA + .bss + stack
 *
 *           reset_vec = 0x0000_0000  =>  ENTRY(_start) must link at 0x0.
 *           Guardrails (spec §9.3 / amendment H.9): no section may ever land
 *           in the VeeR core-local ICCM (0xEE00_xxxx) or DCCM (0xF004_xxxx)
 *           ranges — structurally impossible here because MEMORY only spans
 *           0x0000_xxxx, but asserted anyway so a future edit cannot
 *           silently reintroduce it.
 *
 * Spec     : doc/RISC_V_SW_Build_and_Simulation_Image_Architecture_Specification.md
 *            §4.3 (linker), §9.3 (Mode-1 guardrails), checklist C
 * ==========================================================================*/
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 32K
    MBOX (rw)  : ORIGIN = 0x00010000, LENGTH = 16
    DMEM (rwx) : ORIGIN = 0x00010010, LENGTH = 32K - 16
}

SECTIONS
{
    /* ---- code ---- */
    .text :
    {
        KEEP(*(.text.start))
        *(.text .text.*)
        *(.gnu.linkonce.t.*)
    } > IMEM

    /* ---- read-only data ---- */
    .rodata :
    {
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
        *(.gnu.linkonce.r.*)
        . = ALIGN(4);
    } > IMEM

    /* ---- initialised data: VMA in DMEM, load image in IMEM -------------
     * startup.S copies LOADADDR(.data) -> ADDR(.data), so the bytes arrive
     * in the .mem image via imem.mem and are relocated at boot.          */
    .data :
    {
        . = ALIGN(4);
        __data_start = .;
        *(.data .data.*)
        *(.sdata .sdata.*)
        . = ALIGN(4);
        __data_end = .;
    } > DMEM AT> IMEM

    /* ---- test framework ---------------------------------------------------
     * Phase 1 of the C test suite plan. Two sections, both load-time inert for
     * the image: .test_list is const data (it does land in imem.mem, which is
     * exactly why .data does too), .results is NOLOAD and costs no image bytes.
     *
     * .results is placed FIRST in DMEM so it lands at a fixed 0x0001_0010 and
     * the testbench can walk it by a known absolute address, pushing .data,
     * .bss and the stack above it. __stack_top is unchanged because MEMORY is
     * untouched — see the ASSERT below.
     */
    .results (NOLOAD) :
    {
        . = ALIGN(4);
        __results_start = .;
        KEEP(*(.results .results.*))
        . = ALIGN(4);
        __results_end = .;
    } > DMEM

    .test_list :
    {
        . = ALIGN(4);
        __test_list_start = .;
        KEEP(*(.test_list))
        . = ALIGN(4);
        __test_list_end = .;
    } > IMEM

    __data_load   = LOADADDR(.data);
    __data_size   = SIZEOF(.data);

    /* ---- zero-initialised data: NOBITS, no bytes in any image ---------- */
    .bss (NOLOAD) :
    {
        . = ALIGN(4);
        __bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > DMEM

    __bss_size = SIZEOF(.bss);

    /* ---- end of the loaded image in IMEM ---------------------------------
     * Highest IMEM address occupied by anything $readmemh will have written:
     * the .data load image AND the .test_list registry (which the suite's
     * imem.mem rule now emits explicitly). A memory test must begin scratch at
     * or above this, or it overwrites its own code or its own test table. */
    __imem_image_end = MAX(__data_load + __data_size, __test_list_end);

    /* ---- stack: grows down from the top of DMEM ------------------------ */
    __stack_top  = ORIGIN(DMEM) + LENGTH(DMEM);   /* 0x0001_8000 */
    __stack_size = __stack_top - __bss_end;

    /* ---- mailbox reservation (written by startup.S, read by the TB) ---- */
    __mbox_base = ORIGIN(MBOX);                   /* 0x0001_0000 */
    __mbox_size = LENGTH(MBOX);

    /* Trap diagnostic. startive.S increments it on every trap entry, and the
     * testbench prints it on timeout, so "did the handler run at all?" is a
     * question the log answers instead of one only a waveform can. Placed in
     * the mailbox reservation, which the suite never otherwise writes. */
    __trapdiag = __mbox_base + 12;               /* DMEM 0x0001_000C */

    /* ---- bounds consumed by the Phase 3 memory tests -------------------
     * Every destructive pattern in the suite is bounded by these rather than
     * by hard-coded addresses, so a change to the map above cannot silently
     * redirect a test into .results, .bss or the stack. The ASSERTs at the
     * bottom prove they stay ordered.
     */
    __memtest_dmem_scratch_lo = ((__bss_end + 31) & ~31);   /* word-align */
    __memtest_dmem_scratch_hi = __stack_top - 0x1000;       /* 4 KB stack */

    /DISCARD/ :
    {
        *(.comment)
        *(.note .note.*)
    }
}

/* ============================ guardrails ============================== */

/* reset_vec = 0x0000_0000 in the p2_soc/fw_soc snapshot must match _start. */
ASSERT(_start == 0x00000000,
       "ENTRY(_start) must be 0x00000000 to match reset_vec=0x00000000")

/* The mailbox must never be claimed by a real section. */
ASSERT(__mbox_base + __mbox_size <= ORIGIN(DMEM),
       "mailbox reservation collides with .data")

/* Stack must fit above .bss and still be inside DMEM. */
ASSERT(__stack_size >= 512,
       "less than 512 bytes of stack left above .bss")
ASSERT(__stack_top == 0x00018000,
       "stack top must be the DMEM ceiling 0x00018000")

/* Mode-1 guardrails: nothing may live in the VeeR core-local ranges.
 * ICCM 0xEE00_0000..0xEE00_FFFF, DCCM 0xF004_0000..0xF004_FFFF (spec §9.3). */
ASSERT(ADDR(.text) < 0x00008000 && ADDR(.text) + SIZEOF(.text) <= 0x00008000,
       ".text escapes IMEM")
ASSERT(ADDR(.data) >= 0x00010010 && ADDR(.data) + SIZEOF(.data) <= 0x00018000,
       ".data escapes DMEM")
ASSERT(__bss_start >= 0x00010010 && __bss_end <= 0x00018000,
       ".bss escapes DMEM")
ASSERT(__data_load + __data_size <= 0x00008000,
       ".data LMA escapes IMEM")
ASSERT(!((ADDR(.text)   >= 0xEE000000 && ADDR(.text)   < 0xEE010000) ||
         (ADDR(.data)   >= 0xEE000000 && ADDR(.data)   < 0xEE010000) ||
         (__bss_start   >= 0xEE000000 && __bss_start   < 0xEE010000) ||
         (ADDR(.text)   >= 0xF0040000 && ADDR(.text)   < 0xF0050000) ||
         (ADDR(.data)   >= 0xF0040000 && ADDR(.data)   < 0xF0050000) ||
         (__bss_start   >= 0xF0040000 && __bss_start   < 0xF0050000)),
       "a section landed in an ICCM/DCCM core-local region (Mode 1 violation)")

/* ================= memory-test safety guardrails (Phase 3) ============== */

/* The DMEM scratch window must sit strictly above everything the runner owns
 * and strictly below the stack. If any of these ever failed, a memory test
 * could overwrite its own result table and still report PASS, because the
 * result table is the thing doing the reporting. */
ASSERT(__memtest_dmem_scratch_lo >= __bss_end,
       "DMEM test scratch overlaps .bss")
ASSERT(__memtest_dmem_scratch_lo >= __results_end,
       "DMEM test scratch overlaps .results")
ASSERT(__memtest_dmem_scratch_hi <= __stack_top,
       "DMEM test scratch reaches into the stack")
ASSERT(__memtest_dmem_scratch_hi > __memtest_dmem_scratch_lo,
       "DMEM test scratch window is empty")

/* IMEM scratch starts above the whole loaded image: .text, .rodata, .test_list
 * and the .data LMA all live below __imem_image_end. */
ASSERT(__imem_image_end >= ADDR(.text) + SIZEOF(.text),
       "__imem_image_end does not cover .text")
ASSERT(__imem_image_end >= ADDR(.test_list) + SIZEOF(.test_list),
       "__imem_image_end does not cover the test registry")
ASSERT(__imem_image_end + 0x0400 <= 0x00008000,
       "less than 1 KB of IMEM scratch above the image")

/* ================= test-framework guardrails (Phase 1) ====================
 *
 * All four are guarded on SIZEOF(...) > 0 because fw0 links no .results and no
 * .test_list at all, and an empty output section leaves its boundary symbols
 * undefined (which ld resolves to 0 and would trip a bare comparison).
 */

/* .results must sit at the fixed base the testbench hard-codes, and inside DMEM. */
ASSERT(SIZEOF(.results) == 0 ||
       (__results_start == 0x00010010 && __results_end <= 0x00018000),
       ".results must begin at the fixed RESULTS_BASE 0x00010010 and stay in DMEM")

/* The reservation is a compile-time constant in sw/include/test.h:
 *   RESULTS_HDR_BYTES 28 + RESULTS_MAX_ENT 64 * RESULTS_ENT_BYTES 8 = 540 bytes.
 * ld cannot see those C macros, so the literal is repeated here. If test.h is
 * ever changed, this figure must be changed with it — it exists to keep the
 * fixed reservation comfortably below the 32 KB DMEM ceiling, which the
 * SIZEOF check above already proves for the real section. */
ASSERT((28 + 64 * 8) <= 0x00007F00,
       "result table reservation too large for DMEM below the stack")

/* The whole test registry must fit inside IMEM, alongside .text/.rodata. */
ASSERT(SIZEOF(.test_list) == 0 || __test_list_end <= 0x00008000,
       ".test_list escapes IMEM")

/* The loaded image must leave room for a memory-test scratch region, so a
 * test can never grow into its own code. Gate G15 re-checks the same
 * arithmetic at build time with the value baked into the shell.
 * NOTE: a single string literal — GNU ld does not concatenate adjacent
 * literals in an ASSERT message, so this must not be wrapped. */
ASSERT(__imem_image_end + 0x1000 <= 0x00008000,
       "loaded image leaves less than 4 KB of IMEM scratch for test scratch")
