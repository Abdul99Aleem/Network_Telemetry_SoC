/* ============================================================================
 * Project : RISC-V Network Telemetry SoC
 * File    : sw/src/lib.c
 * Desc    : Freestanding libc shims (-nostdlib / -ffreestanding).
 *
 *           GCC emits calls to these even at -O0 (aggregate assignment,
 *           structure copies, certain __builtin_ lowerings).  With -nostdlib
 *           they are link errors unless provided here — gate G11 proves it.
 *
 *           MUST be compiled with -fno-tree-loop-distribute-patterns,
 *           otherwise GCC recognises the loop below and rewrites it into a
 *           call to memcpy — infinite recursion (spec §8.4).
 * ==========================================================================*/

#include <stddef.h>

void *memcpy(void *dst, const void *src, size_t n)
{
    unsigned char       *d = (unsigned char *)dst;
    const unsigned char *s = (const unsigned char *)src;

    while (n--)
        *d++ = *s++;
    return dst;
}

void *memmove(void *dst, const void *src, size_t n)
{
    unsigned char       *d = (unsigned char *)dst;
    const unsigned char *s = (const unsigned char *)src;

    if (d == s || n == 0u)
        return dst;

    if (d < s) {
        while (n--)
            *d++ = *s++;
    } else {
        d += n;
        s += n;
        while (n--)
            *--d = *--s;
    }
    return dst;
}

void *memset(void *dst, int c, size_t n)
{
    unsigned char *d = (unsigned char *)dst;
    unsigned char  v = (unsigned char)c;

    while (n--)
        *d++ = v;
    return dst;
}

int memcmp(const void *a, const void *b, size_t n)
{
    const unsigned char *x = (const unsigned char *)a;
    const unsigned char *y = (const unsigned char *)b;

    while (n--) {
        if (*x != *y)
            return (int)*x - (int)*y;
        x++;
        y++;
    }
    return 0;
}

size_t strlen(const char *s)
{
    const char *p = s;

    while (*p)
        p++;
    return (size_t)(p - s);
}

char *strcpy(char *dst, const char *src)
{
    char *d = dst;

    while ((*d++ = *src++) != '\0')
        ;
    return dst;
}
