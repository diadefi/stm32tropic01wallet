#include "wallet_key_provider.h"
#include "wallet_build_config.h"
#include "wallet_secure_element.h"
#include "stm32u5xx_hal.h"

#include "psa/crypto.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#ifndef WALLET_ENABLE_DEV_PRIVATE_KEY
#define WALLET_ENABLE_DEV_PRIVATE_KEY 0
#endif

#define WALLET_KDF_ROUNDS           1000U

/*
 * C1.6 KDF + AES-GCM key blob MVP.
 *
 * The long-term secp256k1 test key is not stored directly as a plaintext
 * byte array or plaintext hex literal in firmware.
 *
 * Unwrap flow:
 *
 * round0 = SHA256("WALLET_KDF_V1_ROUND0" || salt || credential)
 *
 * repeat WALLET_KDF_ROUNDS times:
 *     key = SHA256("WALLET_KDF_V1" || salt || previous_key || credential)
 *
 * plaintext_key = PSA_AES_GCM_DECRYPT(key, nonce, aad, ciphertext || tag)
 *
 * This is stronger than single-SHA256 key derivation. It is still an MVP
 * because it is not memory-hard like Argon2/scrypt and has no attempt counter.
 */
static const uint8_t WALLET_KEY_BLOB_SALT[16] =
{
    0xc1, 0xd2, 0xe3, 0xf4,
    0x05, 0x16, 0x27, 0x38,
    0x49, 0x5a, 0x6b, 0x7c,
    0x8d, 0x9e, 0xaf, 0x01
};

static const uint8_t WALLET_KEY_BLOB_NONCE[12] =
{
    0xa0, 0xa1, 0xa2, 0xa3,
    0xa4, 0xa5, 0xa6, 0xa7,
    0xa8, 0xa9, 0xaa, 0xab
};

static const uint8_t WALLET_KEY_BLOB_AAD[] =
    "STM32_WALLET_SECP256K1_KEY_BLOB_V2_KDF";

/*
 * AES-GCM ciphertext || 16-byte tag.
 *
 * Generated for the current regtest secp256k1 test key using the C4.2
 * PIN-session credential as the KDF secret.
 */
static const uint8_t WALLET_KEY_BLOB_AEAD[48] =
{
    0x3e, 0x04, 0x57, 0x6c,
    0x17, 0x06, 0x46, 0x0f,
    0xc2, 0xbe, 0x71, 0x5c,
    0x30, 0x03, 0x84, 0xb2,
    0xa1, 0xea, 0x3e, 0x4f,
    0xfe, 0x9c, 0x6c, 0x81,
    0xa9, 0x2c, 0x09, 0xd9,
    0xc3, 0xfc, 0x0d, 0xf9,

    0x49, 0x4e, 0x52, 0xb0,
    0xc7, 0x56, 0x3c, 0x34,
    0xef, 0x40, 0x13, 0x56,
    0x40, 0x51, 0x0e, 0x31
};

static uint8_t wallet_key_provider_session_key[WALLET_KEY_PROVIDER_PRIVKEY_BYTES_LEN];
static int wallet_key_provider_session_unlocked = 0;
static uint32_t wallet_key_provider_session_started_ms = 0U;
static uint32_t wallet_key_provider_pin_failures = 0U;
static uint32_t wallet_key_provider_pin_retry_until_ms = 0U;

static void wallet_key_provider_secure_zero(uint8_t *buf, size_t len)
{
    volatile uint8_t *p = (volatile uint8_t *)buf;

    if (p == NULL)
    {
        return;
    }

    while (len > 0U)
    {
        *p = 0U;
        p++;
        len--;
    }
}

void wallet_key_provider_lock_session(void)
{
    wallet_key_provider_secure_zero(wallet_key_provider_session_key,
                                    sizeof(wallet_key_provider_session_key));
    wallet_key_provider_session_unlocked = 0;
    wallet_key_provider_session_started_ms = 0U;
}

static int wallet_key_provider_session_expired(void)
{
    uint32_t now_ms;

    if (!wallet_key_provider_session_unlocked)
    {
        return 0;
    }

    now_ms = HAL_GetTick();
    if ((now_ms - wallet_key_provider_session_started_ms) >=
        WALLET_KEY_PROVIDER_PIN_SESSION_TIMEOUT_MS)
    {
        wallet_key_provider_lock_session();
        return 1;
    }

    return 0;
}

int wallet_key_provider_session_is_unlocked(void)
{
    if (wallet_key_provider_session_expired())
    {
        return 0;
    }

    return wallet_key_provider_session_unlocked;
}

uint32_t wallet_key_provider_session_age_ms(void)
{
    if (wallet_key_provider_session_expired())
    {
        return 0U;
    }

    if (!wallet_key_provider_session_unlocked)
    {
        return 0U;
    }

    return HAL_GetTick() - wallet_key_provider_session_started_ms;
}

uint32_t wallet_key_provider_pin_fail_count(void)
{
    return wallet_key_provider_pin_failures;
}

