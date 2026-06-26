#include "wallet_command_debug_test.h"
#include "wallet_command.h"
#include "wallet_policy.h"

#include "psa/crypto.h"

#include <stdint.h>
#include <string.h>

extern RNG_HandleTypeDef hrng;

volatile int wallet_command_ret = 999;

static void wallet_command_fail(uint32_t stage)
{
    debug_stage = stage;

    while (1)
    {
        __NOP();
    }
}

static void wallet_command_clear_debug_state(void)
{
    hal_rng_ret = HAL_ERROR;
    hal_rng_word = 0;
    psa_init_ret = 12345;

    tx_preimage_build_ret = 999;
    signed_tx_build_ret = 999;
    wallet_command_ret = 999;

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

static int wallet_command_split_hex_chunks(void)
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

void wallet_command_debug_run_regression_test(void)
{
    static const char command_text[] =
        "TXID_LE=c2bd530ed9d7e40ba47027e8ffee41aa5b62c0ba36e5c20003ca63309dad31c8\n"
        "VOUT=1\n"
        "INPUT_SATS=100000\n"
        "PREV_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac\n"
        "PAY_SCRIPT=76a914f2124d94cabdb95d49479627cbbe5d7be609f73888ac\n"
        "PAY_SATS=60000\n"
        "CHANGE_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac\n"
        "CHANGE_SATS=30000\n"
        "PRIVKEY=HOST_KEY_INJECTION_DISABLED_PLACEHOLDER\n"
        "SIGN\n";

    wallet_command_clear_debug_state();

    debug_stage = 5000;

    hal_rng_ret = HAL_RNG_GenerateRandomNumber(
        &hrng,
        (uint32_t *)&hal_rng_word
    );

    debug_stage = 5010;

    if (hal_rng_ret != HAL_OK)
    {
        wallet_command_fail(5015);
    }

    psa_init_ret = psa_crypto_init();

    debug_stage = 5020;

    if (psa_init_ret != PSA_SUCCESS)
    {
        wallet_command_fail(5025);
    }

    debug_stage = 5100;

    wallet_command_ret = wallet_command_sign_text(
        command_text,
        (uint8_t *)signed_tx_raw,
        sizeof(signed_tx_raw),
        (uint32_t *)&signed_tx_len,
        signed_tx_hex,
        sizeof(signed_tx_hex)
    );

    signed_tx_build_ret = wallet_command_ret;
    tx_preimage_build_ret = 0;

    debug_stage = 5110;

    if (wallet_command_ret != WALLET_POLICY_ERR_LEGACY_SIGN_DISABLED)
    {
        wallet_command_fail(5115);
    }

    return;

    if (signed_tx_len < 220U || signed_tx_len > 230U)
    {
        wallet_command_fail(5125);
    }

    signed_tx_script_sig_len = signed_tx_raw[41];

    signed_tx_expected_len =
        4U + 1U + 32U + 4U + 1U +
        signed_tx_script_sig_len +
        4U + 1U +
        8U + 1U + 25U +
        8U + 1U + 25U +
        4U;

    if (signed_tx_len == signed_tx_expected_len)
    {
        signed_tx_len_match = 1;
    }

    debug_stage = 5130;

    if (signed_tx_len_match != 1)
    {
        wallet_command_fail(5135);
    }

    if (signed_tx_raw[0] == 0x01 &&
        signed_tx_raw[1] == 0x00 &&
        signed_tx_raw[2] == 0x00 &&
        signed_tx_raw[3] == 0x00 &&
        signed_tx_raw[4] == 0x01 &&
        signed_tx_raw[5] == 0xC2 &&
        signed_tx_raw[6] == 0xBD &&
        signed_tx_raw[7] == 0x53 &&
        signed_tx_raw[8] == 0x0E &&
        signed_tx_raw[37] == 0x01 &&
        signed_tx_raw[38] == 0x00 &&
        signed_tx_raw[39] == 0x00 &&
        signed_tx_raw[40] == 0x00)
    {
        signed_tx_prefix_ok = 1;
    }

    debug_stage = 5140;

    if (signed_tx_prefix_ok != 1)
    {
        wallet_command_fail(5145);
    }

    if (signed_tx_len > 4U &&
        signed_tx_raw[signed_tx_len - 4U] == 0x00 &&
        signed_tx_raw[signed_tx_len - 3U] == 0x00 &&
        signed_tx_raw[signed_tx_len - 2U] == 0x00 &&
        signed_tx_raw[signed_tx_len - 1U] == 0x00)
    {
        signed_tx_ok = 1;
    }

    debug_stage = 5160;

    if (signed_tx_ok != 1)
    {
        wallet_command_fail(5165);
    }

    signed_tx_hex_len = signed_tx_len * 2U;
    signed_tx_hex_expected_len = signed_tx_hex_len;

    if (signed_tx_hex[0] == '0' &&
        signed_tx_hex[1] == '1' &&
        signed_tx_hex[8] == '0' &&
        signed_tx_hex[9] == '1')
    {
        signed_tx_hex_ok = 1;
    }

    debug_stage = 5200;

    if (signed_tx_hex_ok != 1)
    {
        wallet_command_fail(5205);
    }

    debug_stage = 5260;

    signed_tx_hex_parts_ok = (uint32_t)wallet_command_split_hex_chunks();

    if (signed_tx_hex_parts_ok != 1U)
    {
        wallet_command_fail(5265);
    }

    debug_stage = 5280;

    while (1)
    {
        __NOP();
    }
}

