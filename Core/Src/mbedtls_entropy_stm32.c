#include "main.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

/*
 * Minimal entropy shim for TF-PSA-Crypto.
 * We intentionally do NOT include "mbedtls/entropy.h" because this project
 * does not have that legacy MbedTLS header.
 */

typedef struct mbedtls_entropy_context
{
    int dummy;
} mbedtls_entropy_context;

extern RNG_HandleTypeDef hrng;

void mbedtls_entropy_init(mbedtls_entropy_context *ctx)
{
    (void)ctx;
}

void mbedtls_entropy_free(mbedtls_entropy_context *ctx)
{
    (void)ctx;
}

int mbedtls_entropy_func(void *data, unsigned char *output, size_t len)
{
    (void)data;

    if (output == NULL)
    {
        return -1;
    }

    size_t offset = 0U;

    while (offset < len)
    {
        uint32_t word = 0U;

        if (HAL_RNG_GenerateRandomNumber(&hrng, &word) != HAL_OK)
        {
            return -1;
        }

        size_t remaining = len - offset;
        size_t copy_len = remaining;

        if (copy_len > sizeof(word))
        {
            copy_len = sizeof(word);
        }

        memcpy(&output[offset], &word, copy_len);
        offset += copy_len;
    }

    return 0;
}
