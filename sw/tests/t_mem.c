/* ============================================================================
 * Project : RISC-V Network Telemetry SoC
 * File    : sw/tests/t_mem.c
 * Desc    : MEM-01/02/03/04/05/06/07/08/09/11 over IMEM, DMEM and DCCM.
 *
 *           Phase 3 of
 *           doc/Complete_Updated_C_Peripheral_and_Memory_Test_Suite_Plan.md §6.2
 *
 *           SAFETY IS ESTABLISHED FROM LINKER SYMBOLS, NOT ASSUMPTIONS
 *           Every window below is derived from a symbol the linker exports, and
 *           veer.ld ASSERTs their ordering. Concretely:
 *
 *             DMEM scratch  = [ __memtest_dmem_scratch_lo , __memtest_dmem_scratch_hi )
 *                              = [ align_up(__bss_end,32) , __stack_top - 4096 )
 *             IMEM scratch  = [ __imem_image_end , 0x0000_8000 )
 *
 *           That excludes the 16-byte mailbox (0x0001_0000), .results
 *           (0x0001_0010..), .data, .bss, and the stack. The ASSERTs at the
 *           bottom of veer.ld fail the LINK if any of those ever overlap, so a
 *           memory test cannot silently overwrite the machinery that reports its
 *           own result.
 *
 *           BOUNDED FIRST, EXPANDED LATER
 *           MEMTEST_STRIDE and MEMTEST_WINDOW_* cap the first run so the safe
 *           ranges and the runtime can be measured before committing to a full
 *           32/64 KB sweep. See doc/Phase3_Memory_and_Bus_Record.md §3 for the
 *           measurements that justify the current values.
 *
 *           ICCM IS DELIBERATELY ABSENT
 *           MEM-10 is BLOCKED - RTL/ARCH. ICCM is driven by the IFU
 *           (el2_ifu_iccm_mem) and has no LSU data route, so a C access falls
 *           through to the AHB ERROR slave — which t_bus.c asserts directly
 *           rather than pretending it is a memory region.
 * ==========================================================================*/

#include <stdint.h>
#include "soc.h"
#include "test.h"
#include "uart.h"
#include "memtest.h"

/* Linker-exported scratch bounds (veer.ld). */
extern uint32_t __memtest_dmem_scratch_lo;
extern uint32_t __memtest_dmem_scratch_hi;

/* Element stride between tested addresses, and the window cap per region. Both
 * are compile-time so a run is reproducible and a change is visible in the
 * commit that made it. */
#ifndef MEMTEST_STRIDE
#define MEMTEST_STRIDE 4u
#endif

#ifndef MEMTEST_WINDOW_DMEM
#define MEMTEST_WINDOW_DMEM 4096u
#endif
#ifndef MEMTEST_WINDOW_IMEM
#define MEMTEST_WINDOW_IMEM 1024u
#endif
#ifndef MEMTEST_WINDOW_DCCM
#define MEMTEST_WINDOW_DCCM 4096u
#endif

#define ALL_WIDTHS (MEMTEST_F_WIDTH8 | MEMTEST_F_WIDTH16 | MEMTEST_F_WIDTH32)

/* ---- window builders ----------------------------------------------------
 * Each returns 0 (unsafe) rather than letting the caller sweep something it
 * should not.
 */
static int dmem_window(memtest_region_t *r)
{
    uintptr_t lo = (uintptr_t)&__memtest_dmem_scratch_lo;
    uintptr_t hi = (uintptr_t)&__memtest_dmem_scratch_hi;



    if (hi <= lo)
        return 0;
    if ((hi - lo) > MEMTEST_WINDOW_DMEM)
        hi = lo + MEMTEST_WINDOW_DMEM;
    hi &= ~(uintptr_t)3u;

    r->name  = "DMEM";
    r->base  = lo;
    r->size  = (uint32_t)(hi - lo);
    r->flags = ALL_WIDTHS | MEMTEST_ALL_PATTERNS;
    r->stride = MEMTEST_STRIDE;
    return 1;
}