uint32_t wallet_key_provider_pin_retry_remaining_ms(void)
{
    uint32_t now_ms = HAL_GetTick();

    if (wallet_key_provider_pin_retry_until_ms == 0U ||
        (int32_t)(wallet_key_provider_pin_retry_until_ms - now_ms) <= 0)
    {
        wallet_key_provider_pin_retry_until_ms = 0U;
        return 0U;
    }

    return wallet_key_provider_pin_retry_until_ms - now_ms;
}

static int wallet_key_provider_sha256_4(const uint8_t *a, size_t a_len,
                                        const uint8_t *b, size_t b_len,
                                        const uint8_t *c, size_t c_len,
                                        const uint8_t *d, size_t d_len,
                                        uint8_t out[32])
{
    psa_hash_operation_t op = PSA_HASH_OPERATION_INIT;
    psa_status_t status;
    size_t hash_len = 0U;

    status = psa_hash_setup(&op, PSA_ALG_SHA_256);
    if (status != PSA_SUCCESS)
    {
        return -1;
    }

    if (a != NULL && a_len > 0U)
    {
        status = psa_hash_update(&op, a, a_len);
        if (status != PSA_SUCCESS) { psa_hash_abort(&op); return -2; }
    }

    if (b != NULL && b_len > 0U)
    {
        status = psa_hash_update(&op, b, b_len);
        if (status != PSA_SUCCESS) { psa_hash_abort(&op); return -3; }
    }

    if (c != NULL && c_len > 0U)
    {
        status = psa_hash_update(&op, c, c_len);
        if (status != PSA_SUCCESS) { psa_hash_abort(&op); return -4; }
    }

    if (d != NULL && d_len > 0U)
    {
        status = psa_hash_update(&op, d, d_len);
        if (status != PSA_SUCCESS) { psa_hash_abort(&op); return -5; }
    }

    status = psa_hash_finish(&op, out, 32U, &hash_len);
    if (status != PSA_SUCCESS || hash_len != 32U)
    {
        psa_hash_abort(&op);
        return -6;
    }

    return 0;
}

static int wallet_key_provider_derive_aes_key_kdf(const char *credential,
                                                  size_t credential_len,
                                                  uint8_t aes_key[32])
{
    static const uint8_t round0_label[] = "WALLET_KDF_V1_ROUND0";
    static const uint8_t round_label[] = "WALLET_KDF_V1";

    uint8_t tmp[32];

    if (credential == NULL || credential_len == 0U || aes_key == NULL)
    {
        return WALLET_KEY_PROVIDER_ERR_UNLOCK_MISSING;
    }

    memset(aes_key, 0, 32U);
    memset(tmp, 0, sizeof(tmp));

    if (wallet_key_provider_sha256_4(round0_label,
                                     sizeof(round0_label) - 1U,
                                     WALLET_KEY_BLOB_SALT,
                                     sizeof(WALLET_KEY_BLOB_SALT),
                                     (const uint8_t *)credential,
                                     credential_len,
                                     NULL,
                                     0U,
                                     aes_key) != 0)
    {
        wallet_key_provider_secure_zero(tmp, sizeof(tmp));
        return -30;
    }

    for (uint32_t i = 0U; i < WALLET_KDF_ROUNDS; i++)
    {
        if (wallet_key_provider_sha256_4(round_label,
                                         sizeof(round_label) - 1U,
                                         WALLET_KEY_BLOB_SALT,
                                         sizeof(WALLET_KEY_BLOB_SALT),
                                         aes_key,
                                         32U,
                                         (const uint8_t *)credential,
                                         credential_len,
                                         tmp) != 0)
        {
            wallet_key_provider_secure_zero(tmp, sizeof(tmp));
            wallet_key_provider_secure_zero(aes_key, 32U);
            return -31;
        }

        memcpy(aes_key, tmp, 32U);
        wallet_key_provider_secure_zero(tmp, sizeof(tmp));
    }

    return 0;
}

