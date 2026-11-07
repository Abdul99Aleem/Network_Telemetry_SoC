#include <stdint.h>
#include "soc.h"
#include "aes.h"

void aes_write_key(const uint32_t key[4])
{
    AES_REG32(AES_OFF_KEY0) = key[0];
    AES_REG32(AES_OFF_KEY1) = key[1];
    AES_REG32(AES_OFF_KEY2) = key[2];
    AES_REG32(AES_OFF_KEY3) = key[3];
}

void aes_write_data(const uint32_t data[4])
{
    AES_REG32(AES_OFF_DATA0) = data[0];
    AES_REG32(AES_OFF_DATA1) = data[1];
    AES_REG32(AES_OFF_DATA2) = data[2];
    AES_REG32(AES_OFF_DATA3) = data[3];
}

void aes_read_result(uint32_t result[4])
{
    result[0] = AES_REG32(AES_OFF_RESULT0);
    result[1] = AES_REG32(AES_OFF_RESULT1);
    result[2] = AES_REG32(AES_OFF_RESULT2);
    result[3] = AES_REG32(AES_OFF_RESULT3);
}

void aes_clear_done(void)
{
    AES_REG32(AES_OFF_CONTROL) = AES_CTRL_CLEAR_DONE;
}

int aes_start_and_wait(void)
{
    uint32_t n;

    aes_clear_done();
    AES_REG32(AES_OFF_CONTROL) = AES_CTRL_START;

    for (n = 0; n < AES_POLL_LIMIT; n++) {
        if ((AES_REG32(AES_OFF_STATUS) & AES_STATUS_DONE) != 0u)
            return 0;
    }
    return 1;
}
