#include "wallet_debug_test.h"
#include "wallet_core.h"

#include "psa/crypto.h"

#include "ecdsa.h"
#include "secp256k1.h"
#include "ripemd160.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

extern RNG_HandleTypeDef hrng;

/* ------------------------------------------------------------
 * GLOBAL DEBUG VARIABLES
 * ------------------------------------------------------------ */

volatile uint32_t debug_stage = 0;

/* HAL / PSA diagnostics */
volatile HAL_StatusTypeDef hal_rng_ret = HAL_ERROR;
volatile uint32_t hal_rng_word = 0;
volatile psa_status_t psa_init_ret = 12345;

/* SHA diagnostics */
volatile psa_status_t psa_sha_ret = 12345;
volatile uint32_t psa_sha_len = 0;

/* secp256k1 diagnostics */
volatile uint8_t secp_privkey[32] = {0};
volatile uint8_t secp_pubkey[65] = {0};
volatile uint8_t secp_pubkey_compressed[33] = {0};
volatile uint8_t hash160_sha256[32] = {0};
volatile uint8_t hash160_out[20] = {0};

volatile int secp_pubkey_ok = 0;
volatile int secp_pubkey_compressed_ok = 0;
volatile int hash160_ok = 0;

/* Transaction signing diagnostics */
volatile uint8_t tx_preimage[192] = {0};
volatile uint32_t tx_preimage_len = 0;

volatile uint8_t tx_hash1[32] = {0};
volatile uint8_t tx_digest[32] = {0};

volatile psa_status_t tx_sha1_ret = 12345;
volatile psa_status_t tx_sha2_ret = 12345;
volatile uint32_t tx_sha1_len = 0;
volatile uint32_t tx_sha2_len = 0;

volatile uint8_t tx_signature64[64] = {0};
volatile uint8_t tx_signature_der[80] = {0};
volatile uint8_t tx_signature_der_sighash[81] = {0};

volatile int tx_sign_ret = 999;
volatile int tx_verify_ret = 999;
volatile int tx_signature_der_len = 0;
volatile int tx_signature_der_sighash_len = 0;

volatile int tx_der_ok = 0;
volatile int tx_sighash_byte_ok = 0;
volatile int tx_signing_ok = 0;

/* Reusable transaction builder diagnostics */
volatile int tx_preimage_build_ret = 999;
volatile int signed_tx_build_ret = 999;

/* Signed raw transaction diagnostics */
volatile uint8_t signed_tx_raw[512] = {0};
volatile uint32_t signed_tx_len = 0;
volatile uint32_t signed_tx_expected_len = 0;
volatile uint32_t signed_tx_script_sig_len = 0;

volatile int signed_tx_len_match = 0;
volatile int signed_tx_script_sig_ok = 0;
volatile int signed_tx_prefix_ok = 0;
volatile int signed_tx_ok = 0;

/* Hex export diagnostics */
char signed_tx_hex[1024] = {0};

volatile uint32_t signed_tx_hex_len = 0;
volatile uint32_t signed_tx_hex_expected_len = 0;
volatile uint32_t signed_tx_hex_ok = 0;

char signed_tx_hex_part0[101] = {0};
char signed_tx_hex_part1[101] = {0};
char signed_tx_hex_part2[101] = {0};
char signed_tx_hex_part3[101] = {0};
char signed_tx_hex_part4[101] = {0};

volatile uint32_t signed_tx_hex_parts_ok = 0;

static void wallet_fail(uint32_t stage)
{
    debug_stage = stage;

    while (1)
    {
        __NOP();
    }
}

