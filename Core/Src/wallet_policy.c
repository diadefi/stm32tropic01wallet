#include "wallet_policy.h"

/*
 * Approved payment recipient:
 *
 * PAY_SCRIPT=76a914f2124d94cabdb95d49479627cbbe5d7be609f73888ac
 */
static const uint8_t wallet_policy_allowed_pay_script_0[WALLET_POLICY_P2PKH_SCRIPT_LEN] =
{
    0x76U, 0xA9U, 0x14U,
    0xF2U, 0x12U, 0x4DU, 0x94U, 0xCAU,
    0xBDU, 0xB9U, 0x5DU, 0x49U, 0x47U,
    0x96U, 0x27U, 0xCBU, 0xBEU, 0x5DU,
    0x7BU, 0xE6U, 0x09U, 0xF7U, 0x38U,
    0x88U, 0xACU
};

/*
 * Own wallet/change script:
 *
 * PREV_SCRIPT / CHANGE_SCRIPT =
 * 76a914751e76e8199196d454941c45d1b3a323f1433bd688ac
 */
static const uint8_t wallet_policy_own_wallet_script_0[WALLET_POLICY_P2PKH_SCRIPT_LEN] =
{
    0x76U, 0xA9U, 0x14U,
    0x75U, 0x1EU, 0x76U, 0xE8U, 0x19U,
    0x91U, 0x96U, 0xD4U, 0x54U, 0x94U,
    0x1CU, 0x45U, 0xD1U, 0xB3U, 0xA3U,
    0x23U, 0xF1U, 0x43U, 0x3BU, 0xD6U,
    0x88U, 0xACU
};

static int wallet_policy_script_equals(const uint8_t *script,
                                       uint32_t script_len,
                                       const uint8_t *allowed_script)
{
    int policy_ret;

    if (allowed_script == 0)
    {
        return WALLET_POLICY_ERR_NULL;
    }

    policy_ret = wallet_policy_check_p2pkh_script(script, script_len);

    if (policy_ret != WALLET_POLICY_OK)
    {
        return policy_ret;
    }

    for (uint32_t i = 0; i < WALLET_POLICY_P2PKH_SCRIPT_LEN; i++)
    {
        if (script[i] != allowed_script[i])
        {
            return 0;
        }
    }

    return 1;
}

int wallet_policy_check_amounts(const wallet_policy_amounts_t *amounts)
{
    uint64_t output_sum = 0ULL;
    uint64_t fee = 0ULL;
    uint64_t estimated_vbytes = WALLET_POLICY_ESTIMATED_1IN_2OUT_VBYTES;

    if (amounts == 0)
    {
        return WALLET_POLICY_ERR_NULL;
    }

    if (amounts->input_sats == 0ULL)
    {
        return WALLET_POLICY_ERR_INPUT_ZERO;
    }

    if (amounts->input_count == 0U ||
        amounts->input_count > WALLET_POLICY_MAX_INPUTS)
    {
        return WALLET_POLICY_ERR_INPUT_COUNT_UNSUPPORTED;
    }

    if (amounts->pay_sats == 0ULL)
    {
        return WALLET_POLICY_ERR_PAY_ZERO;
    }

    if (amounts->pay_sats > WALLET_POLICY_MAX_PAY_SATS)
    {
        return WALLET_POLICY_ERR_PAY_TOO_HIGH;
    }

    if (amounts->pay_sats < WALLET_POLICY_DUST_LIMIT_SATS)
    {
        return WALLET_POLICY_ERR_DUST_OUTPUT;
    }

    if (amounts->change_sats == 0ULL)
    {
        return WALLET_POLICY_ERR_CHANGE_ZERO;
    }

    if (amounts->change_sats < WALLET_POLICY_DUST_LIMIT_SATS)
    {
        return WALLET_POLICY_ERR_DUST_OUTPUT;
    }

    if (amounts->pay_sats > (UINT64_MAX - amounts->change_sats))
    {
        return WALLET_POLICY_ERR_OUTPUT_SUM;
    }

    output_sum = amounts->pay_sats + amounts->change_sats;

    if (output_sum > amounts->input_sats)
    {
        return WALLET_POLICY_ERR_OUTPUT_SUM;
    }

    fee = amounts->input_sats - output_sum;

    if (fee > WALLET_POLICY_MAX_FEE_SATS)
    {
        return WALLET_POLICY_ERR_FEE_TOO_HIGH;
    }

    if (amounts->input_count == 2U)
    {
        estimated_vbytes = WALLET_POLICY_ESTIMATED_2IN_2OUT_VBYTES;
    }

    if ((fee * 1000ULL) >
        (WALLET_POLICY_MAX_FEE_RATE_SATS_PER_KVB *
         estimated_vbytes))
    {
        return WALLET_POLICY_ERR_FEE_TOO_HIGH;
    }

    return WALLET_POLICY_OK;
}

