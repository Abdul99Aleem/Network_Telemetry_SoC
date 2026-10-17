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
 * Unreachable during fw0. Reached only if a fetch/load address error or an
 * illegal instruction escapes: park without touching the mailbox so the TB
 * watchdog reports a timeout rather than a spurious PASS.
 * ==========================================================================*/
    .align  2
    .globl  trap_handler
    .type   trap_handler, @function
trap_handler:
1:  j       1b
    .size   trap_handler, . - trap_handler

    /* main() lives in main.c; provide no weak alias so a missing main is a
     * link error (gate G5/G11 catches it). */
