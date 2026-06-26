#include "main.h"
#include "psa/crypto.h"
#include <stdint.h>
#include <stddef.h>

uint32_t random32(void)
{
    uint32_t word = 0;

    if (psa_generate_random((uint8_t *)&word, sizeof(word)) == PSA_SUCCESS)
    {
        return word;
    }

    return 0;
}

void random_buffer(uint8_t *buf, size_t len)
{
    if (buf == NULL || len == 0)
    {
        return;
    }

    if (psa_generate_random(buf, len) != PSA_SUCCESS)
    {
        for (size_t i = 0; i < len; i++)
        {
            buf[i] = 0;
        }
    }
}

void random_reseed(const uint32_t value)
{
    (void)value;
}
