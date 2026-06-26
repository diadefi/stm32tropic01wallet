#include "wallet_command.h"
#include "wallet_build_config.h"
#include "wallet_core.h"
#include "wallet_policy.h"
#include "sha2.h"
#include "stm32u5xx_hal.h"

#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <stdio.h>


#define WALLET_CHECK_ID_VERSION_LABEL         "C5.1_CHECK_ID_MULTI_INPUT_V1"

static int wallet_cmd_hex_nibble(char c, uint8_t *out);
static int wallet_cmd_find_value(const char *text,
                                 const char *key,
                                 const char **value_start,
                                 uint32_t *value_len);
static int wallet_cmd_parse_value_equals(const char *text,
                                         const char *key,
                                         const char *expected);
static int wallet_command_network_allowed(const char *command_text,
                                          char *out_network,
                                          uint32_t out_network_size);

#define WALLET_COMMAND_C5_0_FORMAT "C5.0_PSBT_LIKE_TEXT_V1"
#define WALLET_COMMAND_C5_3_CHANGE_DERIVATION "mvp-static-change/0"
#define WALLET_COMMAND_C9_8_TESTNET_CHANGE_DERIVATION "m/84h/1h/0h/1/0"

static const uint8_t wallet_command_c9_8_testnet_change_script[] = {
    0x00U, 0x14U,
    0x75U, 0x1eU, 0x76U, 0xe8U, 0x19U, 0x91U, 0x96U, 0xd4U,
    0x54U, 0x94U, 0x1cU, 0x45U, 0xd1U, 0xb3U, 0xa3U, 0x23U,
    0xf1U, 0x43U, 0x3bU, 0xd6U
};

static const char *wallet_cmd_c5_0_alias_key(const char *key)
{
    if (key == NULL)
    {
        return NULL;
    }

    if (strcmp(key, "NETWORK") == 0) return "PSBT_GLOBAL_NETWORK";
    if (strcmp(key, "TXID_LE") == 0) return "PSBT_INPUT0_TXID_LE";
    if (strcmp(key, "VOUT") == 0) return "PSBT_INPUT0_VOUT";
    if (strcmp(key, "INPUT_SATS") == 0) return "PSBT_INPUT0_SATS";
    if (strcmp(key, "PREV_SCRIPT") == 0) return "PSBT_INPUT0_PREV_SCRIPT";
    if (strcmp(key, "PAY_SCRIPT") == 0) return "PSBT_OUTPUT0_SCRIPT";
    if (strcmp(key, "PAY_SATS") == 0) return "PSBT_OUTPUT0_SATS";
    if (strcmp(key, "CHANGE_SCRIPT") == 0) return "PSBT_OUTPUT1_SCRIPT";
    if (strcmp(key, "CHANGE_SATS") == 0) return "PSBT_OUTPUT1_SATS";

    return NULL;
}

static int wallet_cmd_contains_exact_key(const char *text, const char *key)
{
    const char *p;
    uint32_t key_len;

    if (text == NULL || key == NULL)
    {
        return 0;
    }

    key_len = (uint32_t)strlen(key);
    p = text;

    while ((p = strstr(p, key)) != NULL)
    {
        if ((p == text || p[-1] == '\n' || p[-1] == '\r') &&
            p[key_len] == '=')
        {
            return 1;
        }

        p++;
    }

    return 0;
}

static int wallet_cmd_is_psbt_like_text(const char *text)
{
    if (text == NULL)
    {
        return 0;
    }

    return (strstr(text, "WALLET_CMD_FORMAT=") != NULL ||
            strstr(text, "PSBT_GLOBAL_NETWORK=") != NULL ||
            strstr(text, "PSBT_INPUT_COUNT=") != NULL ||
            strstr(text, "PSBT_OUTPUT_COUNT=") != NULL ||
            strstr(text, "PSBT_INPUT0_") != NULL ||
            strstr(text, "PSBT_INPUT1_") != NULL ||
            strstr(text, "PSBT_OUTPUT0_") != NULL ||
            strstr(text, "PSBT_OUTPUT1_") != NULL);
}

static int wallet_command_is_testnet_text(const char *command_text)
{
    return wallet_cmd_parse_value_equals(command_text, "NETWORK", "TESTNET");
}

static int wallet_command_check_change_script_for_network(
    const char *command_text,
    const uint8_t *change_script_pubkey,
    uint32_t change_script_pubkey_len)
{
    if (wallet_command_is_testnet_text(command_text))
    {
        if (change_script_pubkey == NULL ||
            change_script_pubkey_len != sizeof(wallet_command_c9_8_testnet_change_script) ||
            memcmp(change_script_pubkey,
                   wallet_command_c9_8_testnet_change_script,
                   sizeof(wallet_command_c9_8_testnet_change_script)) != 0)
        {
            return WALLET_POLICY_ERR_CHANGE_NOT_OWN;
        }

        return WALLET_POLICY_OK;
    }

    return wallet_policy_check_own_change_script(
        change_script_pubkey,
        change_script_pubkey_len
    );
}

static int wallet_command_validate_c5_0_format_text(const char *command_text)
{
    if (command_text == NULL)
    {
        return WALLET_POLICY_ERR_NULL;
    }

    if (!wallet_cmd_is_psbt_like_text(command_text))
    {
        return WALLET_POLICY_OK;
    }

    if (!wallet_cmd_parse_value_equals(command_text,
                                       "WALLET_CMD_FORMAT",
                                       WALLET_COMMAND_C5_0_FORMAT))
    {
        return WALLET_POLICY_ERR_FORMAT_INVALID;
    }

    if (!(wallet_cmd_parse_value_equals(command_text, "PSBT_INPUT_COUNT", "1") ||
          wallet_cmd_parse_value_equals(command_text, "PSBT_INPUT_COUNT", "2")) ||
        !wallet_cmd_parse_value_equals(command_text, "PSBT_OUTPUT_COUNT", "2") ||
        !wallet_cmd_parse_value_equals(command_text, "PSBT_OUTPUT0_ROLE", "PAYMENT") ||
        !wallet_cmd_parse_value_equals(command_text, "PSBT_OUTPUT1_ROLE", "CHANGE"))
    {
        return WALLET_POLICY_ERR_FORMAT_INVALID;
    }

    if (wallet_cmd_parse_value_equals(command_text, "PSBT_INPUT_COUNT", "2") &&
        (!wallet_cmd_contains_exact_key(command_text, "PSBT_INPUT1_TXID_LE") ||
         !wallet_cmd_contains_exact_key(command_text, "PSBT_INPUT1_VOUT") ||
         !wallet_cmd_contains_exact_key(command_text, "PSBT_INPUT1_SATS") ||
         !wallet_cmd_contains_exact_key(command_text, "PSBT_INPUT1_PREV_SCRIPT")))
    {
        return WALLET_POLICY_ERR_FORMAT_INVALID;
    }

    if (wallet_command_is_testnet_text(command_text))
    {
        if (!wallet_cmd_parse_value_equals(command_text,
                                           "PSBT_OUTPUT1_DERIVATION",
                                           WALLET_COMMAND_C9_8_TESTNET_CHANGE_DERIVATION))
        {
            return WALLET_POLICY_ERR_CHANGE_DERIVATION_INVALID;
        }
    }
    else if (wallet_cmd_contains_exact_key(command_text, "PSBT_OUTPUT1_DERIVATION") &&
             !wallet_cmd_parse_value_equals(command_text,
                                            "PSBT_OUTPUT1_DERIVATION",
                                            WALLET_COMMAND_C5_3_CHANGE_DERIVATION))
    {
        return WALLET_POLICY_ERR_CHANGE_DERIVATION_INVALID;
    }

    if (wallet_cmd_contains_exact_key(command_text, "NETWORK") ||
        wallet_cmd_contains_exact_key(command_text, "TXID_LE") ||
        wallet_cmd_contains_exact_key(command_text, "VOUT") ||
        wallet_cmd_contains_exact_key(command_text, "INPUT_SATS") ||
        wallet_cmd_contains_exact_key(command_text, "PREV_SCRIPT") ||
        wallet_cmd_contains_exact_key(command_text, "PAY_SCRIPT") ||
        wallet_cmd_contains_exact_key(command_text, "PAY_SATS") ||
        wallet_cmd_contains_exact_key(command_text, "CHANGE_SCRIPT") ||
        wallet_cmd_contains_exact_key(command_text, "CHANGE_SATS"))
    {
        return WALLET_POLICY_ERR_FORMAT_INVALID;
    }

    return WALLET_POLICY_OK;
}