/* IMEM scratch begins at __imem_image_end, which the linker now defines as the
 * maximum of the .data load end and the .test_list end, so the registry cannot
 * be clobbered. Nothing is placed above it in IMEM. */
static int imem_window(memtest_region_t *r)
{
    uintptr_t lo = (uintptr_t)&__imem_image_end;
    uintptr_t hi = 0x00008000u;

    if (hi <= lo)
        return 0;
    if ((hi - lo) > MEMTEST_WINDOW_IMEM)
        hi = lo + MEMTEST_WINDOW_IMEM;
    hi &= ~(uintptr_t)3u;

    r->name  = "IMEM";
    r->base  = lo;
    r->size  = (uint32_t)(hi - lo);
    r->flags = ALL_WIDTHS | MEMTEST_ALL_PATTERNS;
    r->stride = MEMTEST_STRIDE;
    return 1;
}

/* DCCM is LSU-accessible and has NO reset value: the TB's ram_4096x39 banks are
 * uninitialised, so every location is written before it is read and no pattern
 * asserts reset-zero. Verified reachable in Phase 0 (dccm_rb=5a5a5678). */
static int dccm_window(memtest_region_t *r)
{
    uintptr_t lo = DCCM_BASE;
    uintptr_t hi = DCCM_BASE + DCCM_SIZE;

    if ((hi - lo) > MEMTEST_WINDOW_DCCM)
        hi = lo + MEMTEST_WINDOW_DCCM;
    hi &= ~(uintptr_t)3u;

    r->name  = "DCCM";
    r->base  = lo;
    r->size  = (uint32_t)(hi - lo);
    r->flags = ALL_WIDTHS | MEMTEST_ALL_PATTERNS | MEMTEST_F_NO_RESET;
    r->stride = MEMTEST_STRIDE;
    return 1;
}

/* Report a pattern failure with full detail: region, pattern, address,
 * expected and actual. This is what makes a red run diagnosable from the log.
 */
static int report(memtest_region_t *r, int rc, const char *why)
{
    /* Silent on success. An earlier version printed MEMFAIL unconditionally,
     * which put three alarming-looking lines into a passing log. */
    if (rc == MEMTEST_OK)
        return 0;

    /* Set the pattern slot for paths that never reached memtest_run(), so the
     * line never carries an unset (NULL) pointer to the UART formatter. */
    if (memtest_fail_pattern() == 0)
        memtest_set_pattern(why);

    uart_puts("MEMFAIL region=");
    uart_puts(r->name);
    uart_puts(" pattern=");
    uart_puts(memtest_fail_pattern() ? memtest_fail_pattern() : "unknown");
    uart_puts(" addr=");
    uart_puthex32(memtest_fail_addr());
    uart_puts(" expect=");
    uart_puthex32(memtest_fail_expect());
    uart_puts(" actual=");
    uart_puthex32(memtest_fail_actual());
    uart_puts(" code=");
    uart_putdec((uint32_t)rc);
    uart_putc('\n');

    test_record_failure("mem/pattern", (uint32_t)rc,
                        memtest_fail_actual(), memtest_fail_expect());
    return rc;
}

/* ---- the tests ---------------------------------------------------------- */

static int t_mem_dmem(void)
{
    memtest_region_t r;

    if (!dmem_window(&r))
        return report(&r, MEMTEST_E_WIDTH, "window-build-failed");
    if (!memtest_region_safe(&r))
        return report(&r, MEMTEST_E_WIDTH, "window-refused-unsafe");
    return report(&r, memtest_run(&r), 0);
}

static int t_mem_imem(void)
{
    memtest_region_t r;

    if (!imem_window(&r))
        return report(&r, MEMTEST_E_WIDTH, "window-build-failed");
    if (!memtest_region_safe(&r))
        return report(&r, MEMTEST_E_WIDTH, "window-refused-unsafe");
    return report(&r, memtest_run(&r), 0);
}

