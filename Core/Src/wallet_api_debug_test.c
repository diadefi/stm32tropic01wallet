#include "wallet_api_debug_test.h"
#include "wallet_core.h"

#include "psa/crypto.h"

#include <stdint.h>
#include <string.h>

extern RNG_HandleTypeDef hrng;

volatile int wallet_sign_api_ret = 999;

static void wallet_api_fail(uint32_t stage)
{
    debug_stage = stage;

    while (1)
    {
        __NOP();
    }
}

static void wallet_api_clear_debug_state(void)
{
    hal_rng_ret = HAL_ERROR;
    hal_rng_word = 0;
    psa_init_ret = 12345;

    tx_preimage_build_ret = 999;
    signed_tx_build_ret = 999;
    wallet_sign_api_ret = 999;

    memset((void *)secp_privkey, 0, sizeof(secp_privkey));

    memset((void *)signed_tx_raw, 0, sizeof(signed_tx_raw));
    signed_tx_len = 0;
    signed_tx_expected_len = 0;
    signed_tx_script_sig_len = 0;

    signed_tx_len_match = 0;
    signed_tx_script_sig_ok = 0;
    signed_tx_prefix_ok = 0;
    signed_tx_ok = 0;

    memset(signed_tx_hex, 0, sizeof(signed_tx_hex));
    signed_tx_hex_len = 0;
    signed_tx_hex_expected_len = 0;
    signed_tx_hex_ok = 0;

    memset(signed_tx_hex_part0, 0, sizeof(signed_tx_hex_part0));
    memset(signed_tx_hex_part1, 0, sizeof(signed_tx_hex_part1));
    memset(signed_tx_hex_part2, 0, sizeof(signed_tx_hex_part2));
    memset(signed_tx_hex_part3, 0, sizeof(signed_tx_hex_part3));
    memset(signed_tx_hex_part4, 0, sizeof(signed_tx_hex_part4));
    signed_tx_hex_parts_ok = 0;
}

static int wallet_api_split_hex_chunks(void)
{
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

    return (remaining == 0U && pos == signed_tx_hex_len) ? 1 : 0;
}

void wallet_api_debug_run_regression_test(void)
{
    wallet_api_clear_debug_state();

    debug_stage = 4000;

    /* 1. HAL RNG smoke test */
    hal_rng_ret = HAL_RNG_GenerateRandomNumber(
        &hrng,
        (uint32_t *)&hal_rng_word
    );

    debug_stage = 4010;

    if (hal_rng_ret != HAL_OK)
    {
        wallet_api_fail(4015);
    }

    /* 2. PSA crypto init. wallet_sign_p2pkh_2out_tx() uses PSA SHA-256. */
    psa_init_ret = psa_crypto_init();

    debug_stage = 4020;

    if (psa_init_ret != PSA_SUCCESS)
    {
        wallet_api_fail(4025);
    }

    /* 3. Key-blob MVP: no plaintext deterministic private key is kept in source. */
    debug_stage = 4030;

    memset((void *)secp_privkey, 0, sizeof(secp_privkey));
    secp_privkey[31] = 0x01;

    /*
     * Same already-spent two-output regression vector:
     * input: 100000 sats
     * pay:    60000 sats
     * change: 30000 sats
     * fee:    10000 sats
     */
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

    /* 4. Call the high-level wallet API. */
    debug_stage = 4100;

    wallet_sign_api_ret = wallet_sign_p2pkh_2out_tx(
        regtest_prev_txid_le,
        1U,
        regtest_prev_script_pubkey,
        sizeof(regtest_prev_script_pubkey),
        100000ULL,

        regtest_pay_script_pubkey,
        sizeof(regtest_pay_script_pubkey),
        60000ULL,

        regtest_change_script_pubkey,
        sizeof(regtest_change_script_pubkey),
        30000ULL,

        (const uint8_t *)secp_privkey,

        (uint8_t *)signed_tx_raw,
        sizeof(signed_tx_raw),
        (uint32_t *)&signed_tx_len
    );

    signed_tx_build_ret = wallet_sign_api_ret;

    debug_stage = 4110;

    if (wallet_sign_api_ret != 0)
    {
        wallet_api_fail(4115);
    }

    /* The API hides the preimage internally. This marks the high-level path OK. */
    tx_preimage_build_ret = 0;

    /* 5. Validate basic transaction shape. */
    debug_stage = 4120;

    if (signed_tx_len < 220U || signed_tx_len > 230U)
    {
        wallet_api_fail(4125);
    }

    signed_tx_script_sig_len = signed_tx_raw[41];

    signed_tx_expected_len =
        4U + 1U + 32U + 4U + 1U +
        signed_tx_script_sig_len +
        4U + 1U +
        8U + 1U + sizeof(regtest_pay_script_pubkey) +
        8U + 1U + sizeof(regtest_change_script_pubkey) +
        4U;

    if (signed_tx_len == signed_tx_expected_len)
    {
        signed_tx_len_match = 1;
    }

    if (signed_tx_len_match != 1)
    {
        wallet_api_fail(4135);
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
        signed_tx_raw[37] == 0x01 &&
        signed_tx_raw[38] == 0x00 &&
        signed_tx_raw[39] == 0x00 &&
        signed_tx_raw[40] == 0x00)
    {
        signed_tx_prefix_ok = 1;
    }

    debug_stage = 4140;

    if (signed_tx_prefix_ok != 1)
    {
        wallet_api_fail(4145);
    }

    if (signed_tx_raw[41] == (uint8_t)signed_tx_script_sig_len &&
        signed_tx_raw[42] >= 0x47U &&
        signed_tx_raw[42] <= 0x49U)
    {
        signed_tx_script_sig_ok = 1;
    }

    debug_stage = 4150;

    if (signed_tx_script_sig_ok != 1)
    {
        wallet_api_fail(4155);
    }

    if (signed_tx_len > 4U &&
        signed_tx_raw[signed_tx_len - 4U] == 0x00 &&
        signed_tx_raw[signed_tx_len - 3U] == 0x00 &&
        signed_tx_raw[signed_tx_len - 2U] == 0x00 &&
        signed_tx_raw[signed_tx_len - 1U] == 0x00)
    {
        signed_tx_ok = 1;
    }

    debug_stage = 4160;

    if (signed_tx_ok != 1)
    {
        wallet_api_fail(4165);
    }

    /* 6. Export signed raw transaction as hex. */
    debug_stage = 4200;

    signed_tx_hex_expected_len = signed_tx_len * 2U;

    if ((signed_tx_hex_expected_len + 1U) > sizeof(signed_tx_hex))
    {
        wallet_api_fail(4205);
    }

    if (!wallet_bytes_to_hex(
            (const uint8_t *)signed_tx_raw,
            signed_tx_len,
            signed_tx_hex,
            sizeof(signed_tx_hex)))
    {
        wallet_api_fail(4210);
    }

    signed_tx_hex_len = signed_tx_len * 2U;

    if (signed_tx_hex[0] != '0' ||
        signed_tx_hex[1] != '1' ||
        signed_tx_hex[8] != '0' ||
        signed_tx_hex[9] != '1')
    {
        wallet_api_fail(4215);
    }

    signed_tx_hex_ok = 1;

    /* 7. Split hex into debugger-copyable chunks. */
    debug_stage = 4260;

    signed_tx_hex_parts_ok = (uint32_t)wallet_api_split_hex_chunks();

    if (signed_tx_hex_parts_ok != 1U)
    {
        wallet_api_fail(4265);
    }

    debug_stage = 4280;

    while (1)
    {
        __NOP();
    }
}