static void wallet_command_secure_zero(void *buf, size_t len)
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

static int wallet_command_hash_update_str(SHA256_CTX *ctx, const char *s)
{
    if (ctx == NULL || s == NULL)
    {
        return 0;
    }

    sha256_Update(ctx, (const uint8_t *)s, strlen(s));
    return 1;
}

static int wallet_command_hash_update_u32(SHA256_CTX *ctx, uint32_t value)
{
    char buf[11];

    if (ctx == NULL)
    {
        return 0;
    }

    snprintf(buf, sizeof(buf), "%lu", (unsigned long)value);
    sha256_Update(ctx, (const uint8_t *)buf, strlen(buf));
    return 1;
}

static int wallet_command_hash_update_u64(SHA256_CTX *ctx, uint64_t value)
{
    char buf[21];
    char rev[20];
    uint32_t pos = 0U;
    uint32_t out = 0U;

    if (ctx == NULL)
    {
        return 0;
    }

    if (value == 0ULL)
    {
        buf[0] = '0';
        buf[1] = '\0';
        sha256_Update(ctx, (const uint8_t *)buf, 1U);
        return 1;
    }

    while (value != 0ULL && pos < sizeof(rev))
    {
        rev[pos++] = (char)('0' + (value % 10ULL));
        value /= 10ULL;
    }

    if (value != 0ULL || pos == 0U)
    {
        return 0;
    }

    while (pos > 0U && out < (sizeof(buf) - 1U))
    {
        buf[out++] = rev[--pos];
    }

    buf[out] = '\0';
    sha256_Update(ctx, (const uint8_t *)buf, out);
    return 1;
}

static int wallet_command_hash_update_field_str(SHA256_CTX *ctx,
                                                const char *name,
                                                const char *value)
{
    return wallet_command_hash_update_str(ctx, name) &&
           wallet_command_hash_update_str(ctx, "=") &&
           wallet_command_hash_update_str(ctx, value) &&
           wallet_command_hash_update_str(ctx, "\n");
}

static int wallet_command_hash_update_field_u32(SHA256_CTX *ctx,
                                                const char *name,
                                                uint32_t value)
{
    return wallet_command_hash_update_str(ctx, name) &&
           wallet_command_hash_update_str(ctx, "=") &&
           wallet_command_hash_update_u32(ctx, value) &&
           wallet_command_hash_update_str(ctx, "\n");
}

static int wallet_command_hash_update_field_u64(SHA256_CTX *ctx,
                                                const char *name,
                                                uint64_t value)
{
    return wallet_command_hash_update_str(ctx, name) &&
           wallet_command_hash_update_str(ctx, "=") &&
           wallet_command_hash_update_u64(ctx, value) &&
           wallet_command_hash_update_str(ctx, "\n");
}

static int wallet_command_compute_check_id(wallet_command_summary_t *summary)
{
    static const char hex[] = "0123456789abcdef";
    SHA256_CTX ctx;
    uint8_t digest[SHA256_DIGEST_LENGTH];
    uint32_t i;

    if (summary == NULL)
    {
        return 0;
    }

    memset(digest, 0, sizeof(digest));
    memset(summary->check_id_hex, 0, sizeof(summary->check_id_hex));

    sha256_Init(&ctx);

    if (!wallet_command_hash_update_str(&ctx, WALLET_CHECK_ID_VERSION_LABEL) ||
        !wallet_command_hash_update_str(&ctx, "\n") ||
        !wallet_command_hash_update_field_str(&ctx, "NETWORK", summary->network) ||
        !wallet_command_hash_update_field_u32(&ctx, "INPUT_COUNT", summary->input_count) ||
        !wallet_command_hash_update_field_str(&ctx, "TXID_LE", summary->txid_le_hex) ||
        !wallet_command_hash_update_field_u32(&ctx, "VOUT", summary->vout) ||
        !wallet_command_hash_update_field_u64(&ctx, "INPUT_SATS", summary->input_sats) ||
        !wallet_command_hash_update_field_str(&ctx, "PREV_SCRIPT", summary->prev_script_hex))
    {
        wallet_command_secure_zero(digest, sizeof(digest));
        return 0;
    }

    if (summary->input_count == 2U &&
        (!wallet_command_hash_update_field_str(&ctx, "INPUT1_TXID_LE", summary->input1_txid_le_hex) ||
         !wallet_command_hash_update_field_u32(&ctx, "INPUT1_VOUT", summary->input1_vout) ||
         !wallet_command_hash_update_field_u64(&ctx, "INPUT1_SATS", summary->input1_sats) ||
         !wallet_command_hash_update_field_str(&ctx, "INPUT1_PREV_SCRIPT", summary->input1_prev_script_hex)))
    {
        wallet_command_secure_zero(digest, sizeof(digest));
        return 0;
    }

    if (!wallet_command_hash_update_field_u64(&ctx, "TOTAL_INPUT_SATS", summary->total_input_sats) ||
        !wallet_command_hash_update_field_str(&ctx, "PAY_SCRIPT", summary->pay_script_hex) ||
        !wallet_command_hash_update_field_u64(&ctx, "PAY_SATS", summary->pay_sats) ||
        !wallet_command_hash_update_field_str(&ctx, "CHANGE_SCRIPT", summary->change_script_hex) ||
        !wallet_command_hash_update_field_u64(&ctx, "CHANGE_SATS", summary->change_sats) ||
        !wallet_command_hash_update_field_u64(&ctx, "FEE_SATS", summary->fee_sats))
    {
        wallet_command_secure_zero(digest, sizeof(digest));
        return 0;
    }

    sha256_Final(&ctx, digest);

    for (i = 0U; i < SHA256_DIGEST_LENGTH; i++)
    {
        summary->check_id_hex[i * 2U] = hex[(digest[i] >> 4U) & 0x0FU];
        summary->check_id_hex[(i * 2U) + 1U] = hex[digest[i] & 0x0FU];
    }
    summary->check_id_hex[SHA256_DIGEST_STRING_LENGTH - 1U] = '\0';

    wallet_command_secure_zero(digest, sizeof(digest));
    return 1;
}

