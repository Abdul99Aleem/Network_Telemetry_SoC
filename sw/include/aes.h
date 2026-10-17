/* ============================================================================
 * Project : RISC-V Network Telemetry SoC
 * File    : sw/include/aes.h
 * Desc    : Minimal C driver for the AES-128 accelerator (M4a, polling).
 *
 *           Register map matches rtl/aes/aes_axi_slave.v:
 *             0x00  CONTROL   W: bit0 START, bit1 CLEAR_DONE/IRQ
 *             0x04  STATUS    R: bit0 BUSY, bit1 DONE
 *             0x08  KEY0      R/W
 *             0x0C  KEY1      R/W
 *             0x10  KEY2      R/W
 *             0x14  KEY3      R/W
 *             0x18  DATA0     R/W
 *             0x1C  DATA1     R/W
 *             0x20  DATA2     R/W
 *             0x24  DATA3     R/W
 *             0x28  RESULT0   R
 *             0x2C  RESULT1   R
 *             0x30  RESULT2   R
 *             0x34  RESULT3   R
 * ==========================================================================*/
#ifndef AES_H
#define AES_H

#include <stdint.h>
#include "soc.h"

#define AES_OFF_CONTROL 0x00u
#define AES_OFF_STATUS  0x04u
#define AES_OFF_KEY0    0x08u
#define AES_OFF_KEY1    0x0Cu
#define AES_OFF_KEY2    0x10u
#define AES_OFF_KEY3    0x14u
#define AES_OFF_DATA0   0x18u
#define AES_OFF_DATA1   0x1Cu
#define AES_OFF_DATA2   0x20u
#define AES_OFF_DATA3   0x24u
#define AES_OFF_RESULT0 0x28u
#define AES_OFF_RESULT1 0x2Cu
#define AES_OFF_RESULT2 0x30u
#define AES_OFF_RESULT3 0x34u

#define AES_REG32(off) MMIO32(AES_BASE + (off))

#define AES_STATUS_BUSY (1u << 0)
#define AES_STATUS_DONE (1u << 1)

#define AES_CTRL_START      (1u << 0)
#define AES_CTRL_CLEAR_DONE (1u << 1)

/* Poll bound, analogous to UART_POLL_LIMIT. */
#define AES_POLL_LIMIT 1000000u

/* API. Returns 0 on success, non-zero on timeout. */
void aes_write_key(const uint32_t key[4]);
void aes_write_data(const uint32_t data[4]);
void aes_read_result(uint32_t result[4]);
int  aes_start_and_wait(void);
void aes_clear_done(void);

#endif /* AES_H */