int wallet_policy_check_p2pkh_script(const uint8_t *script,
                                     uint32_t script_len)
{
    if (script == 0)
    {
        return WALLET_POLICY_ERR_SCRIPT_NULL;
    }

    if (script_len != WALLET_POLICY_P2PKH_SCRIPT_LEN)
    {
        return WALLET_POLICY_ERR_SCRIPT_TYPE;
    }

    /*
     * Standard P2PKH scriptPubKey:
     * 76 a9 14 <20-byte-hash160> 88 ac
     */
    if (script[0] != 0x76U)
    {
        return WALLET_POLICY_ERR_SCRIPT_TYPE;
    }

    if (script[1] != 0xA9U)
    {
        return WALLET_POLICY_ERR_SCRIPT_TYPE;
    }

    if (script[2] != 0x14U)
    {
        return WALLET_POLICY_ERR_SCRIPT_TYPE;
    }

    if (script[23] != 0x88U)
    {
        return WALLET_POLICY_ERR_SCRIPT_TYPE;
    }

    if (script[24] != 0xACU)
    {
        return WALLET_POLICY_ERR_SCRIPT_TYPE;
    }

    return WALLET_POLICY_OK;
}

int wallet_policy_check_allowed_pay_script(const uint8_t *script,
                                           uint32_t script_len)
{
    int match_ret;

    match_ret = wallet_policy_script_equals(
        script,
        script_len,
        wallet_policy_allowed_pay_script_0
    );

    if (match_ret == WALLET_POLICY_ERR_SCRIPT_NULL ||
        match_ret == WALLET_POLICY_ERR_SCRIPT_TYPE ||
        match_ret == WALLET_POLICY_ERR_NULL)
    {
        return match_ret;
    }

    if (match_ret != 1)
    {
        return WALLET_POLICY_ERR_PAY_NOT_ALLOWED;
    }

    return WALLET_POLICY_OK;
}

int wallet_policy_check_own_change_script(const uint8_t *script,
                                          uint32_t script_len)
{
    int match_ret;

    match_ret = wallet_policy_script_equals(
        script,
        script_len,
        wallet_policy_own_wallet_script_0
    );

    if (match_ret == WALLET_POLICY_ERR_SCRIPT_NULL ||
        match_ret == WALLET_POLICY_ERR_SCRIPT_TYPE ||
        match_ret == WALLET_POLICY_ERR_NULL)
    {
        return match_ret;
    }

    if (match_ret != 1)
    {
        return WALLET_POLICY_ERR_CHANGE_NOT_OWN;
    }

    return WALLET_POLICY_OK;
}

int wallet_policy_check_own_input_script(const uint8_t *script,
                                         uint32_t script_len)
{
    int match_ret;

    match_ret = wallet_policy_script_equals(
        script,
        script_len,
        wallet_policy_own_wallet_script_0
    );

    if (match_ret == WALLET_POLICY_ERR_SCRIPT_NULL ||
        match_ret == WALLET_POLICY_ERR_SCRIPT_TYPE ||
        match_ret == WALLET_POLICY_ERR_NULL)
    {
        return match_ret;
    }

    if (match_ret != 1)
    {
        return WALLET_POLICY_ERR_INPUT_NOT_OWN;
    }

    return WALLET_POLICY_OK;
}
