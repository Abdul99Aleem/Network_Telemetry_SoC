/* ============================================================================
 * Project : RISC-V Network Telemetry SoC
 * File    : sw/tests/test_main.c
 * Desc    : Test-suite runner — discovers .test_list, runs each case, writes
 *           the result table that the testbench reads.
 *
 *           Phase 1 of
 *           doc/Complete_Updated_C_Peripheral_and_Memory_Test_Suite_Plan.md §4.
 *
 *           Discovery is purely link-driven: __test_list_start /
 *           __test_list_end come from sw/linker/veer.ld, and each test file
 *           adds cases with TEST_CASE(). Adding a test never requires editing
 *           this file, and the runner needs no knowledge of any test.
 *
 *           FAILURE POLICY
 *             All cases always run, even after one fails, so a single image
 *             reports the full picture rather than only the first problem. The
 *             first failure is latched (index, code, got, want) for waveform
 *             diagnosis without a re-run. The exit code is non-zero when
 *             anything failed, which is what startup.S turns into the mailbox
 *             FAIL path.
 *
 *           ZERO CASES IS AN ERROR, not an empty pass: a suite that silently
 *           registers nothing would report PASS and prove nothing.
 *
 *           Phase 1 ships the framework only. The cases below are deliberately
 *           trivial — their job is to prove the registry, the result table and
 *           the PASS path work end to end before any real assertion is built
 *           on them. Real cases land in Phase 3 (memory) and Phase 4 (UART).
 *
 *           -DTEST_NEGATIVE_CONTROL adds a case that must fail. The suite
 *           target does not define it and must pass; the negative-control
 *           target does define it and must fail. See doc/Phase1_*_Record.md.
 * ==========================================================================*/

#include <stdint.h>
#include "soc.h"
#include "test.h"
#include "uart.h"

/* Supplied by the linker (sw/linker/veer.ld). */
extern const test_case_t __test_list_start[];
extern const test_case_t __test_list_end[];

/* The result table lives in .results (NOLOAD) so it occupies no bytes in
 * imem.mem / dmem.mem. Deliberately not in .bss: startup.S clears .bss before
 * main() runs, and the table must survive that. */
__attribute__((section(".results"), used))
static volatile test_results_hdr_t results;

__attribute__((section(".results"), used))
static volatile test_results_ent_t entries[RESULTS_MAX_ENT];

#define ENTRY_NOT_RUN 0xFFFFFFFFu

/* Index of the case currently executing, published to test_record_failure by
 * the runner. Using the index rather than a name lookup avoids the mismatch
 * that made an earlier version of this file latch every failure against the
 * sentinel: TEST_CASE stores the stringified function name ("t_dmem"), while
 * CHECK_* passes a check label ("selftest/dmem"), so the two are different
 * string literals and never compared equal. */
static uint32_t g_cur_idx;

/* ------------------------------------------------------------- reporting -- */

void test_set_current(uint32_t idx)
{
    g_cur_idx = idx;
}

/* Latch the first failure only; later ones still get their own entry. */
static void latch_first_fail(uint32_t idx, uint32_t code,
                             uint32_t got, uint32_t want)
{
    if (results.first_fail_idx == TEST_NO_FAIL) {
        results.first_fail_idx  = idx;
        results.first_fail_code = code;
        results.first_fail_got  = got;
        results.first_fail_want = want;
    }
}

void test_record_failure(const char *name, uint32_t code,
                         uint32_t got, uint32_t want)
{
    /* name is carried for the Phase 2 UART log; the table is indexed. */
    (void)name;

    /* Record the code on the current row so the per-entry view and the header
     * agree, then latch the first failure with the observed/expected pair. */
    if (g_cur_idx < RESULTS_MAX_ENT)
        entries[g_cur_idx].code = code;

    latch_first_fail(g_cur_idx, code, got, want);
}

/* ------------------------------------------------------------------ cases -- */

/* .rodata lives in IMEM and is fetched through the fabric. */
static const volatile uint32_t ro_marker = 0xDEC0DE01u;

/* Proves .bss really was cleared by startup.S before main() ran. */
static volatile uint32_t bss_probe[4];

static int t_selftest(void)
{
    CHECK_EQ("selftest/rodata", ro_marker, 0xDEC0DE01u);
    return 0;
}

static int t_bss_is_zero(void)
{
    for (uint32_t i = 0; i < 4u; i++)
        CHECK_EQ("selftest/bss", bss_probe[i], 0u);
    return 0;
}

/* Proves a data store/load round-trip reaches DMEM and reads back. */
static int t_dmem_roundtrip(void)
{
    static volatile uint32_t scratch[4];

    for (uint32_t i = 0; i < 4u; i++)
        scratch[i] = 0xC0DE0000u + i;
    for (uint32_t i = 0; i < 4u; i++)
        CHECK_EQ("selftest/dmem", scratch[i], 0xC0DE0000u + i);
    return 0;
}

/* Phase 2: proves the UART really shifts bits out, by checking the status the
 * transmitter reports once it is idle. This is the only status register the
 * wrapper serves a real read for, so it is the only one that can be trusted.
 * The actual byte-level check is done by the testbench, which decodes the line
 * and cross-checks it against the DMEM table.
 */
static int t_uart_status(void)
{
    CHECK_EQ("uart/thre", UART_REG32(UART_OFF_LSR) & UART_LSR_THRE,
             UART_LSR_THRE);
    CHECK_EQ("uart/temt", UART_REG32(UART_OFF_LSR) & UART_LSR_TEMT,
             UART_LSR_TEMT);
    return 0;
}

