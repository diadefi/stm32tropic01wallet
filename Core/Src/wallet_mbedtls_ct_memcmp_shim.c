/*
 * Compatibility shim for MbedTLS constant-time compare.
 *
 * Some TF-PSA-Crypto objects reference mbedtls_ct_memcmp(), but the
 * corresponding utility object is not currently linked by this CubeIDE project.
 *
 * Returns 0 when equal, nonzero when different.
 */
#include <stddef.h>
#include <stdint.h>

int mbedtls_ct_memcmp(const void *a, const void *b, size_t n)
{
    const uint8_t *pa = (const uint8_t *)a;
    const uint8_t *pb = (const uint8_t *)b;
    uint8_t diff = 0U;

    for (size_t i = 0; i < n; i++)
    {
        diff |= (uint8_t)(pa[i] ^ pb[i]);
    }

    return (int)diff;
}
