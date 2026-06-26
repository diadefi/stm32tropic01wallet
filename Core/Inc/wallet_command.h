#ifndef WALLET_COMMAND_H
#define WALLET_COMMAND_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define WALLET_COMMAND_RAW_TX_HEX_MAX 1024U
#define WALLET_COMMAND_MAX_INPUTS 2U
#define WALLET_COMMAND_APPROVAL_TIMEOUT_MS 10000U
#define WALLET_COMMAND_CONFIRM_CODE_LEN 6U
#define WALLET_COMMAND_CONFIRM_CODE_SIZE (WALLET_COMMAND_CONFIRM_CODE_LEN + 1U)

/*
 * New clean API:
 * command_text contains transaction fields only.
 * private_key is supplied by wallet_key_provider, not by the host command.
 */




typedef struct
{
    uint32_t input_count;
    char network[24];

    char txid_le_hex[65];
    uint32_t vout;
    char input1_txid_le_hex[65];
    uint32_t input1_vout;

    char prev_script_hex[505];
    char input1_prev_script_hex[505];
    char pay_script_hex[505];
    char change_script_hex[505];

    uint64_t input_sats;
    uint64_t input1_sats;
    uint64_t total_input_sats;
    uint64_t pay_sats;
    uint64_t change_sats;
    uint64_t fee_sats;

    char check_id_hex[65];

    int policy_result;
} wallet_command_summary_t;

int wallet_command_check_summary_text(
    const char *command_text,
    wallet_command_summary_t *out_summary);

void wallet_command_record_approved_check(const wallet_command_summary_t *summary);
void wallet_command_clear_approved_check(void);
int wallet_command_has_approved_check(void);
int wallet_command_has_confirmed_approved_check(void);
int wallet_command_peek_approved_check(void);
int wallet_command_peek_confirmed_approved_check(void);
uint32_t wallet_command_approval_timeout_ms(void);
uint32_t wallet_command_approved_check_age_ms(void);
int wallet_command_confirm_approved_check(void);
int wallet_command_get_confirm_code(char *out_code, uint32_t out_code_size);
int wallet_command_confirm_approved_check_code(const char *provided_code);
int wallet_command_sign_matches_approved_check_text(const char *command_text);

int wallet_command_check_policy_text(const char *command_text);

int wallet_command_sign_text_with_private_key(
    const char *command_text,
    const uint8_t *private_key,
    uint8_t *out_raw_tx,
    uint32_t out_raw_tx_size,
    uint32_t *out_raw_tx_len,
    char *out_raw_tx_hex,
    uint32_t out_raw_tx_hex_size);

/*
 * Legacy/debug API:
 * Permanently disabled for C4.0. It must not parse or use host PRIVKEY.
 * Do not use this from wallet_uart.c anymore.
 */
int wallet_command_sign_text(
    const char *command_text,
    uint8_t *out_raw_tx,
    uint32_t out_raw_tx_size,
    uint32_t *out_raw_tx_len,
    char *out_raw_tx_hex,
    uint32_t out_raw_tx_hex_size);

#ifdef __cplusplus
}
#endif

#endif /* WALLET_COMMAND_H */

