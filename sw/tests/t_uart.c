/* ============================================================================
 * Project : RISC-V Network Telemetry SoC
 * File    : sw/tests/t_uart.c
 * Desc    : UART-01..10 — C-driven UART tests through the integrated VeeR path.
 *
 *           Phase 4 of
 *           doc/Complete_Updated_C_Peripheral_and_Memory_Test_Suite_Plan.md §5.4
 *
 *           These tests exercise the UART through the real SoC data path:
 *             VeeR -> AHB fabric -> AHB-to-AXI bridge -> uart_axi_slave
 *                   -> axi_uart_top -> uart_tx_o
 *
 *           The testbench (tb/tb_veer_p2_soc.sv) decodes the serial line,
 *           cross-checks the transcript against the DMEM result table, and
 *           verifies uart_irq stays low (TX-only).
 *
 *           REGISTER MAP (rtl/uart/uart_axi_slave.v:141-149):
 *             0x00  THR/RBR  WO TX byte (DLAB=0) / RO RX byte
 *             0x04  IER      bit 0 IRQ enable; READS BYPASSED TO ZERO
 *             0x08  BAUD     divisor (DLAB=1); READS BYPASSED TO ZERO
 *             0x0C  LCR      DLAB/stop/parity; READS BYPASSED TO ZERO
 *             0x14  LSR      bit 0 DATA_READY, 5 THRE, 6 TEMT — SERVED
 *
 *           DIVISOR LATCHING QUIRK (axi_uart_top.v:408):
 *             BAUD written while DLAB=1 goes live on the NEXT AXI write,
 *             so uart_init() always follows with an LCR write that clears DLAB.
 *
 *           WHAT IS NOT TESTED HERE (and why):
 *             UART-11 (RX): soc_top ties uart_rx_i to 1'b1, so no RX test is
 *             possible. Documented, not papered over.
 *             IRQ delivery: uart_irq is connected at the soc_top pin but not
 *             routed to the VeeR PIC, so firmware cannot observe it.
 *             UART-10 (irq low): verified at the TB pin level, not by firmware.
 *
 *           The test_main.c runner already calls uart_init() before any test
 *           runs, so LSR state reflects a live UART. These tests assume that
 *           init completed (the t_uart_status test from earlier phases already
 *           verified THRE/TEMT at idle).
 * ==========================================================================*/

#include <stdint.h>
#include "soc.h"
#include "test.h"
#include "uart.h"

/* ---- UART-01: LSR idle status --------------------------------------------
 * After init, THRE (bit 5) and TEMT (bit 6) must both be set — the transmitter
 * is idle. DATA_READY (bit 0) must be clear — no RX (tied high).
 */
static int t_uart_lsr_idle(void)
{
    uint32_t lsr = UART_REG32(UART_OFF_LSR);

    CHECK_EQ("uart/lsr_idle_thre", lsr & UART_LSR_THRE, UART_LSR_THRE);
    CHECK_EQ("uart/lsr_idle_temt", lsr & UART_LSR_TEMT, UART_LSR_TEMT);
    /* DATA_READY should be clear: RX is tied high (idle), so no start edge. */
    CHECK_EQ("uart/lsr_idle_dr", lsr & UART_LSR_DATA_READY, 0u);
    return 0;
}

/* ---- UART-02: single byte TX --------------------------------------------
 * Write one byte to THR. THRE should clear momentarily then reassert once
 * the byte moves to the shift register. The testbench decodes the actual
 * byte from uart_tx_o, so the wire-level check is independent of this.
 * Here we verify the firmware-visible status transitions.
 *
 * The trailing newline ensures the test data forms its own line in the
 * transcript, so it does not merge with the test report line that follows.
 */
static int t_uart_single_byte(void)
{
    int rc;

    /* THR write should succeed (THRE is already asserted from idle). */
    rc = uart_putc('A');
    CHECK_EQ("uart/single_byte_putc", rc, 0);

    /* After writing, poll for THRE to return — the byte has left the THR. */
    rc = uart_putc('B');
    CHECK_EQ("uart/single_byte_putc2", rc, 0);

    /* Newline so the data bytes form their own transcript line and do not
     * merge with the test report line the runner emits next. */
    (void)uart_putc('\n');
    return 0;
}