void wallet_debug_run_regression_test(void)
{
    debug_stage = 10;

    /* 1. HAL RNG smoke test */
    hal_rng_word = 0;

    hal_rng_ret = HAL_RNG_GenerateRandomNumber(
        &hrng,
        (uint32_t *)&hal_rng_word
    );

    debug_stage = 15;

    if (hal_rng_ret != HAL_OK)
    {
        wallet_fail(16);
    }

    /* 2. PSA crypto init */
    psa_init_ret = psa_crypto_init();

    debug_stage = 20;

    if (psa_init_ret != PSA_SUCCESS)
    {
        wallet_fail(21);
    }

    /* 3. Key-blob MVP: plaintext secp256k1 debug key removed from source. */
    debug_stage = 100;

    memset((void *)secp_privkey, 0, sizeof(secp_privkey));
    secp_privkey[31] = 0x01;

    memset((void *)secp_pubkey, 0, sizeof(secp_pubkey));
    memset((void *)secp_pubkey_compressed, 0, sizeof(secp_pubkey_compressed));

    ecdsa_get_public_key65(
        &secp256k1,
        (const uint8_t *)secp_privkey,
        (uint8_t *)secp_pubkey
    );

    debug_stage = 110;

    if (secp_pubkey[0] != 0x04)
    {
        wallet_fail(111);
    }

    secp_pubkey_ok = 1;

    ecdsa_get_public_key33(
        &secp256k1,
        (const uint8_t *)secp_privkey,
        (uint8_t *)secp_pubkey_compressed
    );

    debug_stage = 120;

    if (secp_pubkey_compressed[0] != 0x02 &&
        secp_pubkey_compressed[0] != 0x03)
    {
        wallet_fail(121);
    }

    secp_pubkey_compressed_ok = 1;

    /* 4. HASH160(compressed pubkey) */
    debug_stage = 130;

    memset((void *)hash160_sha256, 0, sizeof(hash160_sha256));
    memset((void *)hash160_out, 0, sizeof(hash160_out));

    size_t hash_len_local = 0;

    psa_sha_ret = psa_hash_compute(
        PSA_ALG_SHA_256,
        (const uint8_t *)secp_pubkey_compressed,
        33,
        (uint8_t *)hash160_sha256,
        32,
        &hash_len_local
    );

    psa_sha_len = (uint32_t)hash_len_local;

    if (psa_sha_ret != PSA_SUCCESS || psa_sha_len != 32U)
    {
        wallet_fail(131);
    }

    ripemd160(
        (const void *)hash160_sha256,
        32,
        (void *)hash160_out
    );

    static const uint8_t expected_hash160[20] =
    {
        0x75, 0x1E, 0x76, 0xE8, 0x19,
        0x91, 0x96, 0xD4, 0x54, 0x94,
        0x1C, 0x45, 0xD1, 0xB3, 0xA3,
        0x23, 0xF1, 0x43, 0x3B, 0xD6
    };

    hash160_ok = 1;

    for (uint32_t i = 0; i < 20U; i++)
    {
        if (hash160_out[i] != expected_hash160[i])
        {
            hash160_ok = 0;
            break;
        }
    }

    debug_stage = 140;

    if (hash160_ok != 1)
    {
        wallet_fail(141);
    }

    /* ------------------------------------------------------------
     * 5. Reusable transaction parameters
     * ------------------------------------------------------------ */

    debug_stage = 3000;

    static const uint8_t regtest_prev_txid_le[32] =
    {
        0xC2, 0xBD, 0x53, 0x0E,
        0xD9, 0xD7, 0xE4, 0x0B,
        0xA4, 0x70, 0x27, 0xE8,
        0xFF, 0xEE, 0x41, 0xAA,
        0x5B, 0x62, 0xC0, 0xBA,
        0x36, 0xE5, 0xC2, 0x00,
        0x03, 0xCA, 0x63, 0x30,
        0x9D, 0xAD, 0x31, 0xC8
    };

    static const uint8_t regtest_prev_script_pubkey[25] =
    {
        0x76, 0xA9, 0x14,
        0x75, 0x1E, 0x76, 0xE8, 0x19,
        0x91, 0x96, 0xD4, 0x54, 0x94,
        0x1C, 0x45, 0xD1, 0xB3, 0xA3,
        0x23, 0xF1, 0x43, 0x3B, 0xD6,
        0x88, 0xAC
    };

    static const uint8_t regtest_pay_script_pubkey[25] =
    {
        0x76, 0xA9, 0x14, 0xF2,
        0x12, 0x4D, 0x94, 0xCA,
        0xBD, 0xB9, 0x5D, 0x49,
        0x47, 0x96, 0x27, 0xCB,
        0xBE, 0x5D, 0x7B, 0xE6,
        0x09, 0xF7, 0x38, 0x88,
        0xAC
    };

    static const uint8_t regtest_change_script_pubkey[25] =
    {
        0x76, 0xA9, 0x14, 0x75,
        0x1E, 0x76, 0xE8, 0x19,
        0x91, 0x96, 0xD4, 0x54,
        0x94, 0x1C, 0x45, 0xD1,
        0xB3, 0xA3, 0x23, 0xF1,
        0x43, 0x3B, 0xD6, 0x88,
        0xAC
    };

    wallet_legacy_p2pkh_tx_t tx_params;

    tx_params.prev_txid_le = regtest_prev_txid_le;
    tx_params.prev_vout = 1U;

    tx_params.prev_script_pubkey = regtest_prev_script_pubkey;
    tx_params.prev_script_pubkey_len = sizeof(regtest_prev_script_pubkey);

    /* output 0: payment to recipient */
    tx_params.pay_script_pubkey = regtest_pay_script_pubkey;
    tx_params.pay_script_pubkey_len = sizeof(regtest_pay_script_pubkey);
    tx_params.pay_value_sats = 60000ULL;

    /* output 1: change back to STM32 wallet address */
    tx_params.change_script_pubkey = regtest_change_script_pubkey;
    tx_params.change_script_pubkey_len = sizeof(regtest_change_script_pubkey);
    tx_params.change_value_sats = 30000ULL;

    tx_params.sequence = 0xFFFFFFFFU;
    tx_params.locktime = 0U;

    /* 6. Build reusable SIGHASH_ALL preimage */
    debug_stage = 3010;

    tx_preimage_build_ret = wallet_build_legacy_p2pkh_sighash_preimage(
        &tx_params,
        (uint8_t *)tx_preimage,
        sizeof(tx_preimage),
        (uint32_t *)&tx_preimage_len
    );

    if (tx_preimage_build_ret != 0)
    {
        wallet_fail(3015);
    }

    if (tx_preimage_len == 0U || tx_preimage_len > sizeof(tx_preimage))
    {
        wallet_fail(3016);
    }

    /* First SHA256(preimage) */
    debug_stage = 3020;

    memset((void *)tx_hash1, 0, sizeof(tx_hash1));
    memset((void *)tx_digest, 0, sizeof(tx_digest));

    size_t tx_hash_len_local = 0;

    tx_sha1_ret = psa_hash_compute(
        PSA_ALG_SHA_256,
        (const uint8_t *)tx_preimage,
        tx_preimage_len,
        (uint8_t *)tx_hash1,
        32,
        &tx_hash_len_local
    );

    tx_sha1_len = (uint32_t)tx_hash_len_local;

    if (tx_sha1_ret != PSA_SUCCESS || tx_sha1_len != 32U)
    {
        wallet_fail(3025);
    }

    /* Second SHA256(first hash) */
    debug_stage = 3030;

    tx_hash_len_local = 0;

    tx_sha2_ret = psa_hash_compute(
        PSA_ALG_SHA_256,
        (const uint8_t *)tx_hash1,
        32,
        (uint8_t *)tx_digest,
        32,
        &tx_hash_len_local
    );

    tx_sha2_len = (uint32_t)tx_hash_len_local;

    if (tx_sha2_ret != PSA_SUCCESS || tx_sha2_len != 32U)
    {
        wallet_fail(3035);
    }

    /* 7. Sign transaction digest */
    debug_stage = 3040;

    memset((void *)tx_signature64, 0, sizeof(tx_signature64));
    memset((void *)tx_signature_der, 0, sizeof(tx_signature_der));
    memset((void *)tx_signature_der_sighash, 0, sizeof(tx_signature_der_sighash));

    tx_der_ok = 0;
    tx_sighash_byte_ok = 0;
    tx_signing_ok = 0;

    tx_sign_ret = ecdsa_sign_digest(
        &secp256k1,
        (const uint8_t *)secp_privkey,
        (const uint8_t *)tx_digest,
        (uint8_t *)tx_signature64,
        NULL,
        NULL
    );

    debug_stage = 3045;

    if (tx_sign_ret != 0)
    {
        wallet_fail(3046);
    }

    /* Verify signature locally */
    debug_stage = 3050;

    tx_verify_ret = ecdsa_verify_digest(
        &secp256k1,
        (const uint8_t *)secp_pubkey,
        (const uint8_t *)tx_signature64,
        (const uint8_t *)tx_digest
    );

    debug_stage = 3055;

    if (tx_verify_ret != 0)
    {
        wallet_fail(3056);
    }

    /* DER encode signature */
    debug_stage = 3060;

    tx_signature_der_len = ecdsa_sig_to_der(
        (const uint8_t *)tx_signature64,
        (uint8_t *)tx_signature_der
    );

    debug_stage = 3065;

    if (tx_signature_der_len <= 0 || tx_signature_der_len > 80)
    {
        wallet_fail(3066);
    }

    if (tx_signature_der[0] == 0x30 &&
        tx_signature_der[2] == 0x02 &&
        ((uint32_t)tx_signature_der[1] + 2U) == (uint32_t)tx_signature_der_len)
    {
        tx_der_ok = 1;
    }

    if (tx_der_ok != 1)
    {
        wallet_fail(3067);
    }

    /* Append SIGHASH_ALL byte */
    debug_stage = 3070;

    for (uint32_t i = 0; i < (uint32_t)tx_signature_der_len; i++)
    {
        tx_signature_der_sighash[i] = tx_signature_der[i];
    }

    tx_signature_der_sighash[tx_signature_der_len] = 0x01;
    tx_signature_der_sighash_len = tx_signature_der_len + 1;

    if (tx_signature_der_sighash[tx_signature_der_sighash_len - 1] == 0x01)
    {
        tx_sighash_byte_ok = 1;
    }

    if (tx_sighash_byte_ok != 1)
    {
        wallet_fail(3075);
    }

    tx_signing_ok = 1;

    debug_stage = 3080;

    /* 8. Build signed transaction with reusable helper */
    debug_stage = 3100;

    signed_tx_len = 0;
    signed_tx_expected_len = 0;
    signed_tx_script_sig_len = 0;

    signed_tx_len_match = 0;
    signed_tx_script_sig_ok = 0;
    signed_tx_prefix_ok = 0;
    signed_tx_ok = 0;

    signed_tx_build_ret = wallet_build_signed_legacy_p2pkh_tx(
        &tx_params,
        (const uint8_t *)tx_signature_der_sighash,
        (uint32_t)tx_signature_der_sighash_len,
        (const uint8_t *)secp_pubkey_compressed,
        (uint8_t *)signed_tx_raw,
        sizeof(signed_tx_raw),
        (uint32_t *)&signed_tx_len,
        (uint32_t *)&signed_tx_script_sig_len
    );

    debug_stage = 3110;

    if (signed_tx_build_ret != 0)
    {
        wallet_fail(3115);
    }

    signed_tx_expected_len =
        4U + 1U + 32U + 4U + 1U +
        signed_tx_script_sig_len +
        4U + 1U +
        8U + 1U + tx_params.pay_script_pubkey_len +
        8U + 1U + tx_params.change_script_pubkey_len +
        4U;

    if (signed_tx_len == signed_tx_expected_len)
    {
        signed_tx_len_match = 1;
    }

    debug_stage = 3120;

    if (signed_tx_len_match != 1)
    {
        wallet_fail(3125);
    }

    if (signed_tx_raw[41] == (uint8_t)signed_tx_script_sig_len &&
        signed_tx_raw[42] == (uint8_t)tx_signature_der_sighash_len)
    {
        signed_tx_script_sig_ok = 1;
    }

    debug_stage = 3130;

    if (signed_tx_script_sig_ok != 1)
    {
        wallet_fail(3135);
    }

    if (signed_tx_raw[0] == 0x01 &&
        signed_tx_raw[1] == 0x00 &&
        signed_tx_raw[2] == 0x00 &&
        signed_tx_raw[3] == 0x00 &&
        signed_tx_raw[4] == 0x01 &&
        signed_tx_raw[5] == regtest_prev_txid_le[0] &&
        signed_tx_raw[6] == regtest_prev_txid_le[1] &&
        signed_tx_raw[7] == regtest_prev_txid_le[2] &&
        signed_tx_raw[8] == regtest_prev_txid_le[3] &&
        signed_tx_raw[37] == (uint8_t)(tx_params.prev_vout & 0xFFU) &&
        signed_tx_raw[38] == (uint8_t)((tx_params.prev_vout >> 8) & 0xFFU) &&
        signed_tx_raw[39] == (uint8_t)((tx_params.prev_vout >> 16) & 0xFFU) &&
        signed_tx_raw[40] == (uint8_t)((tx_params.prev_vout >> 24) & 0xFFU))
    {
        signed_tx_prefix_ok = 1;
    }

    debug_stage = 3140;

    if (signed_tx_prefix_ok != 1)
    {
        wallet_fail(3145);
    }

    if (signed_tx_len > 4U &&
        signed_tx_raw[signed_tx_len - 4U] == 0x00 &&
        signed_tx_raw[signed_tx_len - 3U] == 0x00 &&
        signed_tx_raw[signed_tx_len - 2U] == 0x00 &&
        signed_tx_raw[signed_tx_len - 1U] == 0x00)
    {
        signed_tx_ok = 1;
    }

    debug_stage = 3150;

    if (signed_tx_ok != 1)
    {
        wallet_fail(3155);
    }

    debug_stage = 3180;

    /* 9. Export signed raw transaction as hex */
    debug_stage = 3200;

    memset(signed_tx_hex, 0, sizeof(signed_tx_hex));

    signed_tx_hex_ok = 0;
    signed_tx_hex_len = 0;
    signed_tx_hex_expected_len = signed_tx_len * 2U;

    if (signed_tx_ok != 1)
    {
        wallet_fail(3205);
    }

    if (signed_tx_len < 220U || signed_tx_len > 230U)
    {
        wallet_fail(3210);
    }

    if ((signed_tx_hex_expected_len + 1U) > sizeof(signed_tx_hex))
    {
        wallet_fail(3215);
    }

    if (!wallet_bytes_to_hex(
            (const uint8_t *)signed_tx_raw,
            signed_tx_len,
            signed_tx_hex,
            sizeof(signed_tx_hex)))
    {
        wallet_fail(3220);
    }

    signed_tx_hex_len = signed_tx_len * 2U;

    if (signed_tx_hex[0] != '0' ||
        signed_tx_hex[1] != '1' ||
        signed_tx_hex[2] != '0' ||
        signed_tx_hex[3] != '0' ||
        signed_tx_hex[4] != '0' ||
        signed_tx_hex[5] != '0' ||
        signed_tx_hex[6] != '0' ||
        signed_tx_hex[7] != '0')
    {
        wallet_fail(3230);
    }

    if (signed_tx_hex[8] != '0' ||
        signed_tx_hex[9] != '1')
    {
        wallet_fail(3235);
    }

    signed_tx_hex_ok = 1;

    debug_stage = 3250;

    /* 10. Split hex into debugger-copyable chunks */
    debug_stage = 3260;

    signed_tx_hex_parts_ok = 0;

    memset(signed_tx_hex_part0, 0, sizeof(signed_tx_hex_part0));
    memset(signed_tx_hex_part1, 0, sizeof(signed_tx_hex_part1));
    memset(signed_tx_hex_part2, 0, sizeof(signed_tx_hex_part2));
    memset(signed_tx_hex_part3, 0, sizeof(signed_tx_hex_part3));
    memset(signed_tx_hex_part4, 0, sizeof(signed_tx_hex_part4));

    uint32_t pos = 0;
    uint32_t remaining = signed_tx_hex_len;
    uint32_t take = 0;

    take = (remaining > 100U) ? 100U : remaining;
    memcpy(signed_tx_hex_part0, &signed_tx_hex[pos], take);
    signed_tx_hex_part0[take] = '\0';
    pos += take;
    remaining -= take;

    take = (remaining > 100U) ? 100U : remaining;
    memcpy(signed_tx_hex_part1, &signed_tx_hex[pos], take);
    signed_tx_hex_part1[take] = '\0';
    pos += take;
    remaining -= take;

    take = (remaining > 100U) ? 100U : remaining;
    memcpy(signed_tx_hex_part2, &signed_tx_hex[pos], take);
    signed_tx_hex_part2[take] = '\0';
    pos += take;
    remaining -= take;

    take = (remaining > 100U) ? 100U : remaining;
    memcpy(signed_tx_hex_part3, &signed_tx_hex[pos], take);
    signed_tx_hex_part3[take] = '\0';
    pos += take;
    remaining -= take;

    take = (remaining > 100U) ? 100U : remaining;
    memcpy(signed_tx_hex_part4, &signed_tx_hex[pos], take);
    signed_tx_hex_part4[take] = '\0';
    pos += take;
    remaining -= take;

    if (remaining == 0U && pos == signed_tx_hex_len)
    {
        signed_tx_hex_parts_ok = 1;
    }

    if (signed_tx_hex_parts_ok != 1U)
    {
        wallet_fail(3265);
    }

    debug_stage = 3280;

    while (1)
    {
        __NOP();
    }
}


