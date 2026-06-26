#include <stddef.h>
#include <stdint.h>
#include <string.h>

/*
 * Minimal link shims for TF-PSA/MbedTLS objects that are pulled into the
 * STM32CubeIDE link but are not used by the wallet's AES-GCM key-blob path.
 *
 * These unblock unused RSA/ASN.1/bignum helper references.
 * Do not use these as real ASN.1 implementations.
 */

typedef unsigned int mbedtls_ct_condition_t;

mbedtls_ct_condition_t mbedtls_ct_zero(size_t value)
{
    return (value == 0U) ? (mbedtls_ct_condition_t)~0U : 0U;
}

void mbedtls_ct_memcpy_if(mbedtls_ct_condition_t condition,
                          unsigned char *dest,
                          const unsigned char *src,
                          size_t len)
{
    unsigned char mask;

    if (dest == NULL || src == NULL)
    {
        return;
    }

    mask = (condition != 0U) ? 0xffU : 0x00U;

    for (size_t i = 0U; i < len; i++)
    {
        dest[i] = (unsigned char)((dest[i] & (unsigned char)~mask) |
                                  (src[i]  & mask));
    }
}

int mbedtls_asn1_get_tag(unsigned char **p,
                         const unsigned char *end,
                         size_t *len,
                         int tag)
{
    (void)p;
    (void)end;
    (void)len;
    (void)tag;
    return -1;
}

int mbedtls_asn1_get_int(unsigned char **p,
                         const unsigned char *end,
                         int *val)
{
    (void)p;
    (void)end;
    (void)val;
    return -1;
}

int mbedtls_asn1_write_len(unsigned char **p,
                           unsigned char *start,
                           size_t len)
{
    (void)p;
    (void)start;
    (void)len;
    return -1;
}

int mbedtls_asn1_write_tag(unsigned char **p,
                           unsigned char *start,
                           unsigned char tag)
{
    (void)p;
    (void)start;
    (void)tag;
    return -1;
}

int mbedtls_asn1_write_int(unsigned char **p,
                           unsigned char *start,
                           int val)
{
    (void)p;
    (void)start;
    (void)val;
    return -1;
}
