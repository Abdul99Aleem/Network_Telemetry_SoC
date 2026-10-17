/* ============================================================================
 * Project : RISC-V Network Telemetry SoC
 * File    : sw/src/startup.S
 * Desc    : Reset / C runtime bring-up for the p2_soc snapshot.
 *
 *           Spec §22 D8 order, frozen:
 *             0. set MRAC       = side-effect bit for 0x1xxx_xxxx   (Phase 1)
 *             1. set sp        = __stack_top        (0x0001_8000)
 *             2. set mtvec     = trap_handler
 *             3. copy .data    LMA (IMEM) -> VMA (DMEM)
 *             4. clear .bss    in DMEM
 *             5. call main
 *             6. on return, write the Phase-2 PASS signature to the DMEM
 *                mailbox (tb/tb_veer_p2_soc.sv:300 fires unchanged)
 *             7. park
 *
 *           Step 0 is additive: it was added with the C test suite (Phase 1)
 *           and is inert for fw0, which performs no MMIO. Steps 1-7 are the
 *           frozen D8 order and the mailbox byte contract is unchanged.
 *
 *           Verdi: .text.start is the instruction fetch the SoC performs on
 *           the very first AHB cycle after reset is released.
 * ==========================================================================*/

    .section .text.start, "ax", @progbits
    .align  2
    .globl  _start
    .type   _start, @function
_start:
    /* ---- 0. MRAC: mark peripheral regions side-effecting ----------------
     * VeeR's LSU load buffer forwards a repeated load of the same address, so
     * polling a status register (UART LSR) never reaches the bus unless the
     * region is marked side-effecting. scripts/p3_uart_prog_gen.py:28-33
     * documents this for the Python-generated UART program; MRAC has no
     * hardware reset value, so it must be written explicitly on every boot.
     *
     * CSR 0x7C0 packs {side_effect, cacheable} pairs addressed by
     * {addr[31:28], 1'b1}. The SoC peripheral window is 0x1xxx_xxxx, which is
     * MRAC[3], so side_effect for it is 1<<3 = 0x0000_0008. Bit 8 (cacheable
     * for the same region) is deliberately left clear.
     *
     * fw0 performs no MMIO, so this is inert for it; the suite needs it. */
    li      t0, 0x00000008               /* MRAC[3] = side_effect */
    csrw    0x7c0, t0
    fence.i                                /* retire any fetch already in flight */

    /* ---- 1. stack pointer (top of DMEM, 16-byte aligned by construction) */
    la      sp, __stack_top

    /* ---- 2. trap vector ------------------------------------------------- */
    la      t0, trap_handler
    csrw    mtvec, t0

    /* ---- 3. .data: copy LOADADDR (IMEM) -> ADDR (DMEM) ------------------ */
    la      t0, __data_load            /* t0 = LMA, reads from IMEM  */
    la      t1, __data_start           /* t1 = VMA, writes to DMEM   */
    la      t2, __data_end
    bgeu    t1, t2, .Ldata_done
.Ldata_copy:
    lw      t3, 0(t0)                  /* AHB read  cycle -> IMEM     */
    sw      t3, 0(t1)                  /* AHB write cycle -> DMEM     */
    addi    t0, t0, 4
    addi    t1, t1, 4
    bltu    t1, t2, .Ldata_copy
.Ldata_done:

    /* ---- 4. .bss: zero-fill --------------------------------------------- */
    la      t0, __bss_start
    la      t1, __bss_end
    bgeu    t0, t1, .Lbss_done
.Lbss_clear:
    sw      zero, 0(t0)                /* AHB write cycle -> DMEM     */
    addi    t0, t0, 4
    bltu    t0, t1, .Lbss_clear
.Lbss_done:

    /* ---- 5. into C ------------------------------------------------------- */
    li      a0, 0
    li      a1, 0
    call    main                       /* main() returns 0 == PASS    */

    /* ---- 6. Phase-2 PASS signature --------------------------------------
     * tb/tb_veer_p2_soc.sv:300 requires, byte for byte:
     *   mem[0]=0x50 mem[1]=0x32 mem[2]=0xFF
     *   mem[4]=0x50 mem[5]=0x32 mem[6]=0x00 mem[7]=0x00
     * The trigger byte [2]=0xFF is written LAST so the monitor only ever
     * samples a fully-formed signature.                                   */
    la      t0, __mbox_base            /* 0x0001_0000 */

    bnez    a0, .Lmailbox_fail

.Lmailbox_pass:
    li      t1, 0x50                   /* 'P' */
    sb      t1, 0(t0)
    li      t1, 0x32                   /* '2' */
    sb      t1, 1(t0)
    li      t1, 0x3250                 /* words [4..7] == 0x00003250 */
    sw      t1, 4(t0)
    li      t1, 0x00                   /* pass code */
    sb      t1, 3(t0)
    li      t1, 0xFF                   /* trigger */
    sb      t1, 2(t0)
    j       .Lpark

.Lmailbox_fail:
    /* main() returned a non-zero fail id. Corrupt [0] so the existing
     * monitor prints FAIL (instead of stalling to the TB watchdog), and
     * stash the id at [3] for waveform diagnosis.                          */
    li      t1, 0x00
    sb      t1, 0(t0)
    sb      a0, 3(t0)
    li      t1, 0xFF
    sb      t1, 2(t0)
    /* fall through */

