/* ============================================================================
 * Project : RISC-V Network Telemetry SoC
 * File    : sw/tests/memtest_core.c
 * Desc    : Region-parameterised memory test, shared by IMEM, DMEM and DCCM.
 *
 *           Phase 3 of
 *           doc/Complete_Updated_C_Peripheral_and_Memory_Test_Suite_Plan.md §6.1
 *
 *           One implementation, three regions. The patterns are identical and
 *           only the bounds and capability flags differ, so there is a single
 *           place where a pattern is wrong rather than three that can drift.
 *
 *           A pattern only runs if the region's flags permit it. That is
 *           deliberate: the suite must never assert something the RTL was never
 *           asked to do. In particular ICCM is not offered here at all,
 *           because it has no LSU data route (Phase 0: MEM-10 BLOCKED).
 *
 *           ALIGNMENT
 *           Only naturally aligned 8/16/32-bit accesses are issued. The AHB
 *           SRAM does implement byte lanes (ahb_sram.sv lane_en from size_q and
 *           addr_q[2:0]), but a misaligned access to a side-effect region is a
 *           fault in this core (el2_lsu_addrcheck.sv), and mixing alignment rules
 *           into a memory test would test the LSU's alignment policy rather than
 *           the memory. Unaligned coverage is deliberately out of scope.
 *
 *           COST
 *           Every pattern writes and re-reads, so runtime is roughly
 *           2 x words x patterns transfers. `stride` lets a caller trade
 *           coverage for time without changing any code.
 *
 *           FAILURE REPORTING
 *           On any mismatch the failing address, the expected value, the actual
 *           value, the pattern name and the region name are captured and left in
 *           the memtest_fail_* accessors, so the caller can log all five without
 *           threading a struct through the pattern code.
 * ==========================================================================*/

#include <stdint.h>
#include "soc.h"
#include "test.h"
#include "memtest.h"

/* Layout symbols, so the safety guard can refuse a window that overlaps the
 * machinery doing the reporting. */
extern uint32_t __results_end, __bss_end, __stack_top, __imem_image_end;
extern uint32_t __memtest_dmem_scratch_lo, __memtest_dmem_scratch_hi;

/* ---- last-failure capture ----------------------------------------------- */
static uint32_t f_code;
static uint32_t f_addr;
static uint32_t f_expect;
static uint32_t f_actual;
static const char *f_pattern;
static const char *f_region;

uint32_t memtest_fail_code(void)   { return f_code; }
uint32_t memtest_fail_addr(void)   { return f_addr; }
uint32_t memtest_fail_expect(void) { return f_expect; }
uint32_t memtest_fail_actual(void) { return f_actual; }
const char *memtest_fail_pattern(void) { return f_pattern; }
/* Lets a caller label a failure it detected before memtest_run() ran. */
void memtest_set_pattern(const char *p) { f_pattern = p; }
const char *memtest_fail_region(void)  { return f_region; }

static int fail(const memtest_region_t *r, const char *pattern,
                uint32_t code, uintptr_t addr, uint32_t expect, uint32_t actual)
{
    f_code    = code;
    f_addr    = (uint32_t)addr;
    f_expect  = expect;
    f_actual  = actual;
    f_pattern = pattern;
    f_region  = r->name;
    return (int)code;
}

/* ---- safety ------------------------------------------------------------- */