static int wallet_command_confirm_code_from_check_id(const char *check_id_hex,
                                                     char *out_code,
                                                     uint32_t out_code_size)
{
    uint32_t value = 0U;
    uint32_t i;
    uint8_t nibble = 0U;

    if (check_id_hex == NULL || out_code == NULL ||
        out_code_size < WALLET_COMMAND_CONFIRM_CODE_SIZE)
    {
        return 0;
    }

    for (i = 0U; i < 8U; i++)
    {
        if (!wallet_cmd_hex_nibble(check_id_hex[i], &nibble))
        {
            return 0;
        }

        value = (value << 4U) | (uint32_t)nibble;
    }

    value %= 1000000U;

    snprintf(out_code,
             out_code_size,
             "%06lu",
             (unsigned long)value);

    return 1;
}

static wallet_command_summary_t wallet_command_approved_check;
static int wallet_command_approved_check_pending = 0;
static int wallet_command_approved_check_confirmed = 0;
static uint32_t wallet_command_approved_check_recorded_ms = 0U;
static uint32_t wallet_command_approved_check_confirmed_ms = 0U;

static int wallet_command_summary_matches(const wallet_command_summary_t *a,
                                          const wallet_command_summary_t *b)
{
    if (a == NULL || b == NULL)
    {
        return 0;
    }

    if (strcmp(a->network, b->network) != 0) { return 0; }
    if (a->input_count != b->input_count) { return 0; }
    if (strcmp(a->txid_le_hex, b->txid_le_hex) != 0) { return 0; }
    if (a->vout != b->vout) { return 0; }
    if (a->input_sats != b->input_sats) { return 0; }
    if (strcmp(a->prev_script_hex, b->prev_script_hex) != 0) { return 0; }
    if (a->input_count == 2U)
    {
        if (strcmp(a->input1_txid_le_hex, b->input1_txid_le_hex) != 0) { return 0; }
        if (a->input1_vout != b->input1_vout) { return 0; }
        if (a->input1_sats != b->input1_sats) { return 0; }
        if (strcmp(a->input1_prev_script_hex, b->input1_prev_script_hex) != 0) { return 0; }
    }
    if (a->total_input_sats != b->total_input_sats) { return 0; }
    if (strcmp(a->pay_script_hex, b->pay_script_hex) != 0) { return 0; }
    if (a->pay_sats != b->pay_sats) { return 0; }
    if (strcmp(a->change_script_hex, b->change_script_hex) != 0) { return 0; }
    if (a->change_sats != b->change_sats) { return 0; }
    if (a->fee_sats != b->fee_sats) { return 0; }
    if (strcmp(a->check_id_hex, b->check_id_hex) != 0) { return 0; }

    return 1;
}

static int wallet_command_expire_approved_check_if_needed(void)
{
    uint32_t now_ms;
    uint32_t base_ms;

    if (!wallet_command_approved_check_pending)
    {
        return 0;
    }

    now_ms = HAL_GetTick();
    base_ms = wallet_command_approved_check_confirmed ?
              wallet_command_approved_check_confirmed_ms :
              wallet_command_approved_check_recorded_ms;

    if ((now_ms - base_ms) >= WALLET_COMMAND_APPROVAL_TIMEOUT_MS)
    {
        wallet_command_clear_approved_check();
        return 1;
    }

    return 0;
}

void wallet_command_record_approved_check(const wallet_command_summary_t *summary)
{
    if (summary == NULL || summary->policy_result != WALLET_POLICY_OK)
    {
        wallet_command_clear_approved_check();
        return;
    }

    memcpy(&wallet_command_approved_check, summary, sizeof(wallet_command_approved_check));
    wallet_command_approved_check_pending = 1;
    wallet_command_approved_check_confirmed = 0;
    wallet_command_approved_check_recorded_ms = HAL_GetTick();
    wallet_command_approved_check_confirmed_ms = 0U;
}

void wallet_command_clear_approved_check(void)
{
    wallet_command_secure_zero(&wallet_command_approved_check, sizeof(wallet_command_approved_check));
    wallet_command_approved_check_pending = 0;
    wallet_command_approved_check_confirmed = 0;
    wallet_command_approved_check_recorded_ms = 0U;
    wallet_command_approved_check_confirmed_ms = 0U;
}

int wallet_command_has_approved_check(void)
{
    (void)wallet_command_expire_approved_check_if_needed();
    return wallet_command_approved_check_pending;
}

int wallet_command_has_confirmed_approved_check(void)
{
    (void)wallet_command_expire_approved_check_if_needed();
    return wallet_command_approved_check_pending && wallet_command_approved_check_confirmed;
}

int wallet_command_peek_approved_check(void)
{
    return wallet_command_approved_check_pending;
}

int wallet_command_peek_confirmed_approved_check(void)
{
    return wallet_command_approved_check_pending && wallet_command_approved_check_confirmed;
}

uint32_t wallet_command_approval_timeout_ms(void)
{
    return WALLET_COMMAND_APPROVAL_TIMEOUT_MS;
}

uint32_t wallet_command_approved_check_age_ms(void)
{
    uint32_t base_ms;

    if (wallet_command_expire_approved_check_if_needed())
    {
        return 0U;
    }

    if (!wallet_command_approved_check_pending)
    {
        return 0U;
    }

    base_ms = wallet_command_approved_check_confirmed ?
              wallet_command_approved_check_confirmed_ms :
              wallet_command_approved_check_recorded_ms;

    return HAL_GetTick() - base_ms;
}

int wallet_command_confirm_approved_check(void)
{
    if (wallet_command_expire_approved_check_if_needed())
    {
        return WALLET_POLICY_ERR_APPROVAL_EXPIRED;
    }

    if (!wallet_command_approved_check_pending)
    {
        return WALLET_POLICY_ERR_CONFIRM_WITHOUT_APPROVED_CHECK;
    }

    wallet_command_approved_check_confirmed = 1;
    wallet_command_approved_check_confirmed_ms = HAL_GetTick();
    return WALLET_POLICY_OK;
}

int wallet_command_get_confirm_code(char *out_code, uint32_t out_code_size)
{
    if (wallet_command_expire_approved_check_if_needed())
    {
        return WALLET_POLICY_ERR_APPROVAL_EXPIRED;
    }

    if (!wallet_command_approved_check_pending)
    {
        return WALLET_POLICY_ERR_CONFIRM_WITHOUT_APPROVED_CHECK;
    }

    if (!wallet_command_confirm_code_from_check_id(wallet_command_approved_check.check_id_hex,
                                                   out_code,
                                                   out_code_size))
    {
        return WALLET_POLICY_ERR_CONFIRM_CODE_REQUIRED;
    }

    return WALLET_POLICY_OK;
}

