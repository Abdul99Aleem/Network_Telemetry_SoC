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

/* ---------------- core-local memories (Phase 0 probe, measured) ---------
 * ICCM 0xEE00_0000 is instantiated (RV_ICCM_ENABLE 1, 64 KB) but is served by
 * the IFU (el2_ifu_iccm_mem), so a C load/store has no route to it: the address
 * falls through to the AHB ERROR slave. Measured 2026-10-17, see
 * doc/Phase0_ICCM_DCCM_Access_Spike_Record.md. Do not treat it as data memory.
 * DCCM 0xF004_0000 is served by the LSU (el2_lsu_dccm_mem) and IS reachable
 * from C: dccm_rb=5a5a5678 round-tripped with def=0 bus_err=0.               */
#define ICCM_BASE       0xEE000000u      /* NOT C-accessible (IFU-side) */
#define DCCM_BASE       0xF0040000u      /* C-accessible (LSU-side)     */
#define DCCM_SIZE       0x00010000u      /* 64 KB */

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

/* ---------------- memory-mapped peripherals ------------------------------
 * UART_BASE 0x1000_0000 is live: decoded by rtl/ahb/ahb_interconnect.sv:169
 * and driven end-to-end through ahb_to_axi_bridge -> uart_axi_slave.
 *
 * AES is NOT live. aes_axi_slave exists and is proven in isolation, but it is
 * not instantiated in rtl/soc_top.sv and not decoded by the AHB fabric, so the
 * AES address lands on the default ERROR slave. AES_BASE records the address
 * the RTL implements (aes_axi_slave.v:85 writes it as 32'h1000_4000, i.e.
 * 0x1000_4000 = 268451840). Note 0x10004000 and 0x1000_4000 are the SAME
 * value with different underscore grouping, not two different addresses. */
#define UART_BASE       0x10000000u
#define UART_WINDOW     0x10000000u      /* decoded 4 KB: base..base+0xFFF */
#define AES_BASE        0x10004000u      /* canonical written form: 0x1000_4000 */

/* ---------------- MMIO accessors ----------------------------------------- */
#define MMIO8(addr)     (*(volatile uint8_t  *)(uintptr_t)(addr))
#define MMIO16(addr)    (*(volatile uint16_t *)(uintptr_t)(addr))
#define MMIO32(addr)    (*(volatile uint32_t *)(uintptr_t)(addr))

#endif /* SOC_H */
