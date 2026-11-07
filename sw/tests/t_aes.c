/* ============================================================================
 * Project : RISC-V Network Telemetry SoC
 * File    : sw/tests/t_aes.c
 * Desc    : AES-01.. tests through VeeR -> AHB -> bridge -> aes_axi_slave.
 * ==========================================================================*/

#include <stdint.h>
#include "soc.h"
#include "test.h"
#include "aes.h"

static const uint32_t aes_key[4] = {
    0x0c0d0e0fu, 0x08090a0bu, 0x04050607u, 0x00010203u
};

static const uint32_t aes_plain[4] = {
    0xccddeeffu, 0x8899aabbu, 0x44556677u, 0x00112233u
};

static const uint32_t aes_cipher[4] = {
    0x70b4c55au, 0xd8cdb780u, 0x6a7b0430u, 0x69c4e0d8u
};

/* AES-01: key/data register readback. */
static int t_aes_reg_readback(void)
{
    uint32_t k[4];
    uint32_t d[4];
    uint32_t i;

    aes_write_key(aes_key);
    aes_write_data(aes_plain);

    /* Read back via MMIO. */
    k[0] = AES_REG32(AES_OFF_KEY0);
    k[1] = AES_REG32(AES_OFF_KEY1);
    k[2] = AES_REG32(AES_OFF_KEY2);
    k[3] = AES_REG32(AES_OFF_KEY3);
    d[0] = AES_REG32(AES_OFF_DATA0);
    d[1] = AES_REG32(AES_OFF_DATA1);
    d[2] = AES_REG32(AES_OFF_DATA2);
    d[3] = AES_REG32(AES_OFF_DATA3);

    for (i = 0; i < 4u; i++) {
        CHECK_EQ("aes/key_readback", k[i], aes_key[i]);
        CHECK_EQ("aes/data_readback", d[i], aes_plain[i]);
    }
    return 0;
}

/* AES-02: start returns completion without timeout. */
static int t_aes_start_wait(void)
{
    int rc;

    aes_write_key(aes_key);
    aes_write_data(aes_plain);

    rc = aes_start_and_wait();
    CHECK_EQ("aes/start_wait", (uint32_t)rc, 0u);
    return 0;
}

/* AES-03: ciphertext matches reference. */
static int t_aes_ciphertext(void)
{
    uint32_t res[4];
    uint32_t i;
    int rc;

    aes_write_key(aes_key);
    aes_write_data(aes_plain);

    rc = aes_start_and_wait();
    CHECK_EQ("aes/ct_start", (uint32_t)rc, 0u);

    aes_read_result(res);
    for (i = 0; i < 4u; i++)
        CHECK_EQ("aes/ciphertext", res[i], aes_cipher[i]);

    return 0;
}

/* AES-04: clear done resets status. */
static int t_aes_clear_done(void)
{
    int rc;

    aes_write_key(aes_key);
    aes_write_data(aes_plain);

    rc = aes_start_and_wait();
    CHECK_EQ("aes/cd_start", (uint32_t)rc, 0u);

    /* DONE should be set. */
    CHECK_EQ("aes/cd_done_set", AES_REG32(AES_OFF_STATUS) & AES_STATUS_DONE,
             AES_STATUS_DONE);

    aes_clear_done();

    /* After clear, DONE should be clear. */
    CHECK_EQ("aes/cd_done_clear", AES_REG32(AES_OFF_STATUS) & AES_STATUS_DONE, 0u);
    return 0;
}

/* AES-05: repeated transaction produces same result. */
static int t_aes_repeat(void)
{
    uint32_t res[4];
    uint32_t i;
    int rc;

    for (i = 0; i < 2u; i++) {
        aes_write_key(aes_key);
        aes_write_data(aes_plain);
        rc = aes_start_and_wait();
        CHECK_EQ("aes/repeat_start", (uint32_t)rc, 0u);
        aes_read_result(res);
        CHECK_EQ("aes/repeat_ct0", res[0], aes_cipher[0]);
    }
    return 0;
}

TEST_CASE(t_aes_reg_readback)
TEST_CASE(t_aes_start_wait)
TEST_CASE(t_aes_ciphertext)
TEST_CASE(t_aes_clear_done)
TEST_CASE(t_aes_repeat)
