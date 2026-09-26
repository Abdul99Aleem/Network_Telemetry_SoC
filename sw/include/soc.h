/* ============================================================================
 * Project : RISC-V Network Telemetry SoC
 * File    : sw/include/soc.h
 * Desc    : SoC memory map + MMIO accessors for p2_soc / fw0.
 *
 *           Board BSP only. No HAL claims: every address below is written in
 *           spec §9.1 (Mode-1 map) and matches rtl/soc_top.sv wiring.
 * ==========================================================================*/
#ifndef SOC_H
#define SOC_H

#include <stdint.h>

/* ---------------- core-local (Mode 1: never touched by this BSP) --------- */
/* ICCM 0xEE00_0000..0xEE00_FFFF, DCCM 0xF004_0000..0xF004_FFFF — reserved
 * for the VeeR core's local memories, see linker guardrails.              */

/* ---------------- on-chip SRAM ------------------------------------------- */
#define IMEM_BASE       0x00000000u
#define IMEM_SIZE       0x00008000u         /* 32 KB */
#define DMEM_BASE       0x00010000u
#define DMEM_SIZE       0x00008000u         /* 32 KB */

/* fw0 PASS mailbox: first 16 bytes of DMEM, written by startup.S.
 * Layout is the frozen Phase-2 contract so tb/tb_veer_p2_soc.sv:300 fires
 * with zero monitor changes:
 *   [0]=0x50 'P'  [1]=0x32 '2'  [2]=0xFF trigger  [3]=pass code
 *   [4..7]=0x00003250                                                */
#define MBOX_BASE       (DMEM_BASE + 0x00u)
#define MBOX_SIZE       0x10u
#define MBOX_SIG_LO     0x50u
#define MBOX_SIG_HI     0x32u
#define MBOX_TRIGGER    0xFFu

/* ---------------- memory-mapped peripherals ------------------------------ */
#define UART_BASE       0x10000000u         /* spec §9.1; rtl/uart/ present
                                               only on the sibling UART branch */
#define AES_BASE        0x10004000u         /* spec §9.1 */

/* ---------------- MMIO accessors ----------------------------------------- */
#define MMIO8(addr)     (*(volatile uint8_t  *)(uintptr_t)(addr))
#define MMIO16(addr)    (*(volatile uint16_t *)(uintptr_t)(addr))
#define MMIO32(addr)    (*(volatile uint32_t *)(uintptr_t)(addr))

#endif /* SOC_H */
