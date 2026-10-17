/* ============================================================================
 * Project : RISC-V Network Telemetry SoC
 * File    : sw/src/spike.c
 * Desc    : Phase 0 access spike — can user-mode C reach ICCM and DCCM?
 *
 *           Phase 0 of
 *           doc/Complete_Updated_C_Peripheral_and_Memory_Test_Suite_Plan.md §3.
 *           This file is NOT part of fw0. It is built into its own BUILD dir:
 *             make -C sw BUILD=build/spike MAIN_SRC=src/spike.c all
 *             make -C sim run SW_BUILD=$PWD/sw/build/spike
 *           so the proven fw0 artifacts in sw/build/ are never touched.
 *
 *           THE QUESTION
 *             ICCM 0xEE00_0000..0xEE00_FFFF and DCCM 0xF004_0000..0xF004_FFFF
 *             are enabled, 64 KB each (perl_configs.pl:635-704), backed by
 *             behavioural banks in the TB. But are they reachable from plain C,
 *             or does the core refuse the access?
 *
 *           What is already known, and why no setup is done here:
 *             - PMP defaults to allow-all. pmp_entries=16 but every entry
 *               resets OFF, so no entry matches and access_fault_check leaves
 *               access_fail=0 (el2_pmp.sv:167-178). No PMP programming needed.
 *             - MRAC governs *external* bus regions, not the core-local
 *               memories, so MRAC is not programmed for this spike either.
 *             - The banks have NO reset value — tb/tb_veer_p2_soc.sv:221-246
 *               instantiates ram_4096x39 with no init file. So this probe is
 *               strictly write-then-read and never asserts reset-zero.
 *
 *           IF THE ACCESS FAULTS
 *             The core takes an exception and startup.S:trap_handler parks
 *             forever, so the run ends in the TB watchdog rather than
 *             reporting a value. A timeout is therefore itself the answer:
 *             "not reachable from C without further configuration".
 *
 *           SCOPE LIMIT
 *             This probe touches only word 0 of each region. It answers
 *             "reachable at all?" and nothing more. Bank interleaving,
 *             ECC behaviour and width coverage are Phase 3 work.
 * ==========================================================================*/

#include <stdint.h>
#include "soc.h"

/* Re-verified from build/snapshots/p2_soc/perl_configs.pl on 2026-10-17:
 *   iccm_enable=1 iccm_size=64 iccm_region='0xe' iccm_offset='0xe000000'
 *   dccm_enable=1 dccm_size=64 dccm_region='0xf' dccm_offset='0x40000'
 * These match the ICCM/DCCM guardrails in sw/linker/veer.ld:98-127. */
#define ICCM_BASE   0xEE000000u
#define DCCM_BASE   0xF0040000u

/* Distinct patterns so a swapped or aliased readback is unambiguous. */
#define PROBE_ICCM  0xA5A51234u
#define PROBE_DCCM  0x5A5A5678u

/* MBOX is 16 bytes and the frozen contract owns [0..2] (trigger), [3] (fail
 * code) and [4..7] (0x00003250 signature). Bytes [8..15] are inside the
 * reservation and untouched by startup.S, so the raw readback values can be
 * published there without breaking tb_veer_p2_soc.sv:302-307. */
#define PUB_ICCM_WORD  2u   /* DMEM 0x0001_0008 */
#define PUB_DCCM_WORD  3u   /* DMEM 0x0001_000C */

static volatile uint32_t *const iccm =
    (volatile uint32_t *)(uintptr_t)ICCM_BASE;
static volatile uint32_t *const dccm =
    (volatile uint32_t *)(uintptr_t)DCCM_BASE;
static volatile uint32_t *const mbox =
    (volatile uint32_t *)(uintptr_t)MBOX_BASE;

/* .data is required for more than its own sake: the spike would otherwise
 * have an empty .data, dmem.mem comes out empty, and gate G8 rejects the
 * image. Keeping a non-const .data marker also means the spike image passes
 * the identical G1-G13 gate set as fw0, and incidentally re-proves the
 * startup.S LMA -> VMA copy on the way. Must NOT be const, or it would land
 * in .rodata and .data would empty out anyway. */
static volatile uint32_t data_marker = 0x00C0FFEEu;

/* ------------------------------------------------------------------ */
/* A store followed by a load to the same word. `volatile` on both is
 * load-bearing: without it the compiler may fold the load into the
 * constant store and report success without any bus transaction.      */
static uint32_t write_then_read(volatile uint32_t *p, uint32_t pattern)
{
    *p = pattern;
    return *p;
}

int main(void)
{
    /* Sanity: startup.S copied .data from its IMEM LMA into DMEM. If this
     * fails the boot path is broken and the probe below proves nothing. */
    if (data_marker != 0x00C0FFEEu)
        return 3;

#if defined(SPIKE_ONLY_DCCM) || defined(SPIKE_ONLY_ICCM)
    /* One region per run. A faulting access takes an exception and
     * startup.S:trap_handler parks forever, so probing both in one image
     * would never report the second result. */
    #ifdef SPIKE_ONLY_DCCM
        uint32_t rb_dccm = write_then_read(dccm, PROBE_DCCM);
        mbox[PUB_DCCM_WORD] = rb_dccm;
        return (rb_dccm == PROBE_DCCM) ? 0 : 2;
    #else
        uint32_t rb_iccm = write_then_read(iccm, PROBE_ICCM);
        mbox[PUB_ICCM_WORD] = rb_iccm;
        return (rb_iccm == PROBE_ICCM) ? 0 : 1;
    #endif
#else
    /* Publish first, unconditionally, so the log carries the raw readback
     * even on failure — including the "reads as zero" case, which would
     * otherwise be indistinguishable from a missing publish. */
    uint32_t rb_iccm = write_then_read(iccm, PROBE_ICCM);
    uint32_t rb_dccm = write_then_read(dccm, PROBE_DCCM);

    mbox[PUB_ICCM_WORD] = rb_iccm;
    mbox[PUB_DCCM_WORD] = rb_dccm;

    if (rb_iccm != PROBE_ICCM)
        return 1;
    if (rb_dccm != PROBE_DCCM)
        return 2;

    return 0;   /* PASS -> startup.S writes the mailbox signature */
#endif
}