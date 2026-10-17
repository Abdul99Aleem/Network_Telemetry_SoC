/* ============================================================================
 * Project : RISC-V Network Telemetry SoC
 * File    : sw/tests/t_bus.c
 * Desc    : BUS-05/06/07 — AHB decode behaviour for unmapped addresses.
 *
 *           Phase 3 of
 *           doc/Complete_Updated_C_Peripheral_and_Memory_Test_Suite_Plan.md §6.3
 *
 * ============================ IMPORTANT FINDING ===========================
 * An unmapped address does NOT produce a CPU-visible exception in this core,
 * and the CPU cannot complete an access to one either. Both a LOAD and a
 * STORE to unmapped space wedge the pipeline. Verified by measurement, not
 * assumption:
 *
 *   - el2_lsu_lsc_ctl.sv:210 is the only producer of an LSU exception:
 *         lsu_error_pkt_m.exc_valid =
 *             (access_fault_m | misaligned_fault_m | lsu_double_ecc_error_m)
 *     A bus RESPONSE error is not in that list.
 *   - A response error surfaces as lsu_pmu_bus_error
 *     (el2_lsu_bus_buffer.sv:923), whose only consumer is the hardware
 *     performance-counter hit vector at el2_dec_tlu_ctl.sv:2651:
 *         ({1{(mhpme_vec[i][9:0] == MHPME_DBUS_ERROR)}} & {lsu_pmu_bus_error})
 *     That increments a counter. It does not raise a trap. Arming mhpme3 with
 *     event 46 therefore does NOT help, and was tried before this was
 *     established.
 *   - access_fault_m (the one path that could trap) is raised BEFORE the access
 *     reaches the bus, by the address checker or the PMP
 *     (el2_lsu_addrcheck.sv:221). Configuring PMP to deny an address produces
 *     a trap, but then the transaction is never issued and the fabric's ERROR
 *     slave is never exercised.
 *
 * CONSEQUENCE: the two layers the plan assumed are mutually exclusive at a given
 * address. Either the CPU issues the access and the fabric returns ERROR (and
 * the core stalls), or the access is denied before it is issued (and the core
 * traps but the fabric sees nothing). Neither gives both.
 *
 * WHAT THIS FILE THEREFORE DOES
 * It issues exactly ONE unmapped store, as the last thing the firmware does,
 * and lets the core stall. The testbench observes the fabric's response and
 * terminates the run on that evidence:
 *
 *   - tb_ahb_cycle_monitor records every default-slave claim, its ADDRESS, and
 *     every HRESP, and gates the counts against declared expectations
 *     (+expect_def / +expect_buserr).
 *   - +expect_def_addrs pins WHICH address produced them, so a correct count
 *     from the wrong address fails.
 *   - +bus_watch makes the testbench finish on the expected ERROR instead of
 *     waiting for a mailbox the CPU can never write.
 *
 * The expected-trap machinery (startup.S trap_handler + bus_test_resume) is
 * retained and correct, and is what a PMP-denied access would use. It is not
 * used here because nothing routes a bus response error to it. See
 * doc/Phase3_Memory_and_Bus_Record.md §5.
 * ==========================================================================*/

#include <stdint.h>
#include "soc.h"
#include "test.h"
#include "uart.h"
#include "memtest.h"

/* The single address the CPU can drive into the fabric and observe. */
#define BUS_PROBE_ADDR   0x10001000u
#define BUS_PROBE_VALUE  0xDEADBEEFu

/* Arming flag read by startup.S:trap_handler. Implemented in test_main.c so
 * every variant links it; this file is #included into that translation unit. */
extern uint32_t bus_trap_try(volatile uint32_t *p);
extern int      bus_trap_release(void);

/* ---- t_bus_05 ----------------------------------------------------------
 * The ONLY address the CPU can drive into the ERROR slave without wedging the
 * core before any further test can run. A single store is issued; the core then
 * stalls and the testbench terminates on the observed ERROR.
 *
 * It deliberately does not return: the store never completes. The verifier is
 * the testbench, not this function's return value.
 */
static int t_bus_05_unmapped_store(void)
{
    volatile uint32_t *p = (volatile uint32_t *)(uintptr_t)BUS_PROBE_ADDR;

    uart_puts("BUS05 store to unmapped 0x");
    uart_puthex32(BUS_PROBE_ADDR);
    uart_putc('\n');

    /* BUSYWAIT on purpose: see the finding above. The core cannot complete
     * this access, so this instruction never returns and the testbench ends
     * the run from the fabric evidence. A single self-loop keeps the failure
     * mode explicit rather than relying on whatever the core happens to do. */
    for (;;) {
        *p = BUS_PROBE_VALUE;
    }
}

/* ---- mapped-address control -------------------------------------------
 * Included in the bus variant and run BEFORE the unmapped probe, because it
 * must complete while the pipeline is still healthy. Reading a mapped address
 * must not trap and must not disturb the ERROR counters — if this regressed,
 * every later expectation would be measured against a broken baseline.
 */
static int t_bus_mapped_no_trap(void)
{
    volatile uint32_t sink;

    /* Read the mailbox word — safely inside DMEM. An earlier version read
     * __stack_top - 4, which LOOKED like the last valid word but is not: the
     * AHB data bus is 64 bits wide, so a 32-bit load at 0x00017FFC has
     * addr[2] = 1 and is answered from hrdata[63:32], i.e. bytes
     * 0x00018000..0x00018003 — past the end of the 32 KB array. That produced
     * a real AHB ERROR and a spurious default-slave claim at 0x00018000. */
    sink = *(volatile uint32_t *)(uintptr_t)0x00010000u;

    /* Last word of the decoded UART window. 0x10000FFC: addr[2] = 1, so the
     * bridge splits this into one 32-bit AXI read at the same address, which
     * the wrapper bypasses to a local zero with OKAY. */
    sink ^= *(volatile uint32_t *)0x10000FFCu;
    (void)sink;

    CHECK_EQ("bus/trap_flag_clear", trap_expect, 0u);
    return 0;
}

TEST_CASE(t_bus_mapped_no_trap)
TEST_CASE(t_bus_05_unmapped_store)