#ifdef TEST_NEGATIVE_CONTROL
/* Must fail, and the suite must therefore report FAIL. */
static int t_negative_control(void)
{
    CHECK_EQ("selftest/negative", (uint32_t)1u, (uint32_t)2u);
    return 0;
}
#endif

TEST_CASE(t_selftest)
TEST_CASE(t_bss_is_zero)
TEST_CASE(t_dmem_roundtrip)
TEST_CASE(t_uart_status)
#ifdef TEST_NEGATIVE_CONTROL
TEST_CASE(t_negative_control)
#endif

/* ---------------------------------------------------------- serial report --
 * Transcript format, mirrored by the parser in tb/tb_veer_p2_soc.sv:
 *
 *   SUITE_BEGIN
 *   T<idx> <test-name> PASS|FAIL
 *   ...
 *   SUITE_END ntests=<n> npass=<p> nfail=<f> first_fail=<i> code=<c> \
 *            got=0xXXXXXXXX want=0xXXXXXXXX
 *
 * The testbench does not string-compare this against a golden transcript; it
 * parses the fields and cross-checks every one of them against the DMEM result
 * table. That is what makes "UART and DMEM agree" a checked claim rather than
 * an assertion, and it is why the format above is a contract.
 *
 * SUITE_BEGIN deliberately starts with 'S' = 0x53, which has bit0 set. The
 * testbench calibrates its bit period from the first byte by timing the rising
 * edge one bit period after the start bit's falling edge, which is only valid
 * when bit0 is 1. Changing this first character would break that calibration.
 */
static void report_line(uint32_t idx, const char *name, int code)
{
    uart_puts("T");
    uart_putdec(idx);
    uart_putc(' ');
    uart_puts(name);
    uart_puts(code == 0 ? " PASS\n" : " FAIL\n");
}

static void report_summary(void)
{
    uart_puts("SUITE_END ntests=");
    uart_putdec(results.ntests);
    uart_puts(" npass=");
    uart_putdec(results.npass);
    uart_puts(" nfail=");
    uart_putdec(results.nfail);
    uart_puts(" first_fail=");
    uart_putdec(results.first_fail_idx);
    uart_puts(" code=");
    uart_putdec(results.first_fail_code);
    uart_puts(" got=");
    uart_puthex32(results.first_fail_got);
    uart_puts(" want=");
    uart_puthex32(results.first_fail_want);
    uart_putc('\n');
}

/* ------------------------------------------------------------------- main -- */

int main(void)
{
    const uint32_t n = (uint32_t)(__test_list_end - __test_list_start);

    /* Publish the count before running anything, so a hang still leaves a
     * parseable header behind for waveform diagnosis. */
    results.magic           = TEST_MAGIC;
    results.ntests          = n;
    results.npass           = 0;
    results.nfail           = 0;
    results.first_fail_idx  = TEST_NO_FAIL;
    results.first_fail_code = 0;
    results.first_fail_got  = 0;
    results.first_fail_want = 0;

    /* Serial first, so a fault in uart_init itself is still visible. */
    uart_init();
    uart_puts("SUITE_BEGIN\n");

    if (n == 0u || n > RESULTS_MAX_ENT)
        return 1;   /* empty or oversized registry is a framework failure */

    for (uint32_t i = 0; i < n; i++) {
        int code;

        if (i < RESULTS_MAX_ENT) {
            entries[i].name = __test_list_start[i].name;
            entries[i].code = ENTRY_NOT_RUN;
        }

        test_set_current(i);
        code = __test_list_start[i].fn();

        /* Record the outcome for EVERY case, pass or fail. Recording only the
         * failures (an earlier version of this loop) left a passing case
         * sitting at the ENTRY_NOT_RUN sentinel, which the recount below then
         * counted as a failure -- so an all-green suite reported FAIL. */
        if (i < RESULTS_MAX_ENT)
            entries[i].code = (uint32_t)code;

        if (code == 0)
            results.npass++;
        else
            latch_first_fail(i, (uint32_t)code, 0u, 0u);

        report_line(i, __test_list_start[i].name, code);
    }

    /* Recount from the per-entry codes so the two can never disagree, which
     * would make the table untrustworthy as evidence. A case still holding the
     * sentinel did not return at all, so count it as a failure rather than
     * letting the totals quietly under-report. */
    results.npass = 0;
    results.nfail = 0;
    for (uint32_t i = 0; i < n && i < RESULTS_MAX_ENT; i++) {
        if (entries[i].code == 0u)
            results.npass++;
        else
            results.nfail++;
    }

    /* A serial fault is itself a suite failure: a run that could not report its
     * results has not demonstrated anything, whatever the tests concluded. */
    if (uart_error()) {
        results.nfail++;
        if (results.first_fail_idx == TEST_NO_FAIL) {
            results.first_fail_idx  = TEST_NO_FAIL;
            results.first_fail_code = 0xF00Du;   /* 'serial fault' marker */
        }
    }

    report_summary();

    /* Drain BEFORE returning. startup.S writes the mailbox trigger immediately
     * after main() returns and the testbench may $finish on that trigger, so
     * leaving the transmitter mid-byte would truncate the transcript. */
    uart_drain();

    return (results.nfail == 0u) ? 0 : 1;
}