int wallet_command_confirm_approved_check_code(const char *provided_code)
{
    char expected_code[WALLET_COMMAND_CONFIRM_CODE_SIZE];
    int ret = WALLET_POLICY_OK;

    if (wallet_command_expire_approved_check_if_needed())
    {
        return WALLET_POLICY_ERR_APPROVAL_EXPIRED;
    }

    if (!wallet_command_approved_check_pending)
    {
        return WALLET_POLICY_ERR_CONFIRM_WITHOUT_APPROVED_CHECK;
    }

    if (provided_code == NULL)
    {
        return WALLET_POLICY_ERR_CONFIRM_CODE_REQUIRED;
    }

    memset(expected_code, 0, sizeof(expected_code));
    ret = wallet_command_get_confirm_code(expected_code, sizeof(expected_code));
    if (ret != WALLET_POLICY_OK)
    {
        wallet_command_secure_zero(expected_code, sizeof(expected_code));
        return ret;
    }

    if (strcmp(provided_code, expected_code) != 0)
    {
        wallet_command_secure_zero(expected_code, sizeof(expected_code));
        wallet_command_clear_approved_check();
        return WALLET_POLICY_ERR_CONFIRM_CODE_MISMATCH;
    }

    wallet_command_secure_zero(expected_code, sizeof(expected_code));
    return wallet_command_confirm_approved_check();
}

int wallet_command_sign_matches_approved_check_text(const char *command_text)
{
    wallet_command_summary_t sign_summary;
    int ret;

    if (wallet_command_expire_approved_check_if_needed())
    {
        return WALLET_POLICY_ERR_APPROVAL_EXPIRED;
    }

    if (!wallet_command_approved_check_pending)
    {
        return WALLET_POLICY_ERR_SIGN_WITHOUT_APPROVED_CHECK;
    }

    if (!wallet_command_approved_check_confirmed)
    {
        return WALLET_POLICY_ERR_SIGN_WITHOUT_CONFIRMED_CHECK;
    }

    memset(&sign_summary, 0, sizeof(sign_summary));
    ret = wallet_command_check_summary_text(command_text, &sign_summary);

    if (ret != WALLET_POLICY_OK)
    {
        wallet_command_secure_zero(&sign_summary, sizeof(sign_summary));
        return ret;
    }

    if (!wallet_command_summary_matches(&wallet_command_approved_check, &sign_summary))
    {
        wallet_command_secure_zero(&sign_summary, sizeof(sign_summary));
        wallet_command_clear_approved_check();
        return WALLET_POLICY_ERR_SIGN_MISMATCHES_APPROVED_CHECK;
    }

    wallet_command_secure_zero(&sign_summary, sizeof(sign_summary));
    return WALLET_POLICY_OK;
}
static int wallet_cmd_hex_nibble(char c, uint8_t *out)
{
    if (out == NULL)
    {
        return 0;
    }

    if (c >= '0' && c <= '9')
    {
        *out = (uint8_t)(c - '0');
        return 1;
    }

    if (c >= 'a' && c <= 'f')
    {
        *out = (uint8_t)(10 + (c - 'a'));
        return 1;
    }

    if (c >= 'A' && c <= 'F')
    {
        *out = (uint8_t)(10 + (c - 'A'));
        return 1;
    }

    return 0;
}

static int wallet_cmd_find_value(const char *text,
                                 const char *key,
                                 const char **value_start,
                                 uint32_t *value_len)
{
    const char *p;
    const char *v;
    const char *e;
    uint32_t key_len;
    const char *search_key;

    if (text == NULL || key == NULL || value_start == NULL || value_len == NULL)
    {
        return 0;
    }

    search_key = key;
    key_len = (uint32_t)strlen(search_key);
    p = text;

    while ((p = strstr(p, search_key)) != NULL)
    {
        if ((p == text || p[-1] == '\n' || p[-1] == '\r') &&
            p[key_len] == '=')
        {
            break;
        }

        p++;
    }

    if (p == NULL)
    {
        search_key = wallet_cmd_c5_0_alias_key(key);
        if (search_key == NULL)
        {
            return 0;
        }

        key_len = (uint32_t)strlen(search_key);
        p = text;

        while ((p = strstr(p, search_key)) != NULL)
        {
            if ((p == text || p[-1] == '\n' || p[-1] == '\r') &&
                p[key_len] == '=')
            {
                break;
            }

            p++;
        }

        if (p == NULL)
        {
            return 0;
        }
    }

    v = p + key_len;
    v++;

    e = v;

    while (*e != '\0' && *e != '\r' && *e != '\n')
    {
        e++;
    }

    if (e == v)
    {
        return 0;
    }

    *value_start = v;
    *value_len = (uint32_t)(e - v);

    return 1;
}


static int wallet_cmd_parse_hex_fixed(const char *text,
                                      const char *key,
                                      uint8_t *out,
                                      uint32_t out_len)
{
    const char *v;
    uint32_t value_len;
    uint32_t expected_hex_len;
    uint8_t hi;
    uint8_t lo;

    if (out == NULL)
    {
        return 0;
    }

    if (!wallet_cmd_find_value(text, key, &v, &value_len))
    {
        return 0;
    }

    expected_hex_len = out_len * 2U;

    if (value_len != expected_hex_len)
    {
        return 0;
    }

    for (uint32_t i = 0; i < out_len; i++)
    {
        if (!wallet_cmd_hex_nibble(v[i * 2U], &hi))
        {
            return 0;
        }

        if (!wallet_cmd_hex_nibble(v[(i * 2U) + 1U], &lo))
        {
            return 0;
        }

        out[i] = (uint8_t)((hi << 4) | lo);
    }

    return 1;
}

static int wallet_cmd_parse_hex_var(const char *text,
                                    const char *key,
                                    uint8_t *out,
                                    uint32_t out_size,
                                    uint32_t *out_len)
{
    const char *v;
    uint32_t value_len;
    uint8_t hi;
    uint8_t lo;

    if (out == NULL || out_len == NULL)
    {
        return 0;
    }

    if (!wallet_cmd_find_value(text, key, &v, &value_len))
    {
        return 0;
    }

    if ((value_len == 0U) || ((value_len % 2U) != 0U))
    {
        return 0;
    }

    if ((value_len / 2U) > out_size)
    {
        return 0;
    }

    for (uint32_t i = 0; i < (value_len / 2U); i++)
    {
        if (!wallet_cmd_hex_nibble(v[i * 2U], &hi))
        {
            return 0;
        }

        if (!wallet_cmd_hex_nibble(v[(i * 2U) + 1U], &lo))
        {
            return 0;
        }

        out[i] = (uint8_t)((hi << 4) | lo);
    }

    *out_len = value_len / 2U;

    return 1;
}

static int wallet_cmd_parse_u32(const char *text,
                                const char *key,
                                uint32_t *out)
{
    const char *v;
    uint32_t value_len;
    uint32_t value = 0;

    if (out == NULL)
    {
        return 0;
    }

    if (!wallet_cmd_find_value(text, key, &v, &value_len))
    {
        return 0;
    }

    for (uint32_t i = 0; i < value_len; i++)
    {
        if (v[i] < '0' || v[i] > '9')
        {
            return 0;
        }

        value = (value * 10U) + (uint32_t)(v[i] - '0');
    }

    *out = value;

    return 1;
}