static int wallet_key_provider_unwrap_blob_aes_gcm(const char *credential,
                                                   size_t credential_len,
                                                   uint8_t *out_key,
                                                   size_t out_key_size)
{
    uint8_t aes_key[32];
    psa_key_attributes_t attributes = PSA_KEY_ATTRIBUTES_INIT;
    psa_key_id_t key_id = 0;
    psa_status_t status;
    size_t plaintext_len = 0U;

    if (credential == NULL || credential_len == 0U)
    {
        return WALLET_KEY_PROVIDER_ERR_UNLOCK_MISSING;
    }

    if (out_key == NULL || out_key_size < WALLET_KEY_PROVIDER_PRIVKEY_BYTES_LEN)
    {
        return -2;
    }

    memset(aes_key, 0, sizeof(aes_key));
    wallet_key_provider_secure_zero(out_key, out_key_size);

    if (wallet_key_provider_derive_aes_key_kdf(credential,
                                               credential_len,
                                               aes_key) != 0)
    {
        wallet_key_provider_secure_zero(aes_key, sizeof(aes_key));
        return -30;
    }

    psa_set_key_type(&attributes, PSA_KEY_TYPE_AES);
    psa_set_key_bits(&attributes, 256U);
    psa_set_key_usage_flags(&attributes, PSA_KEY_USAGE_DECRYPT);
    psa_set_key_algorithm(&attributes, PSA_ALG_GCM);

    status = psa_import_key(&attributes,
                            aes_key,
                            sizeof(aes_key),
                            &key_id);

    wallet_key_provider_secure_zero(aes_key, sizeof(aes_key));
    psa_reset_key_attributes(&attributes);

    if (status != PSA_SUCCESS)
    {
        wallet_key_provider_secure_zero(out_key, out_key_size);
        return -31;
    }

    status = psa_aead_decrypt(key_id,
                              PSA_ALG_GCM,
                              WALLET_KEY_BLOB_NONCE,
                              sizeof(WALLET_KEY_BLOB_NONCE),
                              WALLET_KEY_BLOB_AAD,
                              sizeof(WALLET_KEY_BLOB_AAD) - 1U,
                              WALLET_KEY_BLOB_AEAD,
                              sizeof(WALLET_KEY_BLOB_AEAD),
                              out_key,
                              out_key_size,
                              &plaintext_len);

    (void)psa_destroy_key(key_id);

    if (status != PSA_SUCCESS || plaintext_len != WALLET_KEY_PROVIDER_PRIVKEY_BYTES_LEN)
    {
        wallet_key_provider_secure_zero(out_key, out_key_size);
        return WALLET_KEY_PROVIDER_ERR_UNLOCK_BAD;
    }

    return 0;
}

int wallet_key_provider_unlock_with_pin(const char *pin_text)
{
    uint32_t now_ms = HAL_GetTick();
    int unwrap_ret;

    if (pin_text == NULL || pin_text[0] == '\0' ||
        pin_text[0] == '\r' || pin_text[0] == '\n')
    {
        return WALLET_KEY_PROVIDER_ERR_UNLOCK_MISSING;
    }

    if (wallet_key_provider_pin_retry_remaining_ms() > 0U)
    {
        return WALLET_KEY_PROVIDER_ERR_PIN_LOCKED;
    }

    wallet_key_provider_lock_session();

    unwrap_ret = wallet_key_provider_unwrap_blob_aes_gcm(
        pin_text,
        strlen(pin_text),
        wallet_key_provider_session_key,
        sizeof(wallet_key_provider_session_key));

    if (unwrap_ret != 0)
    {
        if (wallet_key_provider_pin_failures < 0xffffffffU)
        {
            wallet_key_provider_pin_failures++;
        }

        if (wallet_key_provider_pin_failures >= WALLET_KEY_PROVIDER_PIN_MAX_ATTEMPTS)
        {
            wallet_key_provider_pin_retry_until_ms = now_ms + WALLET_KEY_PROVIDER_PIN_RETRY_DELAY_MS;
        }

        wallet_key_provider_lock_session();
        return WALLET_KEY_PROVIDER_ERR_UNLOCK_BAD;
    }

    wallet_key_provider_pin_failures = 0U;
    wallet_key_provider_pin_retry_until_ms = 0U;
    wallet_key_provider_session_unlocked = 1;
    wallet_key_provider_session_started_ms = now_ms;
    return 0;
}

int wallet_key_provider_get_private_key_bytes_for_command(const char *command_text,
                                                          uint8_t *out_key,
                                                          size_t out_key_size)
{
    int se_ret;

    if (out_key == NULL)
    {
        return -1;
    }

    if (out_key_size < WALLET_KEY_PROVIDER_PRIVKEY_BYTES_LEN)
    {
        return -2;
    }

    wallet_key_provider_secure_zero(out_key, out_key_size);
    (void)command_text;

    if (wallet_key_provider_session_expired())
    {
        return WALLET_KEY_PROVIDER_ERR_PIN_EXPIRED;
    }

    if (!wallet_key_provider_session_unlocked)
    {
        return WALLET_KEY_PROVIDER_ERR_UNLOCK_MISSING;
    }

    /*
     * Secure-element authorization gate still happens before key unwrap.
     */
    se_ret = wallet_secure_element_authorize_key_use();

    if (se_ret != 0)
    {
        wallet_key_provider_secure_zero(out_key, out_key_size);
        return -10;
    }

    memcpy(out_key, wallet_key_provider_session_key, WALLET_KEY_PROVIDER_PRIVKEY_BYTES_LEN);
    wallet_key_provider_lock_session();

    return 0;
}

/*
 * Legacy wrapper.
 *
 * Keep symbol for older code/tests, but do not allow key release without
 * command-provided unlock material.
 */
int wallet_key_provider_get_private_key_bytes(uint8_t *out_key,
                                               size_t out_key_size)
{
    if (out_key != NULL)
    {
        wallet_key_provider_secure_zero(out_key, out_key_size);
    }

    return WALLET_KEY_PROVIDER_ERR_UNLOCK_MISSING;
}

int wallet_key_provider_get_private_key_hex(char *out_hex,
                                            size_t out_hex_size)
{
    if (out_hex != NULL && out_hex_size > 0U)
    {
        out_hex[0] = '\0';
    }

    return -99;
}