int memtest_region_safe(const memtest_region_t *r)
{
    uintptr_t lo = r->base;
    uintptr_t hi = lo + r->size;

    if (r->size == 0u || (r->size & 3u) != 0u)
        return 0;
    if ((r->flags & (MEMTEST_F_WIDTH8 | MEMTEST_F_WIDTH16 | MEMTEST_F_WIDTH32))
        == 0u)
        return 0;

#ifdef MEMTEST_GUARD_BROKEN
    /* Negative control ONLY. Deliberately accepts every window so the guard
     * test can prove it detects a loosened guard. Never defined for a real
     * image; test-memory-negative sets it. */
    return 1;
#endif

    /* Region-aware. The reserved-region rules are about the DMEM window only:
     * applying them unconditionally made the IMEM and DCCM windows fail, since
     * an IMEM window naturally starts below __bss_end and a DCCM window
     * naturally ends far above __stack_top.
     *
     * A DMEM window must lie inside the linker-declared scratch bounds, which
     * already exclude the mailbox, .results/.data/.bss and the stack margin.
     * Comparing against the bounds rather than re-deriving each reserved
     * region keeps this correct if the map moves, and — importantly — refuses
     * a window parked just below __stack_top, which an earlier version
     * accepted because it only tested `hi > __stack_top`. */
    if (lo >= DMEM_BASE && lo < DMEM_BASE + DMEM_SIZE) {
        if (lo < (uintptr_t)&__memtest_dmem_scratch_lo) return 0;
        if (hi > (uintptr_t)&__memtest_dmem_scratch_hi) return 0;
    }
    if (lo < IMEM_SIZE) {
        if (lo < (uintptr_t)&__imem_image_end) return 0;  /* code + registry  */
    }
    return 1;
}

/* ---- patterns ----------------------------------------------------------- */

/* Width sweep: one store and one load at every width, at a stride of
 * `stride` elements. Neighbouring elements are checked afterwards so a lane
 * that leaked into its neighbour is caught rather than silently tolerated. */
static int pat_widths(const memtest_region_t *r)
{
    volatile uint8_t  *b = (volatile uint8_t *)(uintptr_t)r->base;
    volatile uint16_t *h = (volatile uint16_t *)(uintptr_t)r->base;
    volatile uint32_t *w = (volatile uint32_t *)(uintptr_t)r->base;
    /* Every pattern iterates WORD indices and derives the byte offset itself,
     * so i < words guarantees every access stays inside the window. Deriving
     * the bound differently per pattern is what let an earlier version walk
     * past its own DMEM window. */
    const uint32_t words = r->size / 4u;
    const uint32_t step  = r->stride;

    if (r->flags & MEMTEST_F_WIDTH32) {
        for (uint32_t i = 0; i < words; i += step) {
            uintptr_t a = r->base + (uintptr_t)i * 4u;
            uint32_t want = 0xA5A50000u ^ i;
            w[i] = want;
            if (w[i] != want)
                return fail(r, "width32", MEMTEST_E_WIDTH, a, want, w[i]);
        }
    }
    if (r->flags & MEMTEST_F_WIDTH16) {
        for (uint32_t i = 0; i < words; i += step) {
            uintptr_t a = r->base + (uintptr_t)i * 4u;
            uint16_t want = (uint16_t)(0x5A5Au ^ (i & 0xFFFFu));
            h[i * 2u] = want;
            if (h[i * 2u] != want)
                return fail(r, "width16", MEMTEST_E_WIDTH, a, want, h[i * 2u]);
        }
    }
    if (r->flags & MEMTEST_F_WIDTH8) {
        for (uint32_t i = 0; i < words; i += step) {
            uintptr_t a = r->base + (uintptr_t)i * 4u;
            uint8_t want = (uint8_t)(0xC3u ^ (i & 0xFFu));
            b[i * 4u] = want;
            if (b[i * 4u] != want)
                return fail(r, "width8", MEMTEST_E_WIDTH, a, want, b[i * 4u]);
        }
    }
    return 0;
}

/* Walking ones and walking zeros, one bit position per element. Uses `v <<= 1`
 * rather than `1u << i`: both compile to RV32 hardware here (the frozen MARCH
 * contains M, and SLL takes a variable shift amount), but the loop form makes
 * the intent explicit and avoids any 64-bit shift helper. */
static int pat_walk(const memtest_region_t *r)
{
    volatile uint32_t *w = (volatile uint32_t *)(uintptr_t)r->base;
    const uint32_t words = r->size / 4u;
    const uint32_t step  = r->stride;
    uint32_t v = 1u;

    for (uint32_t bit = 0; bit < 32u; bit++) {
        for (uint32_t i = 0; i < words; i += step) {
            uintptr_t a = r->base + (uintptr_t)i * 4u;
            w[i] = v;
            if (w[i] != v)
                return fail(r, "walk-ones", MEMTEST_E_WALK, a, v, w[i]);
        }
        v <<= 1;

        for (uint32_t i = 0; i < words; i += step) {
            uintptr_t a = r->base + (uintptr_t)i * 4u;
            w[i] = ~v;
            if (w[i] != ~v)
                return fail(r, "walk-zeros", MEMTEST_E_WALK, a, ~v, w[i]);
        }
    }
    return 0;
}