/* ---- UART-03: fixed string -----------------------------------------------
 * Send a known multi-byte string. The testbench decodes every byte and order
 * from uart_tx_o. This verifies no loss, duplication, or reordering at the
 * firmware level. The actual byte-level decode is the TB's job.
 */
static int t_uart_fixed_string(void)
{
    int rc;

    rc = uart_puts("UARTTEST\n");
    CHECK_EQ("uart/fixed_string", rc, 0);
    return 0;
}

/* ---- UART-04: THRE polling with timeout ---------------------------------
 * Every uart_putc already polls THRE with a bounded loop (UART_POLL_LIMIT).
 * This test verifies the poll mechanism explicitly: after init and drain,
 * THRE must be immediately set, so a poll should succeed on the first check.
 * Then write a byte and verify THRE returns within the bound.
 */
static int t_uart_thre_poll(void)
{
    uint32_t n;
    uint32_t lsr;

    /* THRE should be set immediately at idle. */
    lsr = UART_REG32(UART_OFF_LSR);
    CHECK_EQ("uart/thre_idle", lsr & UART_LSR_THRE, UART_LSR_THRE);

    /* Write a byte, then poll THRE until it returns. */
    (void)uart_putc('X');
    (void)uart_putc('\n');   /* separate data from the test report line */

    n = 0;
    while ((UART_REG32(UART_OFF_LSR) & UART_LSR_THRE) == 0u) {
        if (++n > UART_POLL_LIMIT) {
            test_record_failure("uart/thre_poll_timeout", 3u, n, UART_POLL_LIMIT);
            return 3;
        }
    }
    return 0;
}

/* ---- UART-05: TEMT completion --------------------------------------------
 * After transmitting, TEMT (bit 6) must eventually assert, meaning the shift
 * register has fully drained. uart_drain() already does this; this test
 * verifies it works by calling drain after a known transmit and checking
 * TEMT is set afterward.
 */
static int t_uart_temt_completion(void)
{
    int rc;

    rc = uart_putc('Z');
    CHECK_EQ("uart/temt_putc", rc, 0);
    (void)uart_putc('\n');   /* separate data from the test report line */

    rc = uart_drain();
    CHECK_EQ("uart/temt_drain", rc, 0);

    /* After drain, TEMT must be set. */
    CHECK_EQ("uart/temt_after_drain",
             UART_REG32(UART_OFF_LSR) & UART_LSR_TEMT, UART_LSR_TEMT);
    return 0;
}

/* ---- UART-06: back-to-back payload ---------------------------------------
 * Send several bytes in quick succession without draining between them.
 * The FIFO (32 deep) should absorb them without loss. The testbench decodes
 * the full sequence.
 */
static int t_uart_back_to_back(void)
{
    static const char msg[] = "BACK2BACK\n";
    int rc;

    rc = uart_puts(msg);
    CHECK_EQ("uart/back2back", rc, 0);
    return 0;
}

/* ---- UART-07: FIFO stress ------------------------------------------------
 * Fill the TX FIFO with more bytes than the FIFO depth (32) to verify the
 * driver's THRE poll correctly throttles when the FIFO fills. If the poll
 * failed, the write would block or corrupt. We send 48 bytes (1.5x FIFO depth)
 * which forces at least one THRE poll cycle.
 */
static int t_uart_fifo_stress(void)
{
    int rc;
    uint32_t i;

    /* 48 bytes: 1.5x the 32-deep FIFO. Forces THRE throttling. */
    for (i = 0; i < 48u; i++) {
        rc = uart_putc((char)('0' + (i % 10u)));
        if (rc != 0) {
            test_record_failure("uart/fifo_stress", 1u, i, 48u);
            return 1;
        }
    }
    rc = uart_putc('\n');
    CHECK_EQ("uart/fifo_stress_nl", rc, 0);
    return 0;
}

/* ---- UART-08: baud configuration -----------------------------------------
 * Re-run the init sequence (DLAB set -> BAUD=8 -> DLAB clear) and verify the
 * UART still transmits correctly afterward. The testbench calibrates the bit
 * period from the first byte, so a wrong divisor would show as a decode failure.
 * This test verifies the init sequence is idempotent.
 */
