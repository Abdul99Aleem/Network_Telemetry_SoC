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

    /* ---- stack: grows down from the top of DMEM ------------------------ */
    __stack_top  = ORIGIN(DMEM) + LENGTH(DMEM);   /* 0x0001_8000 */
    __stack_size = __stack_top - __bss_end;

    /* ---- mailbox reservation (written by startup.S, read by the TB) ---- */
    __mbox_base = ORIGIN(MBOX);                   /* 0x0001_0000 */
    __mbox_size = LENGTH(MBOX);

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
