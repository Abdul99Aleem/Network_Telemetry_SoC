/* ============================================================================
 * Project : RISC-V Network Telemetry SoC
 * File    : sw/src/main.c
 * Desc    : fw0 — "C on silicon".
 *
 *           Proves, end to end, spec §22:
 *               toolchain -> linker -> image -> RTL load -> reset -> fetch
 *               -> startup.S -> main()
 *
 *           Every statement below is chosen to force a countable AHB cycle:
 *             - .data sanity   : LSU READ  from DMEM (VMA)
 *             - .bss sanity    : LSU READ  from DMEM (zero-fill proof)
 *             - scratch[] fill : LSU WRITE to DMEM
 *             - checksum       : LSU READ  from DMEM
 *             - mirror[] write : LSU WRITE to DMEM
 *             - read-back      : LSU READ  from DMEM
 *           Instruction fetches (IMEM reads) happen for free.
 *
 *           Deliberately absent (safety net for the first bring-up):
 *             - .text writes      (IMEM would be a dead branch, spec §9.2)
 *             - stack temporaries (no call depth needed yet)
 *             - trap handler      (startup.S parks instead)
 *             - UART/AES MMIO     (plumbing is on the sibling UART branch)
 * ==========================================================================*/

#include <stdint.h>
#include "soc.h"

#define NWORDS          16u
#define SCRATCH_PATTERN 0xA5A50000u

/* .bss -> allocated in DMEM, zeroed by startup.S before we ever run. */
static volatile uint32_t scratch[NWORDS];
static volatile uint32_t mirror[NWORDS];

/* .rodata -> lives in IMEM, fetched by the LSU only as reads. */
static const volatile uint32_t ro_probe[NWORDS] = {
    0x11111111u, 0x22222222u, 0x33333333u, 0x44444444u,
    0x55555555u, 0x66666666u, 0x77777777u, 0x88888888u,
    0x99999999u, 0xAAAAAAAAu, 0xBBBBBBBBu, 0xCCCCCCCCu,
    0xDDDDDDDDu, 0xEEEEEEEEu, 0xFFFFFFFFu, 0x00000000u,
};

/* .data -> its bytes are stored in imem.mem (LMA) and relocated into DMEM
 * (VMA) by startup.S step 3.  Must NOT be `const`, or it lands in .rodata
 * and .data empties out — then the copy is never exercised (gate G8). */
static volatile uint32_t data_marker = 0x00C0FFEEu;

/* ------------------------------------------------------------------ */
static uint32_t checksum(const volatile uint32_t *p, uint32_t n)
{
    uint32_t acc = 0;
    for (uint32_t i = 0; i < n; i++)
        acc ^= p[i] + i;
    return acc;
}

/* Fail ids are written back through startup.S into mbox[3]; gate G13 only
 * looks at the monitor token, but the id is what makes a red run debuggable
 * in Verdi without re-running. */
int main(void)
{
    /* ---- 1. .rodata is fetched intact, and .data survived the
     *         LMA -> VMA copy performed by startup.S ------------------ */
    if (data_marker != 0x00C0FFEEu)
        return 1;
    if (ro_probe[0] != 0x11111111u || ro_probe[15] != 0x00000000u)
        return 6;

    /* ---- 2. .bss was zeroed ------------------------------------------ */
    for (uint32_t i = 0; i < NWORDS; i++)
        if (scratch[i] != 0u)
            return 2;

    /* ---- 3. write, then read back the pattern ------------------------- */
    for (uint32_t i = 0; i < NWORDS; i++)
        scratch[i] = SCRATCH_PATTERN + i;

    for (uint32_t i = 0; i < NWORDS; i++)
        if (scratch[i] != SCRATCH_PATTERN + i)
            return 3;

    /* ---- 4. fold the block into a single word, round-trip it ---------- */
    uint32_t c = checksum(scratch, NWORDS);
    mirror[0]  = c;
    if (mirror[0] != c)
        return 4;

    /* ---- 5. the scratch block itself must be undisturbed -------------- */
    for (uint32_t i = 0; i < NWORDS; i++)
        if (scratch[i] != SCRATCH_PATTERN + i)
            return 5;

    /* ---- 6. no leakage outside the two arrays -------------------------
     * Placeholders for fw3: once <string.h> shims exist this becomes
     * scratch[N-1] == __bss_end style bounds checking.  Kept empty here so
     * fw0's first run has as few failure modes as possible.               */

    return 0;                          /* PASS -> startup.S writes mbox */
}
