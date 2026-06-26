#ifndef WALLET_POLICY_H
#define WALLET_POLICY_H

#include <stdint.h>

#define WALLET_POLICY_OK                    0
#define WALLET_POLICY_ERR_NULL             -30
#define WALLET_POLICY_ERR_INPUT_ZERO       -31
#define WALLET_POLICY_ERR_PAY_ZERO         -32
#define WALLET_POLICY_ERR_CHANGE_ZERO      -33
#define WALLET_POLICY_ERR_OUTPUT_SUM       -34
#define WALLET_POLICY_ERR_FEE_TOO_HIGH     -35
#define WALLET_POLICY_ERR_SCRIPT_NULL      -36
#define WALLET_POLICY_ERR_SCRIPT_TYPE      -37
#define WALLET_POLICY_ERR_PAY_NOT_ALLOWED  -38
#define WALLET_POLICY_ERR_CHANGE_NOT_OWN   -39
#define WALLET_POLICY_ERR_INPUT_NOT_OWN    -40
#define WALLET_POLICY_ERR_PAY_TOO_HIGH     -41
#define WALLET_POLICY_ERR_NETWORK_NOT_REGTEST -42
#define WALLET_POLICY_ERR_SIGN_WITHOUT_APPROVED_CHECK -43
#define WALLET_POLICY_ERR_SIGN_MISMATCHES_APPROVED_CHECK -44
#define WALLET_POLICY_ERR_SIGN_WITHOUT_CONFIRMED_CHECK -46
#define WALLET_POLICY_ERR_CONFIRM_WITHOUT_APPROVED_CHECK -47
#define WALLET_POLICY_ERR_APPROVAL_EXPIRED -48
#define WALLET_POLICY_ERR_CONFIRM_CODE_REQUIRED -49
#define WALLET_POLICY_ERR_CONFIRM_CODE_MISMATCH -50
#define WALLET_POLICY_ERR_FORMAT_INVALID -51
#define WALLET_POLICY_ERR_DUST_OUTPUT -52
#define WALLET_POLICY_ERR_INPUT_COUNT_UNSUPPORTED -53
#define WALLET_POLICY_ERR_CHANGE_DERIVATION_INVALID -54
#define WALLET_POLICY_ERR_LEGACY_SIGN_DISABLED -60

#define WALLET_POLICY_MAX_FEE_SATS         20000ULL
#define WALLET_POLICY_P2PKH_SCRIPT_LEN     25U
#define WALLET_POLICY_MAX_PAY_SATS         70000ULL
#define WALLET_POLICY_MAX_INPUTS           2U
#define WALLET_POLICY_DUST_LIMIT_SATS      546ULL
#define WALLET_POLICY_ESTIMATED_1IN_2OUT_VBYTES 192ULL
#define WALLET_POLICY_ESTIMATED_2IN_2OUT_VBYTES 340ULL
#define WALLET_POLICY_MAX_FEE_RATE_SATS_PER_KVB 100000ULL


typedef struct
{
    uint64_t input_sats;
    uint64_t pay_sats;
    uint64_t change_sats;
    uint64_t fee_sats;
    uint32_t input_count;
} wallet_policy_amounts_t;

int wallet_policy_check_amounts(const wallet_policy_amounts_t *amounts);

int wallet_policy_check_p2pkh_script(const uint8_t *script,
                                     uint32_t script_len);

int wallet_policy_check_allowed_pay_script(const uint8_t *script,
                                           uint32_t script_len);

int wallet_policy_check_own_change_script(const uint8_t *script,
                                          uint32_t script_len);

int wallet_policy_check_own_input_script(const uint8_t *script,
                                         uint32_t script_len);

#endif /* WALLET_POLICY_H */