static int wallet_cmd_parse_u64(const char *text,
                                const char *key,
                                uint64_t *out)
{
    const char *v;
    uint32_t value_len;
    uint64_t value = 0;

    if (out == NULL)
    {
        return 0;
    }

    if (!wallet_cmd_find_value(text, key, &v, &value_len))
    {
        return 0;
    }

    for (uint32_t i = 0; i < value_len; i++)
    {
        if (v[i] < '0' || v[i] > '9')
        {
            return 0;
        }

        value = (value * 10ULL) + (uint64_t)(v[i] - '0');
    }

    *out = value;

    return 1;
}

/*
 * Public policy pre-check.
 *
 * wallet_uart.c calls this before key provider / TROPIC authorization.
 * This prevents private key access for unsafe commands.
 */


static int wallet_cmd_parse_value_equals(const char *text,
                                         const char *key,
                                         const char *expected)
{
    const char *v;
    uint32_t value_len;
    uint32_t expected_len;

    if (text == NULL || key == NULL || expected == NULL)
    {
        return 0;
    }

    if (!wallet_cmd_find_value(text, key, &v, &value_len))
    {
        return 0;
    }

    expected_len = (uint32_t)strlen(expected);

    if (value_len != expected_len)
    {
        return 0;
    }

    for (uint32_t i = 0; i < expected_len; i++)
    {
        if (v[i] != expected[i])
        {
            return 0;
        }
    }

    return 1;
}

static int wallet_command_network_allowed(const char *command_text,
                                          char *out_network,
                                          uint32_t out_network_size)
{
    if (command_text == NULL)
    {
        return 0;
    }

    if (wallet_cmd_parse_value_equals(command_text, "NETWORK", "REGTEST"))
    {
        if (out_network != NULL && out_network_size > 0U)
        {
            snprintf(out_network, out_network_size, "REGTEST");
        }
        return 1;
    }

#if WALLET_TESTNET_SIGNING_BUILD_FLAG
    if (wallet_cmd_parse_value_equals(command_text, "NETWORK", "TESTNET"))
    {
        if (out_network != NULL && out_network_size > 0U)
        {
            snprintf(out_network, out_network_size, "TESTNET");
        }
        return 1;
    }
#endif

    if (out_network != NULL && out_network_size > 0U)
    {
        snprintf(out_network, out_network_size, "NON_REGTEST_OR_MISSING");
    }

    return 0;
}



int wallet_command_check_policy_text(const char *command_text)
{
    uint8_t prev_script_pubkey[252];
    uint32_t prev_script_pubkey_len = 0;
    uint8_t input1_prev_script_pubkey[252];
    uint32_t input1_prev_script_pubkey_len = 0;

    uint8_t pay_script_pubkey[252];
    uint32_t pay_script_pubkey_len = 0;

    uint8_t change_script_pubkey[252];
    uint32_t change_script_pubkey_len = 0;

    uint32_t input_count = 1U;
    uint64_t input_value_sats = 0ULL;
    uint64_t input1_value_sats = 0ULL;
    uint64_t total_input_value_sats = 0ULL;
    uint64_t pay_value_sats = 0ULL;
    uint64_t change_value_sats = 0ULL;

    wallet_policy_amounts_t policy_amounts;
    int policy_ret;

    if (command_text == NULL)
    {
        return WALLET_POLICY_ERR_NULL;
    }

    policy_ret = wallet_command_validate_c5_0_format_text(command_text);
    if (policy_ret != WALLET_POLICY_OK)
    {
        return policy_ret;
    }

    if (!wallet_command_network_allowed(command_text, NULL, 0U))
    {
        return WALLET_POLICY_ERR_NETWORK_NOT_REGTEST;
    }

    memset(prev_script_pubkey, 0, sizeof(prev_script_pubkey));
    memset(input1_prev_script_pubkey, 0, sizeof(input1_prev_script_pubkey));
    memset(pay_script_pubkey, 0, sizeof(pay_script_pubkey));
    memset(change_script_pubkey, 0, sizeof(change_script_pubkey));

    if (wallet_cmd_contains_exact_key(command_text, "PSBT_INPUT_COUNT") &&
        !wallet_cmd_parse_u32(command_text, "PSBT_INPUT_COUNT", &input_count))
    {
        return WALLET_POLICY_ERR_FORMAT_INVALID;
    }

    if (input_count == 0U || input_count > WALLET_COMMAND_MAX_INPUTS)
    {
        return WALLET_POLICY_ERR_INPUT_COUNT_UNSUPPORTED;
    }

    if (!wallet_cmd_parse_u64(command_text, "INPUT_SATS", &input_value_sats))
    {
        return -12;
    }

    if (!wallet_cmd_parse_hex_var(command_text,
                                  "PREV_SCRIPT",
                                  prev_script_pubkey,
                                  sizeof(prev_script_pubkey),
                                  &prev_script_pubkey_len))
    {
        return -13;
    }

    if (input_count == 2U)
    {
        if (!wallet_cmd_parse_u64(command_text, "PSBT_INPUT1_SATS", &input1_value_sats))
        {
            return -20;
        }

        if (!wallet_cmd_parse_hex_var(command_text,
                                      "PSBT_INPUT1_PREV_SCRIPT",
                                      input1_prev_script_pubkey,
                                      sizeof(input1_prev_script_pubkey),
                                      &input1_prev_script_pubkey_len))
        {
            return -21;
        }
    }

    if (!wallet_cmd_parse_hex_var(command_text,
                                  "PAY_SCRIPT",
                                  pay_script_pubkey,
                                  sizeof(pay_script_pubkey),
                                  &pay_script_pubkey_len))
    {
        return -14;
    }

    if (!wallet_cmd_parse_u64(command_text, "PAY_SATS", &pay_value_sats))
    {
        return -15;
    }

    if (!wallet_cmd_parse_hex_var(command_text,
                                  "CHANGE_SCRIPT",
                                  change_script_pubkey,
                                  sizeof(change_script_pubkey),
                                  &change_script_pubkey_len))
    {
        return -16;
    }

    if (!wallet_cmd_parse_u64(command_text, "CHANGE_SATS", &change_value_sats))
    {
        return -17;
    }

    total_input_value_sats = input_value_sats;
    if (input_count == 2U)
    {
        if (input1_value_sats > (UINT64_MAX - total_input_value_sats))
        {
            return WALLET_POLICY_ERR_OUTPUT_SUM;
        }
        total_input_value_sats += input1_value_sats;
    }

    policy_amounts.input_sats = total_input_value_sats;
    policy_amounts.pay_sats = pay_value_sats;
    policy_amounts.change_sats = change_value_sats;
    policy_amounts.fee_sats = 0ULL;
    policy_amounts.input_count = input_count;

    policy_ret = wallet_policy_check_amounts(&policy_amounts);

    if (policy_ret != WALLET_POLICY_OK)
    {
        return policy_ret;
    }

    policy_ret = wallet_policy_check_own_input_script(
        prev_script_pubkey,
        prev_script_pubkey_len
    );

    if (policy_ret != WALLET_POLICY_OK)
    {
        return policy_ret;
    }

    if (input_count == 2U)
    {
        policy_ret = wallet_policy_check_own_input_script(
            input1_prev_script_pubkey,
            input1_prev_script_pubkey_len
        );

        if (policy_ret != WALLET_POLICY_OK)
        {
            return policy_ret;
        }
    }

    policy_ret = wallet_policy_check_allowed_pay_script(
        pay_script_pubkey,
        pay_script_pubkey_len
    );

    if (policy_ret != WALLET_POLICY_OK)
    {
        return policy_ret;
    }

    policy_ret = wallet_command_check_change_script_for_network(
        command_text,
        change_script_pubkey,
        change_script_pubkey_len
    );

    if (policy_ret != WALLET_POLICY_OK)
    {
        return policy_ret;
    }

    return WALLET_POLICY_OK;
}


