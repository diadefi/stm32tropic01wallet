#include "main.h"

#include "psa/crypto.h"
#include "psa/crypto_driver_common.h"

#include "mbedtls/platform.h"
#include "mbedtls/platform_util.h"

#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

/*
 * STM32CubeMX creates this RNG handle in main.c.
 */
extern RNG_HandleTypeDef hrng;

/*
 * Debug variables.
 * Add these to STM32CubeIDE Expressions:
 *
 * entropy_hook_calls
 * entropy_hook_last_output_size
 * entropy_hook_last_estimate_bits
 * entropy_hook_last_status
 */
volatile uint32_t entropy_hook_calls = 0;
volatile size_t entropy_hook_last_output_size = 0;
volatile size_t entropy_hook_last_estimate_bits = 0;
volatile int entropy_hook_last_status = 0;

/*
 * Secure zeroize.
 */
void mbedtls_platform_zeroize(void *buf, size_t len)
{
    volatile unsigned char *p = (volatile unsigned char *)buf;

    while (len--)
    {
        *p++ = 0;
    }
}

/*
 * Some MbedTLS/TF-PSA builds expect this helper.
 */
void mbedtls_zeroize_and_free(void *buf, size_t len)
{
    if (buf != NULL)
    {
        mbedtls_platform_zeroize(buf, len);
        free(buf);
    }
}

/*
 * TF-PSA-Crypto platform entropy hook.
 *
 * Important:
 *   TF-PSA currently expects this function to return full entropy.
 *   That means:
 *
 *      *estimate_bits = 8 * output_size;
 *
 *   If estimate_bits is smaller, PSA treats it like insufficient entropy.
 */
int mbedtls_platform_get_entropy(
    psa_driver_get_entropy_flags_t flags,
    size_t *estimate_bits,
    unsigned char *output,
    size_t output_size
)
{
    (void)flags;

    entropy_hook_calls++;
    entropy_hook_last_output_size = output_size;
    entropy_hook_last_estimate_bits = 0;
    entropy_hook_last_status = PSA_ERROR_INSUFFICIENT_ENTROPY;

    if (estimate_bits == NULL || output == NULL)
    {
        return PSA_ERROR_INSUFFICIENT_ENTROPY;
    }

    *estimate_bits = 0;

    if (output_size == 0)
    {
        entropy_hook_last_status = PSA_SUCCESS;
        return PSA_SUCCESS;
    }

    size_t offset = 0;

    while (offset < output_size)
    {
        uint32_t random_word = 0;

        HAL_StatusTypeDef ret = HAL_RNG_GenerateRandomNumber(&hrng, &random_word);

        if (ret != HAL_OK)
        {
            *estimate_bits = 0;
            entropy_hook_last_estimate_bits = 0;
            entropy_hook_last_status = PSA_ERROR_INSUFFICIENT_ENTROPY;
            return PSA_ERROR_INSUFFICIENT_ENTROPY;
        }

        size_t remaining = output_size - offset;
        size_t copy_len = remaining;

        if (copy_len > sizeof(random_word))
        {
            copy_len = sizeof(random_word);
        }

        memcpy(&output[offset], &random_word, copy_len);
        offset += copy_len;
    }

    /*
     * Critical for TF-PSA-Crypto:
     * report full entropy.
     */
    *estimate_bits = output_size * 8U;

    entropy_hook_last_estimate_bits = *estimate_bits;
    entropy_hook_last_status = PSA_SUCCESS;

    return PSA_SUCCESS;
}
