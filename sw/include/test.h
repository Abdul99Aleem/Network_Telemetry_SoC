/* ============================================================================
 * Project : RISC-V Network Telemetry SoC
 * File    : sw/include/test.h
 * Desc    : Bare-metal test framework — registry, result table, assertions.
 *
 *           Phase 1 of
 *           doc/Complete_Updated_C_Peripheral_and_Memory_Test_Suite_Plan.md §4.
 *
 *           Design constraints this file exists to satisfy:
 *
 *           1. Freestanding. -nostdlib is mandatory (sw/Makefile Amendment A1)
 *              and /opt/riscv has no RV32 multilib, so there is no libgcc to
 *              fall back on. Nothing here may allocate, and nothing may need
 *              a 64-bit division helper (`__udivdi3` does not exist).
 *
 *           2. Zero edit cost to add a test. A test file declares its cases
 *              with TEST_CASE() and that is all — the linker collects them
 *              from a section, so no registry list needs maintaining and the
 *              runner needs no knowledge of individual tests.
 *
 *           3. No silent failure. A test returns 0 for pass and non-zero for
 *              fail. First failure (index, code, and the offending value) is
 *              latched in the result table so a red run is debuggable without
 *              re-running.
 *
 *           4. MMIO must stay volatile. Repeated polls of a peripheral status
 *              register are also defeated at the hardware level by the LSU
 *              load buffer unless MRAC marks the region side-effecting
 *              (set in startup.S). `volatile` is the software half of that;
 *              without it the compiler can elide the load and the test passes
 *              having touched no hardware.
 * ==========================================================================*/
#ifndef TEST_H
#define TEST_H

#include <stdint.h>

/* ---------------------------------------------------------------- types -- */

/* A test returns 0 for pass, non-zero as its fail code. */
typedef struct {
    const char *name;      /* stringified from the function name */
    int       (*fn)(void);
} test_case_t;

/* ------------------------------------------------------- result mailbox --
 * Lives at RESULTS_BASE (first word of the DMEM region) and is read
 * hierarchically by the testbench via u_soc.u_dmem.mem[]. NOLOAD, so it costs
 * no bytes in imem.mem / dmem.mem.
 *
 * Entry size is deliberately 8 bytes and the whole table is 4-byte aligned so
 * the TB can walk it with plain byte-lane reads without knowing C struct
 * padding.
 */
#define TEST_MAGIC        0x54534553u    /* 'T''E''S''T' */
#define RESULTS_BASE      0x00010010u    /* = DMEM region origin */
#define RESULTS_MAX_ENT   64u            /* fixed reservation; see gate G15 */
#define RESULTS_HDR_BYTES 32u
#define RESULTS_ENT_BYTES 8u
#define RESULTS_BYTES     (RESULTS_HDR_BYTES + RESULTS_MAX_ENT * RESULTS_ENT_BYTES)

typedef struct {
    uint32_t magic;             /* TEST_MAGIC, written first by the runner  */
    uint32_t ntests;            /* entries discovered in .test_list         */
    uint32_t npass;
    uint32_t nfail;
    uint32_t first_fail_idx;    /* index into .test_list, or TEST_NO_FAIL   */
    uint32_t first_fail_code;   /* what that test returned                  */
    uint32_t first_fail_got;    /* observed value at the failing check      */
    uint32_t first_fail_want;   /* expected value at the failing check      */
} test_results_hdr_t;

typedef struct {
    const char *name;           /* pointer into .rodata (IMEM)              */
    uint32_t    code;           /* 0 = pass, non-zero = that test's code    */
} test_results_ent_t;

#define TEST_NO_FAIL 0xFFFFFFFFu

/* ------------------------------------------------------------- registry --
 * TEST_CASE emits one entry into .test_list. The linker wraps it with
 * __test_list_start / __test_list_end, so the runner discovers tests purely
 * from the link. `used` is required: without it --gc-sections drops a section
 * nothing references.
 */
#define TEST_CASE(fn)                                            \
    static const test_case_t tc_##fn                             \
        __attribute__((section(".test_list"), used))             \
        = { #fn, fn };

extern const test_case_t __test_list_start[];
extern const test_case_t __test_list_end[];

/* ------------------------------------------------------------- reporting --
 * Called by CHECK_* before returning, so the failure is recorded even if the
 * caller ignores the return value.
 *
 * `name` is diagnostics only (it will carry the check label to the UART once
 * Phase 2 lands). The result table is NOT looked up by name: TEST_CASE stores
 * the stringified *function* name, which is a different literal from the
 * label a CHECK_* passes, so a pointer or content comparison would never
 * match. The runner instead publishes the current index via
 * test_set_current(), which is why this works regardless of naming.
 */
void test_record_failure(const char *name, uint32_t code,
                         uint32_t got, uint32_t want);

/* Runner hook: tells the reporter which .test_list entry is executing, so a
 * failure is attributed to the right row without any string matching. */
void test_set_current(uint32_t idx);

/* The live result table, so a memory test can assert that its own destructive
 * patterns did NOT reach the reporting machinery. Declared here rather than
 * duplicated: test_main.c owns the single definition. */
extern volatile test_results_hdr_t results;

/* ------------------------------------------------------------ assertions --
 * Every macro records the failure and returns non-zero from the enclosing
 * test. Volatile-qualified operands are preserved through the cast so an MMIO
 * read is issued exactly once, before any comparison.
 */
#define CHECK_EQ(what, got, want)                                          \
    do {                                                                   \
        uint32_t _g = (uint32_t)(got);                                     \
        uint32_t _w = (uint32_t)(want);                                    \
        if (_g != _w) {                                                    \
            test_record_failure((what), 1u, _g, _w);                       \
            return 1;                                                      \
        }                                                                  \
    } while (0)

#define CHECK_TRUE(what, cond)                                             \
    do {                                                                   \
        if (!(cond)) {                                                     \
            test_record_failure((what), 2u, 0u, 1u);                       \
            return 2;                                                      \
        }                                                                  \
    } while (0)

/* Bounded poll: every hardware wait must terminate. `expr` is re-evaluated
 * each iteration and must be a volatile MMIO read, or this spins forever.
 */
#define CHECK_POLL(what, expr, limit)                                      \
    do {                                                                   \
        uint32_t _n = 0;                                                   \
        while (!(expr)) {                                                  \
            if (++_n > (uint32_t)(limit)) {                                \
                test_record_failure((what), 3u, _n, (uint32_t)(limit));    \
                return 3;                                                  \
            }                                                              \
        }                                                                  \
    } while (0)

#endif /* TEST_H */