/* ============================================================================
 * Project : RISC-V Network Telemetry SoC
 * File    : sw/include/uart.h
 * Desc    : Minimal C UART driver for the test suite's serial reporting.
 *
 *           Phase 2 of
 *           doc/Complete_Updated_C_Peripheral_and_Memory_Test_Suite_Plan.md §5.
 *
 *           Register map, verified against rtl/uart/uart_axi_slave.v:141-149:
 *
 *             0x00  THR/RBR  write TX byte (DLAB=0) / read RX byte
 *             0x04  IER      bit 0 IRQ enable.  WRITES SERVED, READS BYPASSED
 *             0x08  BAUD     divisor while DLAB=1.  WRITES SERVED, READS BYPASSED
 *             0x0C  LCR      bit 7 DLAB, 2 stop, 3 parity en, 4 parity mode.
 *                             WRITES SERVED, READS BYPASSED
 *             0x14  LSR      bit 0 DATA_READY, 5 THRE, 6 TEMT.  SERVED BOTH WAYS
 *
 *           READ-BACK CAVEAT — the driver never reads IER/LCR/BAUD.
 *           uart_axi_slave.v:153-156 forwards only offsets whose addr[4:2] is
 *           0 or 5 to the IP; every other read completes locally with
 *           32'h0000_0000:
 *
 *             function automatic logic is_ip_read_offset(input [4:0] off);
 *                 is_ip_read_offset = (off[4:2] == 3'd0) || (off[4:2] == 3'd5);
 *             endfunction
 *
 *           So a read of LCR returning 0 does NOT mean the LCR write failed.
 *           Asserting otherwise would encode a wrapper quirk as a contract.
 *
 *           DIVISOR LATCHING QUIRK — the divisor takes effect one write late.
 *           axi_uart_top.v:408 does `uart_baudrate_div_int <= baudrate_divisor_int`
 *           in AckWriteState, so a BAUD written while DLAB=1 becomes live on the
 *           NEXT AXI write, not the one that stored it. uart_init() therefore
 *           always follows the BAUD write with the LCR write that clears DLAB.
 *
 *           Every wait is bounded. A driver that could hang would turn a hung
 *           peripheral into a hung simulation, which is the one outcome that
 *           produces no evidence at all.
 * ==========================================================================*/
#ifndef UART_H
#define UART_H

#include <stdint.h>

/* ---- registers (offsets from UART_BASE) --------------------------------- */
#define UART_OFF_THR  0x00u
#define UART_OFF_IER  0x04u
#define UART_OFF_BAUD 0x08u
#define UART_OFF_LCR  0x0Cu
#define UART_OFF_LSR  0x14u

/* ---- register access ----------------------------------------------------
 * Exposed so test cases can read a register directly (the LSR test does).
 * Only the LSR is meaningfully readable — IER/LCR/BAUD reads are bypassed to
 * zero by the wrapper, see the note above.
 */
#define UART_REG32(off)  MMIO32(UART_BASE + (off))

/* ---- LCR bits ----------------------------------------------------------- */
#define UART_LCR_DLAB    (1u << 7)
#define UART_LCR_8N1     0x03u          /* 8 data bits, no parity, 1 stop */

/* ---- LSR bits (axi_uart.vh) --------------------------------------------- */
#define UART_LSR_DATA_READY (1u << 0)
#define UART_LSR_THRE       (1u << 5)
#define UART_LSR_TEMT       (1u << 6)

/* Simulation divisor. The reset default is 868 (115200 at 100 MHz); at a 10 ns
 * clock that is an 8680 ns bit period, so even a short line costs hundreds of
 * microseconds of simulation time. 8 gives (8+1)*10 = 90 ns per bit. */
#define UART_BAUD_SIM  8u

/* Bound on any single poll loop. Generous against the ~90-cycle settle at
 * UART_BAUD_SIM, but finite so a dead peripheral fails instead of hanging. */
#define UART_POLL_LIMIT 20000u

/* ---- API. Every call returns 0 on success, non-zero on failure. ---------- */
int uart_init(void);
int uart_putc(char c);
int uart_puts(const char *s);
int uart_puthex32(uint32_t v);   /* "0x" + 8 upper-case hex digits */
int uart_putdec(uint32_t v);     /* unsigned decimal, no padding */
int uart_drain(void);            /* wait for TEMT: transmitter fully idle */

/* Non-zero once any uart_* call has failed. Lets the runner report a serial
 * fault without every call site having to thread a status code. */
int uart_error(void);
void uart_clear_error(void);

#endif /* UART_H */