/*
 * C2.6 device-side transaction policy summary with input binding.
 *
 * This intentionally does NOT check the PIN session and does NOT sign.
 * It parses the same transaction-policy fields used by SIGN and runs
 * the same policy checks, but returns only summary data and a decision.
 */
int wallet_command_check_summary_text(
    const char *command_text,
    wallet_command_summary_t *out_summary)
{
    uint8_t prev_txid_le[32];
    uint8_t input1_txid_le[32];

    uint8_t prev_script_pubkey[252];
    uint32_t prev_script_pubkey_len = 0;
    uint8_t input1_prev_script_pubkey[252];
    uint32_t input1_prev_script_pubkey_len = 0;

    uint8_t pay_script_pubkey[252];
    uint32_t pay_script_pubkey_len = 0;

    uint8_t change_script_pubkey[252];
    uint32_t change_script_pubkey_len = 0;

    uint32_t input_count = 1U;
    uint32_t prev_vout = 0;
    uint32_t input1_vout = 0;
    uint64_t input_value_sats = 0ULL;
    uint64_t input1_value_sats = 0ULL;
    uint64_t total_input_value_sats = 0ULL;
    uint64_t pay_value_sats = 0ULL;
    uint64_t change_value_sats = 0ULL;

    wallet_policy_amounts_t policy_amounts;
    int policy_ret;

    if (command_text == NULL || out_summary == NULL)
    {
        return WALLET_POLICY_ERR_NULL;
    }

    memset(out_summary, 0, sizeof(*out_summary));
    memset(prev_txid_le, 0, sizeof(prev_txid_le));
    memset(input1_txid_le, 0, sizeof(input1_txid_le));
    memset(prev_script_pubkey, 0, sizeof(prev_script_pubkey));
    memset(input1_prev_script_pubkey, 0, sizeof(input1_prev_script_pubkey));
    memset(pay_script_pubkey, 0, sizeof(pay_script_pubkey));
    memset(change_script_pubkey, 0, sizeof(change_script_pubkey));

    policy_ret = wallet_command_validate_c5_0_format_text(command_text);
    if (policy_ret != WALLET_POLICY_OK)
    {
        out_summary->policy_result = policy_ret;
        return policy_ret;
    }

    if (wallet_cmd_contains_exact_key(command_text, "PSBT_INPUT_COUNT") &&
        !wallet_cmd_parse_u32(command_text, "PSBT_INPUT_COUNT", &input_count))
    {
        out_summary->policy_result = WALLET_POLICY_ERR_FORMAT_INVALID;
        return WALLET_POLICY_ERR_FORMAT_INVALID;
    }

    if (input_count == 0U || input_count > WALLET_COMMAND_MAX_INPUTS)
    {
        out_summary->policy_result = WALLET_POLICY_ERR_INPUT_COUNT_UNSUPPORTED;
        return WALLET_POLICY_ERR_INPUT_COUNT_UNSUPPORTED;
    }

    (void)wallet_command_network_allowed(command_text,
                                         out_summary->network,
                                         sizeof(out_summary->network));

    if (!wallet_cmd_parse_hex_fixed(command_text, "TXID_LE", prev_txid_le, 32U))
    {
        out_summary->policy_result = -10;
        return -10;
    }

    if (!wallet_cmd_parse_u32(command_text, "VOUT", &prev_vout))
    {
        out_summary->policy_result = -11;
        return -11;
    }

    if (!wallet_cmd_parse_u64(command_text, "INPUT_SATS", &input_value_sats))
    {
        out_summary->policy_result = -12;
        return -12;
    }

    if (!wallet_cmd_parse_hex_var(command_text,
                                  "PREV_SCRIPT",
                                  prev_script_pubkey,
                                  sizeof(prev_script_pubkey),
                                  &prev_script_pubkey_len))
    {
        out_summary->policy_result = -13;
        return -13;
    }

    if (input_count == 2U)
    {
        if (!wallet_cmd_parse_hex_fixed(command_text, "PSBT_INPUT1_TXID_LE", input1_txid_le, 32U))
        {
            out_summary->policy_result = -18;
            return -18;
        }

        if (!wallet_cmd_parse_u32(command_text, "PSBT_INPUT1_VOUT", &input1_vout))
        {
            out_summary->policy_result = -19;
            return -19;
        }

        if (!wallet_cmd_parse_u64(command_text, "PSBT_INPUT1_SATS", &input1_value_sats))
        {
            out_summary->policy_result = -20;
            return -20;
        }

        if (!wallet_cmd_parse_hex_var(command_text,
                                      "PSBT_INPUT1_PREV_SCRIPT",
                                      input1_prev_script_pubkey,
                                      sizeof(input1_prev_script_pubkey),
                                      &input1_prev_script_pubkey_len))
        {
            out_summary->policy_result = -21;
            return -21;
        }
    }

    if (!wallet_cmd_parse_hex_var(command_text,
                                  "PAY_SCRIPT",
                                  pay_script_pubkey,
                                  sizeof(pay_script_pubkey),
                                  &pay_script_pubkey_len))
    {
        out_summary->policy_result = -14;
        return -14;
    }

    if (!wallet_cmd_parse_u64(command_text, "PAY_SATS", &pay_value_sats))
    {
        out_summary->policy_result = -15;
        return -15;
    }

    if (!wallet_cmd_parse_hex_var(command_text,
                                  "CHANGE_SCRIPT",
                                  change_script_pubkey,
                                  sizeof(change_script_pubkey),
                                  &change_script_pubkey_len))
    {
        out_summary->policy_result = -16;
        return -16;
    }

    if (!wallet_cmd_parse_u64(command_text, "CHANGE_SATS", &change_value_sats))
    {
        out_summary->policy_result = -17;
        return -17;
    }

    total_input_value_sats = input_value_sats;
    if (input_count == 2U)
    {
        if (input1_value_sats > (UINT64_MAX - total_input_value_sats))
        {
            out_summary->policy_result = WALLET_POLICY_ERR_OUTPUT_SUM;
            return WALLET_POLICY_ERR_OUTPUT_SUM;
        }
        total_input_value_sats += input1_value_sats;
    }

    out_summary->input_count = input_count;
    out_summary->vout = prev_vout;
    out_summary->input1_vout = input1_vout;
    out_summary->input_sats = input_value_sats;
    out_summary->input1_sats = input1_value_sats;
    out_summary->total_input_sats = total_input_value_sats;
    out_summary->pay_sats = pay_value_sats;
    out_summary->change_sats = change_value_sats;

    if (total_input_value_sats >= pay_value_sats &&
        (total_input_value_sats - pay_value_sats) >= change_value_sats)
    {
        out_summary->fee_sats =
            total_input_value_sats - pay_value_sats - change_value_sats;
    }
    else
    {
        out_summary->fee_sats = 0ULL;
    }

    if (!wallet_bytes_to_hex(prev_txid_le,
                             sizeof(prev_txid_le),
                             out_summary->txid_le_hex,
                             sizeof(out_summary->txid_le_hex)))
    {
        out_summary->policy_result = -31;
        return -31;
    }

    if (input_count == 2U &&
        !wallet_bytes_to_hex(input1_txid_le,
                             sizeof(input1_txid_le),
                             out_summary->input1_txid_le_hex,
                             sizeof(out_summary->input1_txid_le_hex)))
    {
        out_summary->policy_result = -35;
        return -35;
    }

    if (!wallet_bytes_to_hex(prev_script_pubkey,
                             prev_script_pubkey_len,
                             out_summary->prev_script_hex,
                             sizeof(out_summary->prev_script_hex)))
    {
        out_summary->policy_result = -32;
        return -32;
    }

    if (input_count == 2U &&
        !wallet_bytes_to_hex(input1_prev_script_pubkey,
                             input1_prev_script_pubkey_len,
                             out_summary->input1_prev_script_hex,
                             sizeof(out_summary->input1_prev_script_hex)))
    {
        out_summary->policy_result = -36;
        return -36;
    }

    if (!wallet_bytes_to_hex(pay_script_pubkey,
                             pay_script_pubkey_len,
                             out_summary->pay_script_hex,
                             sizeof(out_summary->pay_script_hex)))
    {
        out_summary->policy_result = -33;
        return -33;
    }

    if (!wallet_bytes_to_hex(change_script_pubkey,
                             change_script_pubkey_len,
                             out_summary->change_script_hex,
                             sizeof(out_summary->change_script_hex)))
    {
        out_summary->policy_result = -34;
        return -34;
    }

    
    if (!wallet_command_compute_check_id(out_summary))
    {
        out_summary->policy_result = -45;
        return -45;
    }
    if (!wallet_command_network_allowed(command_text, NULL, 0U))
    {
        out_summary->policy_result = WALLET_POLICY_ERR_NETWORK_NOT_REGTEST;
        return WALLET_POLICY_ERR_NETWORK_NOT_REGTEST;
    }

    policy_amounts.input_sats = total_input_value_sats;
    policy_amounts.pay_sats = pay_value_sats;
    policy_amounts.change_sats = change_value_sats;
    policy_amounts.fee_sats = 0ULL;
    policy_amounts.input_count = input_count;

    policy_ret = wallet_policy_check_amounts(&policy_amounts);

    if (policy_ret != WALLET_POLICY_OK)
    {
        out_summary->policy_result = policy_ret;
        return policy_ret;
    }

    policy_ret = wallet_policy_check_own_input_script(
        prev_script_pubkey,
        prev_script_pubkey_len
    );

    if (policy_ret != WALLET_POLICY_OK)
    {
        out_summary->policy_result = policy_ret;
        return policy_ret;
    }

    if (input_count == 2U)
    {
        policy_ret = wallet_policy_check_own_input_script(
            input1_prev_script_pubkey,
            input1_prev_script_pubkey_len
        );

        if (policy_ret != WALLET_POLICY_OK)
        {
            out_summary->policy_result = policy_ret;
            return policy_ret;
        }
    }

    policy_ret = wallet_policy_check_allowed_pay_script(
        pay_script_pubkey,
        pay_script_pubkey_len
    );

    if (policy_ret != WALLET_POLICY_OK)
    {
        out_summary->policy_result = policy_ret;
        return policy_ret;
    }

    policy_ret = wallet_command_check_change_script_for_network(
        command_text,
        change_script_pubkey,
        change_script_pubkey_len
    );

    if (policy_ret != WALLET_POLICY_OK)
    {
        out_summary->policy_result = policy_ret;
        return policy_ret;
    }

    out_summary->policy_result = WALLET_POLICY_OK;
    return WALLET_POLICY_OK;
}
/*
 * Core signing implementation.
 *
 * This parses transaction fields only.
 * It does NOT parse PRIVKEY=.
 *
 * The private key is supplied separately by the caller.
 */