.Lpark:
    /* ---- 7. park -------------------------------------------------------- */
    wfi                                 /* idles until an interrupt */
1:  j       1b
    .size   _start, . - _start

/* ============================================================================
 * Trap handler — dual purpose (Phase 3).
 *
 * 1. An UNEXPECTED trap (fault/illegal instruction, or any error while no test
 *    armed the expectation) parks exactly as before, WITHOUT touching the
 *    mailbox, so the TB watchdog reports a timeout rather than a spurious PASS.
 *
 * 2. An EXPECTED trap — the Phase-3 bus tests deliberately read unmapped
 *    addresses to prove the fabric raises an AHB ERROR and that the CPU sees
 *    an exception. For that case the handler clears the flag and jumps to a
 *    FIXED resume label (bus_test_resume in sw/tests/t_bus.c).
 *
 * WHY NOT `mepc + 4`
 *   The VeeR bus exception is IMPRECISE. Verified trace:
 *     hresp -> axi4_to_ahb.sv:323,344,365 -> axi_rresp 2'b10/2'b11 ->
 *     el2_lsu_bus_buffer.sv:873 bus_rsp_read_error -> buf_error ->
 *     lsu_imprecise_error_load_any / lsu_imprecise_error_store_any ->
 *     lsu_pmu_bus_error (el2_veer.sv:923).
 *   For an imprecise error mepc does not reliably identify the faulting
 *   instruction, so resuming at mepc+4 could re-execute the faulting load and
 *   trap forever. The resume label is a fixed symbol instead, and the C side
 *   restores ra/sp (a longjmp-style recovery) so the interrupted frame
 *   continues from a known state.
 *
 * trap_expect is a plain word in .bss, declared in sw/tests/t_bus.c. It is armed
 * immediately before the faulting access and disarmed immediately after the
 * access plus a fence, so the window where a trap is "expected" is as short as
 * the test can make it.
 * ==========================================================================*/
    .align  2
    .globl  trap_handler
    .type   trap_handler, @function
trap_handler:
    /* Diagnostic counter: incremented on EVERY trap entry so the testbench can
     * tell "handler never ran" apart from "handler ran but recovery failed".
     */
    la      t0, __trapdiag
    lw      t1, 0(t0)
    addi    t1, t1, 1
    sw      t1, 0(t0)

    la      t0, trap_expect
    lw      t1, 0(t0)
    beqz    t1, .Ltrap_park         /* unexpected: original behaviour */

    li      t1, 0                   /* expected: disarm before resuming */
    sw      t1, 0(t0)

    la      t0, bus_test_resume     /* fixed resume label, NOT mepc-derived */
    jr      t0

.Ltrap_park:
1:  j       1b
    .size   trap_handler, . - trap_handler

/* ============================================================================
 * bus_test_resume — the fixed safe resume label.
 *
 * Written in assembly, deliberately. An earlier version was a C function that
 * did `mv ra, saved_ra; mv sp, saved_sp` inline: the compiler then emitted its
 * own epilogue AFTER those stores, reloading ra from the (now stale) stack
 * frame and adjusting sp again. The recovery was silently undone and the CPU
 * looped forever — the bus test hung on the first unmapped access.
 *
 * Here there is no compiler-generated prologue or epilogue at all: restore ra
 * and sp, then return. This is a longjmp-style recovery — no mepc-derived value
 * is trusted, and the faulting instruction is never re-executed.
 *
 * saved_ra / saved_sp are captured by bus_trap_try immediately before the
 * faulting access, and are plain globals so this code can name them.
 * ==========================================================================*/
    .align  2
    .globl  bus_test_resume
    .type   bus_test_resume, @function
bus_test_resume:
    la      t0, saved_ra
    lw      t1, 0(t0)
    mv      ra, t1
    la      t0, saved_sp
    lw      t1, 0(t0)
    mv      sp, t1
    ret
    .size   bus_test_resume, . - bus_test_resume

/* ============================================================================
 * Recovery state for the expected-trap path.
 *
 * Defined HERE rather than in the C test files, and deliberately in .bss.
 * startup.S references trap_expect / saved_ra / saved_sp unconditionally, so a
 * variant that does not compile test_main.c (fw0, the default build, the
 * probes) must still be able to link. Keeping the storage in this file makes
 * that true without a weak-symbol or build-flag dance, and .bss means the
 * startup clear loop initialises it exactly like any other mutable global.
 * ==========================================================================*/
    .section .bss,"aw",@nobits
    .globl  trap_expect
    .type   trap_expect, @object
    .size   trap_expect, 4
trap_expect:
    .word   0
    .globl  saved_ra
    .type   saved_ra, @object
    .size   saved_ra, 4
saved_ra:
    .word   0
    .globl  saved_sp
    .type   saved_sp, @object
    .size   saved_sp, 4
saved_sp:
    .word   0
    .text

    /* main() lives in main.c; provide no weak alias so a missing main is a
     * link error (gate G5/G11 catches it). */