static int t_mem_dccm(void)
{
    memtest_region_t r;

    if (!dccm_window(&r))
        return report(&r, MEMTEST_E_WIDTH, "window-build-failed");
    if (!memtest_region_safe(&r))
        return report(&r, MEMTEST_E_WIDTH, "window-refused-unsafe");
    return report(&r, memtest_run(&r), 0);
}

/* ---- control for the safety guard -----------------------------------
 * Builds a window deliberately overlapping the result table and asserts the
 * guard REFUSES it, then builds one in the reserved stack margin and asserts
 * refusal again, and finally asserts the real DMEM window is ACCEPTED. This is
 * the control for the control: without it, a regression that loosened
 * memtest_region_safe() would let a destructive pattern overwrite the very
 * results table doing the reporting, and the suite could then report PASS while
 * having destroyed its own evidence.
 *
 * It asserts the guard's verdict rather than running a pattern, so it is safe:
 * an earlier version actually performed the unsafe pattern and wedged the run.
 *
 * Always compiled. test-memory-negative builds the same test with
 * -DMEMTEST_GUARD_BROKEN so the guard accepts everything and these assertions
 * MUST fail, proving the test detects a loosened guard.
 */
static int t_mem_guard_refuses_unsafe(void)
{
    memtest_region_t bad;
    memtest_region_t good;

    bad.name  = "UNSAFE";
    bad.base  = (uintptr_t)&__results_start;   /* the result table itself */
    bad.size  = 512u;
    bad.flags = MEMTEST_F_WIDTH32 | MEMTEST_ALL_PATTERNS;
    bad.stride = 1u;

    CHECK_EQ("mem/guard_refuses_results", memtest_region_safe(&bad), 0);

    bad.base = (uintptr_t)&__stack_top - 512u; /* straddles the stack ceiling */
    CHECK_EQ("mem/guard_refuses_stack", memtest_region_safe(&bad), 0);

    /* And the guard must still accept the real DMEM window, or "refuses
     * everything" would pass this control too. */
    if (!dmem_window(&good))
        return MEMTEST_E_WIDTH;
    CHECK_EQ("mem/guard_accepts_dmem", memtest_region_safe(&good), 1);

    return 0;
}

TEST_CASE(t_mem_guard_refuses_unsafe)

/* MEM-09 region isolation: writing a pattern across the DMEM scratch must not
 * disturb the mailbox or the result table, which are the very things reporting
 * this test. Checking them afterwards is what makes the claim real rather than
 * assumed. */
static int t_mem_isolation(void)
{
    memtest_region_t r;
    volatile uint8_t *mbox = (volatile uint8_t *)(uintptr_t)&__mbox_base;
    uint32_t saved_mbox[4];

    if (!dmem_window(&r))
        return report(&r, MEMTEST_E_WIDTH, "window-build-failed");
    if (!memtest_region_safe(&r))
        return report(&r, MEMTEST_E_WIDTH, "window-refused-unsafe");

    /* Snapshot the mailbox signature before the destructive pass. */
    for (uint32_t i = 0; i < 4u; i++)
        saved_mbox[i] = *(volatile uint32_t *)(uintptr_t)(&__mbox_base + i * 4u);

    (void)memtest_run(&r);

    for (uint32_t i = 0; i < 4u; i++) {
        uint32_t now = *(volatile uint32_t *)(uintptr_t)(&__mbox_base + i * 4u);
        CHECK_EQ("mem/mbox_intact", now, saved_mbox[i]);
    }

    /* The result table must still carry its own magic: if a destructive
     * pattern had reached it, this is where that would show. */
    CHECK_EQ("mem/results_magic", results.magic, TEST_MAGIC);
    (void)mbox;
    return 0;
}

TEST_CASE(t_mem_dmem)
TEST_CASE(t_mem_imem)
TEST_CASE(t_mem_dccm)
TEST_CASE(t_mem_isolation)