static int wallet_command_sign_text_core(
    const char *command_text,
    const uint8_t *private_key,
    uint8_t *out_raw_tx,
    uint32_t out_raw_tx_size,
    uint32_t *out_raw_tx_len,
    char *out_raw_tx_hex,
    uint32_t out_raw_tx_hex_size)
{
    uint8_t prev_txid_le[32];
    uint8_t input1_txid_le[32];

    uint8_t prev_script_pubkey[252];
    uint32_t prev_script_pubkey_len = 0;
    uint8_t input1_prev_script_pubkey[252];
    uint32_t input1_prev_script_pubkey_len = 0;

    uint8_t pay_script_pubkey[252];
    uint32_t pay_script_pubkey_len = 0;

    uint8_t change_script_pubkey[252];
    uint32_t change_script_pubkey_len = 0;

    wallet_legacy_p2pkh_input_t inputs[WALLET_COMMAND_MAX_INPUTS];
    uint32_t input_count = 1U;
    uint32_t prev_vout = 0;
    uint32_t input1_vout = 0;
    uint64_t input_value_sats = 0ULL;
    uint64_t input1_value_sats = 0ULL;
    uint64_t total_input_value_sats = 0ULL;
    uint64_t pay_value_sats = 0ULL;
    uint64_t change_value_sats = 0ULL;

    int ret;

    if (command_text == NULL ||
        private_key == NULL ||
        out_raw_tx == NULL ||
        out_raw_tx_len == NULL ||
        out_raw_tx_hex == NULL)
    {
        return -1;
    }

    if (!wallet_command_network_allowed(command_text, NULL, 0U))
    {
        return WALLET_POLICY_ERR_NETWORK_NOT_REGTEST;
    }

    ret = wallet_command_validate_c5_0_format_text(command_text);
    if (ret != WALLET_POLICY_OK)
    {
        return ret;
    }



    memset(prev_txid_le, 0, sizeof(prev_txid_le));
    memset(input1_txid_le, 0, sizeof(input1_txid_le));
    memset(prev_script_pubkey, 0, sizeof(prev_script_pubkey));
    memset(input1_prev_script_pubkey, 0, sizeof(input1_prev_script_pubkey));
    memset(pay_script_pubkey, 0, sizeof(pay_script_pubkey));
    memset(change_script_pubkey, 0, sizeof(change_script_pubkey));
    memset(inputs, 0, sizeof(inputs));

    if (wallet_cmd_contains_exact_key(command_text, "PSBT_INPUT_COUNT") &&
        !wallet_cmd_parse_u32(command_text, "PSBT_INPUT_COUNT", &input_count))
    {
        return WALLET_POLICY_ERR_FORMAT_INVALID;
    }

    if (input_count == 0U || input_count > WALLET_COMMAND_MAX_INPUTS)
    {
        return WALLET_POLICY_ERR_INPUT_COUNT_UNSUPPORTED;
    }

    /*
     * For now, command expects TXID_LE, not normal big-endian display txid.
     * Later we can add TXID_BE and reverse internally.
     */
    if (!wallet_cmd_parse_hex_fixed(command_text, "TXID_LE", prev_txid_le, 32U))
    {
        return -10;
    }

    if (!wallet_cmd_parse_u32(command_text, "VOUT", &prev_vout))
    {
        return -11;
    }

    if (!wallet_cmd_parse_u64(command_text, "INPUT_SATS", &input_value_sats))
    {
        return -12;
    }

    if (!wallet_cmd_parse_hex_var(command_text,
                                  "PREV_SCRIPT",
                                  prev_script_pubkey,
                                  sizeof(prev_script_pubkey),
                                  &prev_script_pubkey_len))
    {
        return -13;
    }

    if (input_count == 2U)
    {
        if (!wallet_cmd_parse_hex_fixed(command_text, "PSBT_INPUT1_TXID_LE", input1_txid_le, 32U))
        {
            return -18;
        }

        if (!wallet_cmd_parse_u32(command_text, "PSBT_INPUT1_VOUT", &input1_vout))
        {
            return -19;
        }

        if (!wallet_cmd_parse_u64(command_text, "PSBT_INPUT1_SATS", &input1_value_sats))
        {
            return -20;
        }

        if (!wallet_cmd_parse_hex_var(command_text,
                                      "PSBT_INPUT1_PREV_SCRIPT",
                                      input1_prev_script_pubkey,
                                      sizeof(input1_prev_script_pubkey),
                                      &input1_prev_script_pubkey_len))
        {
            return -21;
        }
    }

    if (!wallet_cmd_parse_hex_var(command_text,
                                  "PAY_SCRIPT",
                                  pay_script_pubkey,
                                  sizeof(pay_script_pubkey),
                                  &pay_script_pubkey_len))
    {
        return -14;
    }

    if (!wallet_cmd_parse_u64(command_text, "PAY_SATS", &pay_value_sats))
    {
        return -15;
    }

    if (!wallet_cmd_parse_hex_var(command_text,
                                  "CHANGE_SCRIPT",
                                  change_script_pubkey,
                                  sizeof(change_script_pubkey),
                                  &change_script_pubkey_len))
    {
        return -16;
    }

    if (!wallet_cmd_parse_u64(command_text, "CHANGE_SATS", &change_value_sats))
    {
        return -17;
    }

    total_input_value_sats = input_value_sats;
    if (input_count == 2U)
    {
        if (input1_value_sats > (UINT64_MAX - total_input_value_sats))
        {
            return WALLET_POLICY_ERR_OUTPUT_SUM;
        }
        total_input_value_sats += input1_value_sats;
    }

    /*
     * Defense-in-depth policy check.
     *
     * wallet_uart.c should already have called wallet_command_check_policy_text()
     * before key provider / TROPIC authorization. This repeats the same checks
     * before actually building/signing the transaction.
     */
    {
        wallet_policy_amounts_t policy_amounts;
        int policy_ret;

        policy_amounts.input_sats = total_input_value_sats;
        policy_amounts.pay_sats = pay_value_sats;
        policy_amounts.change_sats = change_value_sats;
        policy_amounts.fee_sats = 0ULL;
        policy_amounts.input_count = input_count;

        policy_ret = wallet_policy_check_amounts(&policy_amounts);

        if (policy_ret != WALLET_POLICY_OK)
        {
            return policy_ret;
        }

        policy_ret = wallet_policy_check_own_input_script(
            prev_script_pubkey,
            prev_script_pubkey_len
        );

        if (policy_ret != WALLET_POLICY_OK)
        {
            return policy_ret;
        }

        if (input_count == 2U)
        {
            policy_ret = wallet_policy_check_own_input_script(
                input1_prev_script_pubkey,
                input1_prev_script_pubkey_len
            );

            if (policy_ret != WALLET_POLICY_OK)
            {
                return policy_ret;
            }
        }

        policy_ret = wallet_policy_check_allowed_pay_script(
            pay_script_pubkey,
            pay_script_pubkey_len
        );

        if (policy_ret != WALLET_POLICY_OK)
        {
            return policy_ret;
        }

        policy_ret = wallet_command_check_change_script_for_network(
            command_text,
            change_script_pubkey,
            change_script_pubkey_len
        );

        if (policy_ret != WALLET_POLICY_OK)
        {
            return policy_ret;
        }
    }

    inputs[0].prev_txid_le = prev_txid_le;
    inputs[0].prev_vout = prev_vout;
    inputs[0].prev_script_pubkey = prev_script_pubkey;
    inputs[0].prev_script_pubkey_len = prev_script_pubkey_len;
    inputs[0].input_value_sats = input_value_sats;
    inputs[0].sequence = 0xFFFFFFFFU;

    if (input_count == 2U)
    {
        inputs[1].prev_txid_le = input1_txid_le;
        inputs[1].prev_vout = input1_vout;
        inputs[1].prev_script_pubkey = input1_prev_script_pubkey;
        inputs[1].prev_script_pubkey_len = input1_prev_script_pubkey_len;
        inputs[1].input_value_sats = input1_value_sats;
        inputs[1].sequence = 0xFFFFFFFFU;
    }

    ret = wallet_sign_p2pkh_multi_2out_tx(
        inputs,
        input_count,

        pay_script_pubkey,
        pay_script_pubkey_len,
        pay_value_sats,

        change_script_pubkey,
        change_script_pubkey_len,
        change_value_sats,

        private_key,

        out_raw_tx,
        out_raw_tx_size,
        out_raw_tx_len
    );

    if (ret != 0)
    {
        return -30;
    }

    if (!wallet_bytes_to_hex(
            out_raw_tx,
            *out_raw_tx_len,
            out_raw_tx_hex,
            out_raw_tx_hex_size))
    {
        return -31;
    }

    return 0;
}