static int t_uart_baud_config(void)
{
    int rc;

    /* Re-init: should not break anything. */
    rc = uart_init();
    CHECK_EQ("uart/baud_reinit", rc, 0);

    /* Transmit after re-init to prove the UART is still alive. */
    rc = uart_puts("BAUDOK\n");
    CHECK_EQ("uart/baud_tx_after_reinit", rc, 0);
    return 0;
}

/* ---- UART-09: wrapper read behavior ---------------------------------------
 * The UART wrapper bypasses reads of IER (0x04), BAUD (0x08), and LCR (0x0C)
 * to zero, because the IP's read FSM only serves RBR (0x00) and LSR (0x14).
 * This test asserts that bypass as EXPECTED behavior. If a future RTL change
 * starts serving these reads, this test will fail loudly — which is the point.
 *
 * LSR is the one register that IS served, so it must NOT read as zero.
 */
static int t_uart_wrapper_reads(void)
{
    uint32_t ier_val, baud_val, lcr_val, lsr_val;

    ier_val  = UART_REG32(UART_OFF_IER);
    baud_val = UART_REG32(UART_OFF_BAUD);
    lcr_val  = UART_REG32(UART_OFF_LCR);
    lsr_val  = UART_REG32(UART_OFF_LSR);

    /* These three are bypassed to zero by the wrapper. */
    CHECK_EQ("uart/ier_read_zero", ier_val, 0u);
    CHECK_EQ("uart/baud_read_zero", baud_val, 0u);
    CHECK_EQ("uart/lcr_read_zero", lcr_val, 0u);

    /* LSR is served by the IP and must NOT be zero (THRE+TEMT = 0x60 at idle). */
    CHECK_TRUE("uart/lsr_not_zero", lsr_val != 0u);
    CHECK_EQ("uart/lsr_thre_set", lsr_val & UART_LSR_THRE, UART_LSR_THRE);

    return 0;
}

/* ---- UART-10: TX-only IRQ stays low (firmware-observable check) -----------
 * The full IRQ check is a TB-level pin observation (see plan §5.10), because
 * uart_irq is not routed to the VeeR PIC. Here we verify the firmware-visible
 * side: after transmitting, no unexpected side effects appear in LSR. The
 * TB independently asserts uart_irq stays low at the soc_top pin.
 *
 * This test is deliberately minimal — it checks that transmitting does not
 * set any unexpected LSR bits, which would indicate an interrupt condition.
 */
static int t_uart_tx_no_side_effects(void)
{
    uint32_t lsr_before, lsr_after;
    int rc;

    lsr_before = UART_REG32(UART_OFF_LSR);

    rc = uart_putc('Q');
    CHECK_EQ("uart/irq_tx_putc", rc, 0);
    (void)uart_putc('\n');   /* separate data from the test report line */

    (void)uart_drain();

    lsr_after = UART_REG32(UART_OFF_LSR);

    /* Only THRE and TEMT should be set. No error bits (bits 1-4) should
     * appear, and DATA_READY (bit 0) should stay clear (RX is tied high). */
    CHECK_EQ("uart/irq_no_err_bits", lsr_after & 0x1Eu, 0u);
    CHECK_EQ("uart/irq_no_data_ready", lsr_after & UART_LSR_DATA_READY, 0u);

    /* THRE and TEMT must still be set after drain. */
    CHECK_EQ("uart/irq_thre_set", lsr_after & UART_LSR_THRE, UART_LSR_THRE);
    CHECK_EQ("uart/irq_temt_set", lsr_after & UART_LSR_TEMT, UART_LSR_TEMT);

    return 0;
}

/* ---- test registry ------------------------------------------------------- */
TEST_CASE(t_uart_lsr_idle)
TEST_CASE(t_uart_single_byte)
TEST_CASE(t_uart_fixed_string)
TEST_CASE(t_uart_thre_poll)
TEST_CASE(t_uart_temt_completion)
TEST_CASE(t_uart_back_to_back)
TEST_CASE(t_uart_fifo_stress)
TEST_CASE(t_uart_baud_config)
TEST_CASE(t_uart_wrapper_reads)
TEST_CASE(t_uart_tx_no_side_effects)