/* Address-distinct: every element gets a value derived from its own address,
 * so an alias (two addresses backed by one location) or a stuck line shows up
 * as a mismatch instead of passing because every element looks alike. */
static uint32_t addru_value(uintptr_t a)
{
    return (uint32_t)(a * 2654435761u) ^ (uint32_t)a;
}

static int pat_addru(const memtest_region_t *r)
{
    volatile uint32_t *w = (volatile uint32_t *)(uintptr_t)r->base;
    const uint32_t words = r->size / 4u;
    const uint32_t step  = r->stride;

    for (uint32_t i = 0; i < words; i += step) {
        uintptr_t a = r->base + (uintptr_t)i * 4u;
        w[i] = addru_value(a);
    }
    for (uint32_t i = 0; i < words; i += step) {
        uintptr_t a = r->base + (uintptr_t)i * 4u;
        uint32_t want = addru_value(a);
        if (w[i] != want)
            return fail(r, "address-unique", MEMTEST_E_ADDRU, a, want, w[i]);
    }
    return 0;
}

/* Retention: write a known set, walk the whole region with a different
 * pattern, then re-read. Catches destructive refresh and store buffering that
 * only shows once other traffic has intervened. */
static int pat_retention(const memtest_region_t *r)
{
    volatile uint32_t *w = (volatile uint32_t *)(uintptr_t)r->base;
    const uint32_t words = r->size / 4u;
    const uint32_t step  = r->stride;
    const uint32_t marker = 0x5EED1234u;

    for (uint32_t i = 0; i < words; i += step)
        w[i] = marker;

    for (uint32_t i = 0; i < words; i += step)
        w[i] = ~marker;              /* unrelated traffic in between */

    for (uint32_t i = 0; i < words; i += step)
        w[i] = marker;
    for (uint32_t i = 0; i < words; i += step) {
        uintptr_t a = r->base + (uintptr_t)i * 4u;
        if (w[i] != marker)
            return fail(r, "retention", MEMTEST_E_RETENTION, a, marker, w[i]);
    }
    return 0;
}

/* Boundary: the first and last legal element of the window, written and read
 * back. A region whose decode is off by one fails here and nowhere else. */
static int pat_boundary(const memtest_region_t *r)
{
    volatile uint32_t *w = (volatile uint32_t *)(uintptr_t)r->base;
    const uint32_t last = (r->size / 4u) - 1u;
    const uint32_t marker = 0xB0B0F00Du;

    w[0] = marker;
    if (w[0] != marker)
        return fail(r, "boundary-first", MEMTEST_E_BOUNDARY,
                    r->base, marker, w[0]);

    w[last] = marker;
    if (w[last] != marker)
        return fail(r, "boundary-last", MEMTEST_E_BOUNDARY,
                    r->base + (uintptr_t)last * 4u, marker, w[last]);
    return 0;
}

/* ---- driver ------------------------------------------------------------- */

int memtest_run(const memtest_region_t *r)
{
    int rc;

    f_code = MEMTEST_OK;

    if (!memtest_region_safe(r))
        return fail(r, "region-unsafe", MEMTEST_E_WIDTH, r->base,
                    (uint32_t)r->size, 0u);

    if ((r->flags & MEMTEST_F_WIDTH32) && (rc = pat_widths(r)) != 0)
        return rc;
    if ((r->flags & MEMTEST_F_WALK)    && (rc = pat_walk(r)) != 0)
        return rc;
    if ((r->flags & MEMTEST_F_ADDRU)   && (rc = pat_addru(r)) != 0)
        return rc;
    if ((r->flags & MEMTEST_F_BOUNDARY)&& (rc = pat_boundary(r)) != 0)
        return rc;
    if ((r->flags & MEMTEST_F_RETENTION) && (rc = pat_retention(r)) != 0)
        return rc;

    return MEMTEST_OK;
}