/*
 * New clean API.
 *
 * Used by wallet_uart.c.
 * The UART command does not contain PRIVKEY=.
 */
int wallet_command_sign_text_with_private_key(
    const char *command_text,
    const uint8_t *private_key,
    uint8_t *out_raw_tx,
    uint32_t out_raw_tx_size,
    uint32_t *out_raw_tx_len,
    char *out_raw_tx_hex,
    uint32_t out_raw_tx_hex_size)
{
    return wallet_command_sign_text_core(
        command_text,
        private_key,
        out_raw_tx,
        out_raw_tx_size,
        out_raw_tx_len,
        out_raw_tx_hex,
        out_raw_tx_hex_size
    );
}

/*
 * C4.0: legacy host-supplied key signing is permanently disabled.
 */
int wallet_command_sign_text(
    const char *command_text,
    uint8_t *out_raw_tx,
    uint32_t out_raw_tx_size,
    uint32_t *out_raw_tx_len,
    char *out_raw_tx_hex,
    uint32_t out_raw_tx_hex_size)
{
    (void)command_text;
    (void)out_raw_tx;
    (void)out_raw_tx_size;
    (void)out_raw_tx_len;
    (void)out_raw_tx_hex;
    (void)out_raw_tx_hex_size;

    return WALLET_POLICY_ERR_LEGACY_SIGN_DISABLED;
}







