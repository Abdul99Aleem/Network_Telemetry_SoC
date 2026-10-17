/* ============================================================================
 * Project : RISC-V Network Telemetry SoC
 * File    : sw/include/memtest.h
 * Desc    : Region safety bounds and the shared memory-test core interface.
 *
 *           Phase 3 of
 *           doc/Complete_Updated_C_Peripheral_and_Memory_Test_Suite_Plan.md §6.
 *
 *           WHY EVERY BOUND IS LINKER-EXPORTED
 *           A memory test that hard-codes 0x0001_0010 or assumes ".bss ends
 *           somewhere harmless" is one linker-script edit away from overwriting
 *           its own result table or running off the stack. Every bound below is
 *           a linker symbol, so the linker fails the build rather than the
 *           simulation if the map changes underneath the tests.
 *
 *           THE THREE RESERVED THINGS A TEST MUST NEVER TOUCH
 *             1. the 16-byte mailbox at MBOX_BASE          (startup.S / TB)
 *             2. .results, .data, .bss                      (runner state)
 *             3. the stack, which grows down from __stack_top
 *           Scratch is therefore placed strictly after __bss_end and strictly
 *           below __stack_top - MEMTEST_STACK_RESERVE.
 * ==========================================================================*/
#ifndef MEMTEST_H
#define MEMTEST_H

#include <stdint.h>

/* ---- linker-exported layout (sw/linker/veer.ld) ------------------------- */
extern uint32_t __mbox_base;          /* 0x0001_0000                     */
extern uint32_t __mbox_size;          /* 16                              */
extern uint32_t __results_start;      /* 0x0001_0010, start of .results  */
extern uint32_t __results_end;        /* end of .results                 */
extern uint32_t __data_start;
extern uint32_t __data_end;
extern uint32_t __bss_start;
extern uint32_t __bss_end;
extern uint32_t __stack_top;          /* 0x0001_8000                     */
extern uint32_t __stack_size;
extern uint32_t __imem_image_end;     /* first free byte above the image  */

/* ---- region geometry ----------------------------------------------------- */
#define IMEM_BASE     0x00000000u
#define IMEM_SIZE     0x00008000u
#define DMEM_BASE     0x00010000u
#define DMEM_SIZE     0x00008000u
#define DCCM_BASE     0xF0040000u      /* LSU-accessible, verified Phase 0 */
#define DCCM_SIZE     0x00010000u      /* 64 KB                            */

/* ICCM (0xEE000000) is intentionally absent from this header. It is
 * IFU-driven instruction memory (el2_ifu_iccm_mem) with no LSU data route, so
 * a C load/store falls through to the AHB ERROR slave. MEM-10 is therefore
 * BLOCKED - RTL/ARCH and must not be treated as a data-memory region. The only
 * correct assertion about that range is that it errors, which t_bus.c makes. */

/* Stack the tests themselves need while running. __stack_top - __bss_end is
 * already asserted >= 512 by the linker, but the memory tests recurse through
 * check helpers, so reserve a generous margin and keep it out of scratch. */
#define MEMTEST_STACK_RESERVE 4096u

/* ---- capability flags ----------------------------------------------------
 * A region only gets the patterns its architecture actually supports, so the
 * suite can never assert something the RTL was never asked to do.
 */
#define MEMTEST_F_WIDTH8    0x0001u   /* byte store/load                 */
#define MEMTEST_F_WIDTH16   0x0002u   /* halfword store/load             */
#define MEMTEST_F_WIDTH32   0x0004u   /* word store/load                 */
#define MEMTEST_F_WALK      0x0008u   /* walking ones / walking zeros    */
#define MEMTEST_F_ADDRU     0x0010u   /* address-distinct pattern        */
#define MEMTEST_F_ISOLATION 0x0020u   /* region-isolation check          */
#define MEMTEST_F_RETENTION 0x0040u   /* re-read after unrelated traffic */
#define MEMTEST_F_BOUNDARY  0x0080u   /* first/last legal word           */

/* Regions whose backing storage has no reset value must be written before
 * they are read; there is no reset-zero pattern to assert. */
#define MEMTEST_F_NO_RESET  0x0100u

#define MEMTEST_ALL_PATTERNS (MEMTEST_F_WALK | MEMTEST_F_ADDRU | \
                              MEMTEST_F_ISOLATION | MEMTEST_F_RETENTION | \
                              MEMTEST_F_BOUNDARY)

/* ---- failure reporting ---------------------------------------------------
 * The suite reports the failing address, the expected value, the actual value
 * and a test identifier, so a red run is diagnosable from the log without
 * re-running. Code ranges let the caller group them.
 */
#define MEMTEST_OK           0
#define MEMTEST_E_WIDTH      1   /* a width the region does not support    */
#define MEMTEST_E_WALK       2
#define MEMTEST_E_ADDRU      3
#define MEMTEST_E_BOUNDARY   4
#define MEMTEST_E_RETENTION  5
#define MEMTEST_E_ISOLATION  6
#define MEMTEST_E_NO_TRAP    7   /* expected exception did not happen     */
#define MEMTEST_E_UNEXPECTED_TRAP 8 /* a trap with no expectation armed    */

/* ---- API ----------------------------------------------------------------- */

typedef struct {
    const char *name;       /* region name, e.g. "DMEM"                 */
    uintptr_t   base;       /* first byte of the SCRATCH window        */
    uint32_t    size;       /* bytes; always a multiple of 4           */
    uint32_t    flags;      /* MEMTEST_F_* capability set              */
    uint32_t    stride;     /* element count between tested addresses  */
} memtest_region_t;

/* Runs every pattern the region's flags allow. Returns MEMTEST_OK or a
 * MEMTEST_E_* code. On failure the details are left in the accessors below. */
int memtest_run(const memtest_region_t *r);

/* Details of the last failure, published through memtest_fail_* so the caller
 * can hand them to CHECK_EQ without threading a struct pointer everywhere. */
uint32_t memtest_fail_code(void);
uint32_t memtest_fail_addr(void);
uint32_t memtest_fail_expect(void);
uint32_t memtest_fail_actual(void);
const char *memtest_fail_pattern(void);
void memtest_set_pattern(const char *p);
const char *memtest_fail_region(void);

/* Guard used by t_imem.c and t_dmem.c before any destructive pattern runs. */
int memtest_region_safe(const memtest_region_t *r);

/* Arms/disarms the startup.S expected-trap flag. Declared here because the
 * handler in startup.S refers to the same symbol by name. */
extern volatile uint32_t trap_expect;

#endif /* MEMTEST_H */