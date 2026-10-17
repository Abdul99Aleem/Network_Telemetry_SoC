/* ============================================================================
 * Project : RISC-V Network Telemetry SoC
 * File    : sw/src/uart.c
 * Desc    : Minimal UART driver for the test suite's serial reporting.
 *
 *           Phase 2 of
 *           doc/Complete_Updated_C_Peripheral_and_Memory_Test_Suite_Plan.md §5.
 *
 *           Freestanding: no libc beyond the project's own sw/src/lib.c, and
 *           nothing here needs a 64-bit division helper (Amendment A1).
 *
 *           Every register access is volatile. That is not decoration: VeeR's
 *           LSU load buffer will forward a repeated load of the same address,
 *           so a non-volatile poll of LSR can be satisfied from the buffer
 *           without ever reaching the bus. startup.S also sets the MRAC
 *           side-effect bit for 0x1xxx_xxxx for the hardware half of the same
 *           problem. Both are required — with either one missing, uart_putc
 *           would "succeed" without transmitting anything.
 *
 *           IER, LCR and BAUD are never read back; see sw/include/uart.h for why
 *           their reads are bypassed to zero and why treating that as a failure
 *           would be wrong.
 * ==========================================================================*/

#include <stdint.h>
#include "soc.h"
#include "uart.h"

/* ---- MMIO accessors ----------------------------------------------------- */
#define REG32(off)  UART_REG32(off)

/* Every entry point returns 0 or non-zero; this is the sticky error flag. */
static int uart_err;

int uart_error(void)      { return uart_err; }
void uart_clear_error(void) { uart_err = 0; }

/* ---- bounded poll --------------------------------------------------------
 * Returns 0 when `mask` became set within UART_POLL_LIMIT iterations,
 * non-zero otherwise. Bounded so a dead peripheral produces a failure rather
 * than a simulation that never terminates.
 */
static int poll_lsr(uint32_t mask)
{
    uint32_t n;

    for (n = 0; n < UART_POLL_LIMIT; n++) {
        if ((REG32(UART_OFF_LSR) & mask) != 0u)
            return 0;
    }
    return 1;
}

/* ---- init ----------------------------------------------------------------
 * DLAB set -> divisor -> DLAB clear. The trailing LCR write is not cosmetic:
 * it is what makes the divisor written a moment earlier actually take effect
 * (axi_uart_top.v:408).
 */
int uart_init(void)
{
    int rc = 0;

    REG32(UART_OFF_LCR) = UART_LCR_DLAB | UART_LCR_8N1;  /* DLAB=1, 8N1   */
    REG32(UART_OFF_BAUD) = UART_BAUD_SIM;                /* divisor latched */
    REG32(UART_OFF_LCR) = UART_LCR_8N1;                  /* DLAB=0, live   */

    /* THRE/TEMT are the only registers whose reads the wrapper actually
     * serves, so this is the only status that can be trusted at reset. */
    rc |= poll_lsr(UART_LSR_THRE);

    if (rc)
        uart_err = rc;
    return rc;
}

/* ---- character output ----------------------------------------------------
 * Wait for THRE (transmit holding register empty, i.e. FIFO has room) rather
 * than TEMT: waiting for TEMT per character would serialise at the line rate
 * and make the transcript thousands of times slower than necessary. The FIFO
 * is 32 deep (_AXI_UART_FIFO_DEPTH_), so polling THRE keeps it fed.
 */
int uart_putc(char c)
{
    int rc;

    rc = poll_lsr(UART_LSR_THRE);
    if (rc) {
        uart_err = rc;
        return rc;
    }

    REG32(UART_OFF_THR) = (uint32_t)(uint8_t)c;
    return 0;
}

int uart_puts(const char *s)
{
    int rc = 0;

    while (*s != '\0') {
        rc |= uart_putc(*s);
        s++;
        if (rc)
            break;              /* stop early; the sticky flag keeps the error */
    }
    return rc;
}

/* ---- numeric formatting -------------------------------------------------- */

static const char hexdig[] = "0123456789ABCDEF";

int uart_puthex32(uint32_t v)
{
    int rc = 0;
    int i;

    rc |= uart_putc('0');
    rc |= uart_putc('x');
    for (i = 28; i >= 0 && !rc; i -= 4)
        rc |= uart_putc(hexdig[(v >> i) & 0xFu]);
    return rc;
}

int uart_putdec(uint32_t v)
{
    char buf[11];
    int  n = 0;
    int  rc = 0;

    if (v == 0u)
        return uart_putc('0');

    /* Unsigned only: no 64-bit division helper exists under -nostdlib. */
    while (v != 0u && n < (int)sizeof(buf)) {
        buf[n] = hexdig[v % 10u];
        v /= 10u;
        n++;
    }
    while (n > 0 && !rc) {
        n--;
        rc |= uart_putc(buf[n]);
    }
    return rc;
}

/* ---- drain ---------------------------------------------------------------
 * TEMT (bit 6) is set only when the transmitter has finished shifting the last
 * bit, so this is the point at which the line is idle-high and the testbench
 * can stop capturing. main() must call this BEFORE writing the mailbox
 * trigger, otherwise the testbench can $finish while bytes are still in flight.
 */
int uart_drain(void)
{
    int rc = poll_lsr(UART_LSR_TEMT);

    if (rc)
        uart_err = rc;
    return rc;
}