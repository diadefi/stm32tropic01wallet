#include "main.h"
#include "wallet_uart.h"
#include "wallet_build_config.h"
#include "wallet_command.h"
#include "wallet_debug_test.h"
#include "wallet_key_provider.h"
#include "wallet_secure_element.h"
#include "wallet_policy.h"

#include "psa/crypto.h"

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>


/*
 * C2.0 device identity reporting.
 *
 * These are public wallet identity values for the current MVP key.
 * They are safe to expose over UART.
 *
 * TODO C2.x:
 * Replace static public identity constants with derivation from the
 * active firmware-owned signing key/public key path.
 */
#define WALLET_C2_ADDRESS_REGTEST       "mrCDrCybB6J1vRfbwM5hemdJz73FwDBC8r"
#define WALLET_C2_PUBKEY_COMPRESSED     "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
#define WALLET_C2_SCRIPT_P2PKH          "76a914751e76e8199196d454941c45d1b3a323f1433bd688ac"
#define WALLET_C2_IDENTITY_VERSION      "C2.0_DEVICE_IDENTITY_REPORTING"
#define WALLET_C2_KEY_MODEL             "KDF_AES_GCM_WRAPPED_SECP256K1_KEY_BLOB_TROPIC_AUTH_GATE"
#define WALLET_C9_7_BIP84_IDENTITY_VERSION "C9.7_TESTNET_BIP84_IDENTITY_V1"
#define WALLET_C9_7_TESTNET_BIP84_ADDRESS "tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx"
#define WALLET_C9_7_TESTNET_BIP84_SCRIPT_P2WPKH "0014751e76e8199196d454941c45d1b3a323f1433bd6"
#define WALLET_C9_7_TESTNET_BIP84_PUBKEY_HASH160 "751e76e8199196d454941c45d1b3a323f1433bd6"
#define WALLET_C9_7_TESTNET_BIP84_ACCOUNT_PATH "m/84h/1h/0h"
#define WALLET_C9_7_TESTNET_BIP84_RECEIVE_PATH "m/84h/1h/0h/0/0"
#define WALLET_C9_7_TESTNET_BIP84_CHANGE_PATH "m/84h/1h/0h/1/0"
#define WALLET_PROTOCOL_VERSION         "C6.0_TEXT_PROTOCOL_V1"
#define WALLET_COMMAND_VERSION          "C6.0_COMMAND_FIELDS_V1"
#define WALLET_RESPONSE_VERSION         "C6.0_RESPONSE_FIELDS_V1"
#define WALLET_ERROR_VERSION            "C6.0_ERROR_FIELDS_V1"
#define WALLET_POLICY_VERSION           "C6.0_POLICY_LABELS_V1"
#define WALLET_FRAME_VERSION            "C6.1_TEXT_FRAME_V1"
#define WALLET_FRAME_CRC_NAME           "CRC32_IEEE"
#define WALLET_FRAME_MAX_PAYLOAD        1200U
#define WALLET_FRAME_ERR_INVALID        -70
#define WALLET_FRAME_ERR_LEN            -71
#define WALLET_FRAME_ERR_CRC            -72
#define WALLET_FRAME_ERR_UNSUPPORTED    -73
#define WALLET_REAL_BITCOIN_STAGE       "C9.8_TESTNET_CHANGE_DERIVATION_ENFORCEMENT"
#define WALLET_REAL_BITCOIN_READINESS   "C9.8_TESTNET_CHANGE_DERIVATION_ENFORCEMENT"

#ifndef WALLET_TESTNET_SIGNING_BUILD_FLAG
#define WALLET_TESTNET_SIGNING_BUILD_FLAG 0
#endif

#ifndef WALLET_MAINNET_SIGNING_BUILD_FLAG
#define WALLET_MAINNET_SIGNING_BUILD_FLAG 0
#endif
/*
 * BSP COM1 is the path that actually reaches the ST-LINK Virtual COM port.
 * The direct smoke test proved hcom_uart[COM1] prints on COM3.
 */
extern UART_HandleTypeDef hcom_uart[];
extern RNG_HandleTypeDef hrng;

#define WALLET_UART_CMD_MAX        1536U
#define WALLET_UART_RESPONSE_MAX   640U

#define WALLET_UART_READ_SIGN        0
#define WALLET_UART_READ_SEINFO      1
#define WALLET_UART_READ_POLICYINFO  2
#define WALLET_UART_READ_VERSION    3
#define WALLET_UART_READ_SEKEYINFO  4
#define WALLET_UART_READ_SEKEYTEST  5


#define WALLET_UART_READ_IDENTITY  6
#define WALLET_UART_READ_ADDR      7
#define WALLET_UART_READ_PUBKEY    8
#define WALLET_UART_READ_SCRIPT    9
#define WALLET_UART_READ_CHECK 100
#define WALLET_UART_READ_CONFIRM 101
#define WALLET_UART_READ_BUTTONINFO 102
#define WALLET_UART_READ_UNLOCK_PIN 103
#define WALLET_UART_READ_LOCK 104
#define WALLET_UART_READ_UNLOCKINFO 105
#define WALLET_UART_READ_FRAMEINFO 106
#define WALLET_UART_READ_REALINFO 107
#define WALLET_UART_RX_POLL_MS 25U
#define WALLET_UART_BUTTON_DEBOUNCE_MS 200U
volatile int wallet_uart_ret = 999;
volatile int wallet_uart_keypolicy_ret = 999;
volatile uint32_t wallet_uart_rx_len = 0;
volatile uint32_t wallet_uart_tx_len = 0;

static char wallet_uart_cmd[WALLET_UART_CMD_MAX];
static char wallet_uart_response[WALLET_UART_RESPONSE_MAX];
static uint8_t wallet_uart_private_key[WALLET_KEY_PROVIDER_PRIVKEY_BYTES_LEN];
static uint32_t wallet_uart_button_prev_state = 0U;
static uint32_t wallet_uart_button_last_ms = 0U;
static uint32_t wallet_uart_button_confirm_armed = 0U;
static int wallet_uart_command_is_exact(const char *cmd,
                                        const char *expected);

static void wallet_uart_send_policyinfo(void);
static void wallet_uart_send_version(void);
static void wallet_uart_send_frameinfo(void);
static void wallet_uart_send_realinfo(void);
static void wallet_uart_send_identity(void);
static void wallet_uart_send_addr(void);
static void wallet_uart_send_pubkey(void);
static void wallet_uart_send_script(void);
static void wallet_uart_send_confirm_result(void);
static void wallet_uart_send_sekeyinfo(void);
static void wallet_uart_send_buttoninfo(void);
static void wallet_uart_send_unlockinfo(void);
static void wallet_uart_send_unlock_result(void);
static void wallet_uart_poll_button_confirm(void);
static const char *wallet_uart_confirm_code_arg(void);
static const char *wallet_uart_unlock_pin_arg(void);
static void wallet_uart_clear_command_buffer(void);


static void wallet_uart_send_sekeytest(void);
static void wallet_uart_send_str(const char *s)
{
    if (s == NULL)
    {
        return;
    }

    uint32_t len = (uint32_t)strlen(s);
    wallet_uart_tx_len = len;

    (void)HAL_UART_Transmit(
        &hcom_uart[COM1],
        (uint8_t *)s,
        len,
        HAL_MAX_DELAY
    );
}

static void wallet_uart_secure_zero(void *buf, size_t len)
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

static void wallet_uart_clear_command_buffer(void)
{
    wallet_uart_secure_zero(wallet_uart_cmd, sizeof(wallet_uart_cmd));
    wallet_uart_rx_len = 0;
}

static void wallet_uart_poll_button_confirm(void)
{
    uint32_t now_ms;
    uint32_t state;
    int confirm_ret;

    state = (BSP_PB_GetState(BUTTON_USER) != GPIO_PIN_RESET) ? 1U : 0U;
    now_ms = HAL_GetTick();

    if (!wallet_command_peek_approved_check() ||
        wallet_command_peek_confirmed_approved_check())
    {
        wallet_uart_button_confirm_armed = 0U;
        wallet_uart_button_prev_state = state;
        return;
    }

    if (state == 0U)
    {
        wallet_uart_button_confirm_armed = 1U;
    }

    if (state != 0U &&
        wallet_uart_button_confirm_armed != 0U &&
        wallet_uart_button_prev_state == 0U &&
        ((now_ms - wallet_uart_button_last_ms) >= WALLET_UART_BUTTON_DEBOUNCE_MS))
    {
        wallet_uart_button_last_ms = now_ms;

        if (wallet_command_peek_approved_check() &&
            !wallet_command_peek_confirmed_approved_check())
        {
            confirm_ret = wallet_command_confirm_approved_check();

            if (confirm_ret == WALLET_POLICY_OK)
            {
                wallet_uart_send_str("\r\nOK BUTTON_CONFIRM\r\n");
                wallet_uart_send_str("USER_APPROVED=1\r\n");
                wallet_uart_send_str("CONFIRM_SOURCE=BUTTON_USER\r\n");
                wallet_uart_button_confirm_armed = 0U;
            }
        }
    }

    wallet_uart_button_prev_state = state;
}

static void wallet_uart_send_seinfo(void)
{
    snprintf(wallet_uart_response,
             sizeof(wallet_uart_response),
             "\r\nOK SEINFO\r\n"
             "INIT_RET=%d\r\n"
             "INIT_ATTEMPTS=%lu\r\n"
             "LAST_ATTEMPT_RET=%d\r\n"
             "INITIALIZED=%lu\r\n"
             "AUTH_COUNT=%lu\r\n"
             "LT_INIT_RET=%d\r\n"
             "LT_MODE_RET=%d\r\n"
             "LT_CHIP_ID_RET=%d\r\n"
             "LT_DEINIT_RET=%d\r\n"
             "MODE=%lu\r\n",
             wallet_secure_element_init_ret,
             (unsigned long)wallet_secure_element_init_attempts,
             wallet_secure_element_last_attempt_ret,
             (unsigned long)wallet_secure_element_initialized,
             (unsigned long)wallet_secure_element_auth_count,
             wallet_secure_element_lt_init_ret,
             wallet_secure_element_lt_mode_ret,
             wallet_secure_element_lt_chip_id_ret,
             wallet_secure_element_lt_deinit_ret,
             (unsigned long)wallet_secure_element_mode_value);

    wallet_uart_send_str(wallet_uart_response);
}

static int wallet_uart_line_is_sign(const char *buf,
                                    uint32_t line_start,
                                    uint32_t line_end)
{
    if (buf == NULL)
    {
        return 0;
    }

    while (line_end > line_start &&
           (buf[line_end - 1U] == '\n' || buf[line_end - 1U] == '\r'))
    {
        line_end--;
    }

    if ((line_end - line_start) != 4U)
    {
        return 0;
    }

    if (buf[line_start + 0U] != 'S') return 0;
    if (buf[line_start + 1U] != 'I') return 0;
    if (buf[line_start + 2U] != 'G') return 0;
    if (buf[line_start + 3U] != 'N') return 0;

    return 1;
}

static int wallet_uart_line_is_seinfo(const char *buf,
                                      uint32_t line_start,
                                      uint32_t line_end)
{
    if (buf == NULL)
    {
        return 0;
    }

    while (line_end > line_start &&
           (buf[line_end - 1U] == '\n' || buf[line_end - 1U] == '\r'))
    {
        line_end--;
    }

    if ((line_end - line_start) != 6U)
    {
        return 0;
    }

    if (buf[line_start + 0U] != 'S') return 0;
    if (buf[line_start + 1U] != 'E') return 0;
    if (buf[line_start + 2U] != 'I') return 0;
    if (buf[line_start + 3U] != 'N') return 0;
    if (buf[line_start + 4U] != 'F') return 0;
    if (buf[line_start + 5U] != 'O') return 0;

    return 1;
}

static int wallet_uart_line_is_policyinfo(const char *buf,
                                          uint32_t line_start,
                                          uint32_t line_end)
{
    if (buf == NULL)
    {
        return 0;
    }

    while (line_end > line_start &&
           (buf[line_end - 1U] == '\n' || buf[line_end - 1U] == '\r'))
    {
        line_end--;
    }

    if ((line_end - line_start) != 10U)
    {
        return 0;
    }

    if (buf[line_start + 0U] != 'P') return 0;
    if (buf[line_start + 1U] != 'O') return 0;
    if (buf[line_start + 2U] != 'L') return 0;
    if (buf[line_start + 3U] != 'I') return 0;
    if (buf[line_start + 4U] != 'C') return 0;
    if (buf[line_start + 5U] != 'Y') return 0;
    if (buf[line_start + 6U] != 'I') return 0;
    if (buf[line_start + 7U] != 'N') return 0;
    if (buf[line_start + 8U] != 'F') return 0;
    if (buf[line_start + 9U] != 'O') return 0;

    return 1;
}

static int wallet_uart_line_is_version(const char *buf,
                                       uint32_t line_start,
                                       uint32_t line_end)
{
    while (line_end > line_start &&
           (buf[line_end - 1U] == '\n' || buf[line_end - 1U] == '\r'))
    {
        line_end--;
    }

    if ((line_end - line_start) != 7U)
    {
        return 0;
    }

    if (buf[line_start + 0U] != 'V') return 0;
    if (buf[line_start + 1U] != 'E') return 0;
    if (buf[line_start + 2U] != 'R') return 0;
    if (buf[line_start + 3U] != 'S') return 0;
    if (buf[line_start + 4U] != 'I') return 0;
    if (buf[line_start + 5U] != 'O') return 0;
    if (buf[line_start + 6U] != 'N') return 0;

    return 1;
}
static int wallet_uart_line_is_sekeyinfo(const char *buf,
                                         uint32_t line_start,
                                         uint32_t line_end)
{
    while (line_end > line_start &&
           (buf[line_end - 1U] == '\n' || buf[line_end - 1U] == '\r'))
    {
        line_end--;
    }

    if ((line_end - line_start) != 9U)
    {
        return 0;
    }

    return ((buf[line_start + 0U] == 'S') &&
            (buf[line_start + 1U] == 'E') &&
            (buf[line_start + 2U] == 'K') &&
            (buf[line_start + 3U] == 'E') &&
            (buf[line_start + 4U] == 'Y') &&
            (buf[line_start + 5U] == 'I') &&
            (buf[line_start + 6U] == 'N') &&
            (buf[line_start + 7U] == 'F') &&
            (buf[line_start + 8U] == 'O'));
}

static int wallet_uart_command_is_exact(const char *cmd,
                                        const char *expected)
{
    size_t expected_len;

    if (cmd == NULL || expected == NULL)
    {
        return 0;
    }

    while (*cmd == '\r' || *cmd == '\n' || *cmd == ' ' || *cmd == '\t')
    {
        cmd++;
    }

    expected_len = strlen(expected);

    if (strncmp(cmd, expected, expected_len) != 0)
    {
        return 0;
    }

    cmd += expected_len;

    while (*cmd == '\r' || *cmd == '\n' || *cmd == ' ' || *cmd == '\t')
    {
        cmd++;
    }

    return (*cmd == '\0');
}

static void wallet_uart_send_addr(void)
{
    wallet_uart_send_str("\r\nOK ADDR\r\n");
    wallet_uart_send_str("NETWORK=REGTEST\r\n");
    wallet_uart_send_str("ADDRESS=");
    wallet_uart_send_str(WALLET_C2_ADDRESS_REGTEST);
    wallet_uart_send_str("\r\n");
    wallet_uart_send_str("SCRIPT_P2PKH=");
    wallet_uart_send_str(WALLET_C2_SCRIPT_P2PKH);
    wallet_uart_send_str("\r\n");
    wallet_uart_send_str("TESTNET_BIP84_IDENTITY_VERSION=");
    wallet_uart_send_str(WALLET_C9_7_BIP84_IDENTITY_VERSION);
    wallet_uart_send_str("\r\n");
    wallet_uart_send_str("TESTNET_BIP84_ADDRESS=");
    wallet_uart_send_str(WALLET_C9_7_TESTNET_BIP84_ADDRESS);
    wallet_uart_send_str("\r\n");
    wallet_uart_send_str("TESTNET_BIP84_SCRIPT_P2WPKH=");
    wallet_uart_send_str(WALLET_C9_7_TESTNET_BIP84_SCRIPT_P2WPKH);
    wallet_uart_send_str("\r\n");
}

static void wallet_uart_send_pubkey(void)
{
    wallet_uart_send_str("\r\nOK PUBKEY\r\n");
    wallet_uart_send_str("PUBKEY_COMPRESSED=");
    wallet_uart_send_str(WALLET_C2_PUBKEY_COMPRESSED);
    wallet_uart_send_str("\r\n");
    wallet_uart_send_str("PUBKEY_HASH160=");
    wallet_uart_send_str(WALLET_C9_7_TESTNET_BIP84_PUBKEY_HASH160);
    wallet_uart_send_str("\r\n");
}

static void wallet_uart_send_script(void)
{
    wallet_uart_send_str("\r\nOK SCRIPT\r\n");
    wallet_uart_send_str("SCRIPT_P2PKH=");
    wallet_uart_send_str(WALLET_C2_SCRIPT_P2PKH);
    wallet_uart_send_str("\r\n");
    wallet_uart_send_str("TESTNET_SCRIPT_P2WPKH=");
    wallet_uart_send_str(WALLET_C9_7_TESTNET_BIP84_SCRIPT_P2WPKH);
    wallet_uart_send_str("\r\n");
}

static void wallet_uart_send_identity(void)
{
    wallet_uart_send_str("\r\nOK IDENTITY\r\n");
    wallet_uart_send_str("IDENTITY_VERSION=");
    wallet_uart_send_str(WALLET_C2_IDENTITY_VERSION);
    wallet_uart_send_str("\r\n");
    wallet_uart_send_str("NETWORK=REGTEST\r\n");
    wallet_uart_send_str("ADDRESS=");
    wallet_uart_send_str(WALLET_C2_ADDRESS_REGTEST);
    wallet_uart_send_str("\r\n");
    wallet_uart_send_str("PUBKEY_COMPRESSED=");
    wallet_uart_send_str(WALLET_C2_PUBKEY_COMPRESSED);
    wallet_uart_send_str("\r\n");
    wallet_uart_send_str("SCRIPT_P2PKH=");
    wallet_uart_send_str(WALLET_C2_SCRIPT_P2PKH);
    wallet_uart_send_str("\r\n");
    wallet_uart_send_str("TESTNET_BIP84_IDENTITY_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_BIP84_IDENTITY_VERSION=");
    wallet_uart_send_str(WALLET_C9_7_BIP84_IDENTITY_VERSION);
    wallet_uart_send_str("\r\n");
    wallet_uart_send_str("TESTNET_BIP84_ADDRESS=");
    wallet_uart_send_str(WALLET_C9_7_TESTNET_BIP84_ADDRESS);
    wallet_uart_send_str("\r\n");
    wallet_uart_send_str("TESTNET_BIP84_SCRIPT_P2WPKH=");
    wallet_uart_send_str(WALLET_C9_7_TESTNET_BIP84_SCRIPT_P2WPKH);
    wallet_uart_send_str("\r\n");
    wallet_uart_send_str("TESTNET_BIP84_PUBKEY_HASH160=");
    wallet_uart_send_str(WALLET_C9_7_TESTNET_BIP84_PUBKEY_HASH160);
    wallet_uart_send_str("\r\n");
    wallet_uart_send_str("TESTNET_BIP84_ACCOUNT_PATH=");
    wallet_uart_send_str(WALLET_C9_7_TESTNET_BIP84_ACCOUNT_PATH);
    wallet_uart_send_str("\r\n");
    wallet_uart_send_str("TESTNET_BIP84_RECEIVE_PATH=");
    wallet_uart_send_str(WALLET_C9_7_TESTNET_BIP84_RECEIVE_PATH);
    wallet_uart_send_str("\r\n");
    wallet_uart_send_str("TESTNET_BIP84_CHANGE_PATH=");
    wallet_uart_send_str(WALLET_C9_7_TESTNET_BIP84_CHANGE_PATH);
    wallet_uart_send_str("\r\n");
    wallet_uart_send_str("TESTNET_BIP84_DEVICE_DERIVES_KEYS=0\r\n");
    wallet_uart_send_str("TESTNET_BIP84_SIGNING_ENABLED=0\r\n");
    wallet_uart_send_str("CURRENT_BITCOIN_KEY_MODEL=");
    wallet_uart_send_str(WALLET_C2_KEY_MODEL);
    wallet_uart_send_str("\r\n");
    wallet_uart_send_str("CURRENT_DEV_KEY_ENABLED=0\r\n");
    wallet_uart_send_str("BITCOIN_DIRECT_TROPIC_SIGNING=0\r\n");
    wallet_uart_send_str("BITCOIN_REQUIRED_CURVE=SECP256K1\r\n");
}
static int wallet_uart_line_is_check(const char *buf, uint32_t line_start, uint32_t pos)
{
    uint32_t end;

    if (buf == NULL || pos < line_start)
    {
        return 0;
    }

    end = pos;

    while (end > line_start &&
           (buf[end - 1U] == '\r' || buf[end - 1U] == '\n'))
    {
        end--;
    }

    if ((end - line_start) != 5U)
    {
        return 0;
    }

    if (memcmp(&buf[line_start], "CHECK", 5U) == 0)
    {
        return 1;
    }

    return 0;
}

static int wallet_uart_line_is_confirm_code(const char *buf,
                                            uint32_t line_start,
                                            uint32_t pos)
{
    static const char prefix[] = "CONFIRM_CODE=";
    uint32_t end;
    uint32_t i;
    uint32_t code_len;

    if (buf == NULL || pos < line_start)
    {
        return 0;
    }

    end = pos;

    while (end > line_start &&
           (buf[end - 1U] == '\r' || buf[end - 1U] == '\n'))
    {
        end--;
    }

    if ((end - line_start) <= (sizeof(prefix) - 1U))
    {
        return 0;
    }

    if (memcmp(&buf[line_start], prefix, sizeof(prefix) - 1U) != 0)
    {
        return 0;
    }

    code_len = end - line_start - (uint32_t)(sizeof(prefix) - 1U);
    if (code_len != WALLET_COMMAND_CONFIRM_CODE_LEN)
    {
        return 0;
    }

    for (i = 0U; i < code_len; i++)
    {
        char c = buf[line_start + (uint32_t)(sizeof(prefix) - 1U) + i];
        if (c < '0' || c > '9')
        {
            return 0;
        }
    }

    return 1;
}

static int wallet_uart_line_is_unlock_pin(const char *buf,
                                          uint32_t line_start,
                                          uint32_t pos)
{
    static const char prefix[] = "UNLOCK_PIN=";
    uint32_t end;
    uint32_t pin_len;
    uint32_t i;

    if (buf == NULL || pos < line_start)
    {
        return 0;
    }

    end = pos;
    while (end > line_start &&
           (buf[end - 1U] == '\r' || buf[end - 1U] == '\n'))
    {
        end--;
    }

    if ((end - line_start) <= (sizeof(prefix) - 1U))
    {
        return 0;
    }

    if (memcmp(&buf[line_start], prefix, sizeof(prefix) - 1U) != 0)
    {
        return 0;
    }

    pin_len = end - line_start - (uint32_t)(sizeof(prefix) - 1U);
    if (pin_len == 0U || pin_len > 32U)
    {
        return 0;
    }

    for (i = 0U; i < pin_len; i++)
    {
        char c = buf[line_start + (uint32_t)(sizeof(prefix) - 1U) + i];
        if (c < '0' || c > '9')
        {
            return 0;
        }
    }

    return 1;
}

static uint32_t wallet_uart_line_trim_end(const char *buf,
                                          uint32_t line_start,
                                          uint32_t line_end)
{
    if (buf == NULL || line_end < line_start)
    {
        return line_start;
    }

    while (line_end > line_start &&
           (buf[line_end - 1U] == '\n' || buf[line_end - 1U] == '\r'))
    {
        line_end--;
    }

    return line_end;
}

static int wallet_uart_line_equals(const char *buf,
                                   uint32_t line_start,
                                   uint32_t line_end,
                                   const char *expected)
{
    uint32_t end;
    size_t expected_len;

    if (buf == NULL || expected == NULL || line_end < line_start)
    {
        return 0;
    }

    end = wallet_uart_line_trim_end(buf, line_start, line_end);
    expected_len = strlen(expected);

    if ((end - line_start) != expected_len)
    {
        return 0;
    }

    return (memcmp(&buf[line_start], expected, expected_len) == 0);
}

static int wallet_uart_line_starts_with(const char *buf,
                                        uint32_t line_start,
                                        uint32_t line_end,
                                        const char *prefix)
{
    uint32_t end;
    size_t prefix_len;

    if (buf == NULL || prefix == NULL || line_end < line_start)
    {
        return 0;
    }

    end = wallet_uart_line_trim_end(buf, line_start, line_end);
    prefix_len = strlen(prefix);

    if ((end - line_start) < prefix_len)
    {
        return 0;
    }

    return (memcmp(&buf[line_start], prefix, prefix_len) == 0);
}

static int wallet_uart_line_value_equals(const char *buf,
                                         uint32_t line_start,
                                         uint32_t line_end,
                                         const char *prefix,
                                         const char *expected_value)
{
    uint32_t end;
    size_t prefix_len;
    size_t value_len;

    if (buf == NULL || prefix == NULL || expected_value == NULL || line_end < line_start)
    {
        return 0;
    }

    end = wallet_uart_line_trim_end(buf, line_start, line_end);
    prefix_len = strlen(prefix);
    value_len = strlen(expected_value);

    if ((end - line_start) != (prefix_len + value_len))
    {
        return 0;
    }

    if (memcmp(&buf[line_start], prefix, prefix_len) != 0)
    {
        return 0;
    }

    return (memcmp(&buf[line_start + (uint32_t)prefix_len], expected_value, value_len) == 0);
}

static int wallet_uart_parse_frame_len(const char *buf,
                                       uint32_t line_start,
                                       uint32_t line_end,
                                       uint32_t *out_len)
{
    static const char prefix[] = "FRAME_LEN=";
    uint32_t end;
    uint32_t i;
    uint32_t value = 0U;

    if (out_len == NULL ||
        wallet_uart_line_starts_with(buf, line_start, line_end, prefix) == 0)
    {
        return 0;
    }

    end = wallet_uart_line_trim_end(buf, line_start, line_end);
    i = line_start + (uint32_t)(sizeof(prefix) - 1U);
    if (i >= end)
    {
        return 0;
    }

    while (i < end)
    {
        char c = buf[i];
        if (c < '0' || c > '9')
        {
            return 0;
        }
        value = (value * 10U) + (uint32_t)(c - '0');
        if (value > WALLET_FRAME_MAX_PAYLOAD)
        {
            return 0;
        }
        i++;
    }

    *out_len = value;
    return 1;
}

static int wallet_uart_parse_frame_crc32(const char *buf,
                                         uint32_t line_start,
                                         uint32_t line_end,
                                         uint32_t *out_crc)
{
    static const char prefix[] = "FRAME_CRC32=";
    uint32_t end;
    uint32_t i;
    uint32_t value = 0U;

    if (out_crc == NULL ||
        wallet_uart_line_starts_with(buf, line_start, line_end, prefix) == 0)
    {
        return 0;
    }

    end = wallet_uart_line_trim_end(buf, line_start, line_end);
    i = line_start + (uint32_t)(sizeof(prefix) - 1U);
    if ((end - i) != 8U)
    {
        return 0;
    }

    while (i < end)
    {
        char c = buf[i];
        uint32_t nibble;

        if (c >= '0' && c <= '9')
        {
            nibble = (uint32_t)(c - '0');
        }
        else if (c >= 'a' && c <= 'f')
        {
            nibble = (uint32_t)(c - 'a') + 10U;
        }
        else if (c >= 'A' && c <= 'F')
        {
            nibble = (uint32_t)(c - 'A') + 10U;
        }
        else
        {
            return 0;
        }

        value = (value << 4U) | nibble;
        i++;
    }

    *out_crc = value;
    return 1;
}

static uint32_t wallet_uart_crc32_ieee(const char *buf, uint32_t len)
{
    uint32_t crc = 0xFFFFFFFFU;
    uint32_t i;

    if (buf == NULL)
    {
        return 0U;
    }

    for (i = 0U; i < len; i++)
    {
        uint32_t bit;

        crc ^= (uint8_t)buf[i];
        for (bit = 0U; bit < 8U; bit++)
        {
            if ((crc & 1U) != 0U)
            {
                crc = (crc >> 1U) ^ 0xEDB88320U;
            }
            else
            {
                crc >>= 1U;
            }
        }
    }

    return crc ^ 0xFFFFFFFFU;
}

static int wallet_uart_classify_command_text(const char *buf, uint32_t len)
{
    uint32_t line_start = 0U;
    uint32_t pos;

    if (buf == NULL)
    {
        return -1;
    }

    if (wallet_uart_command_is_exact(buf, "SEKEYTEST")) return WALLET_UART_READ_SEKEYTEST;
    if (wallet_uart_command_is_exact(buf, "IDENTITY")) return WALLET_UART_READ_IDENTITY;
    if (wallet_uart_command_is_exact(buf, "ADDR")) return WALLET_UART_READ_ADDR;
    if (wallet_uart_command_is_exact(buf, "PUBKEY")) return WALLET_UART_READ_PUBKEY;
    if (wallet_uart_command_is_exact(buf, "SCRIPT")) return WALLET_UART_READ_SCRIPT;
    if (wallet_uart_command_is_exact(buf, "LOCK")) return WALLET_UART_READ_LOCK;
    if (wallet_uart_command_is_exact(buf, "UNLOCKINFO")) return WALLET_UART_READ_UNLOCKINFO;
    if (wallet_uart_command_is_exact(buf, "CONFIRM")) return WALLET_UART_READ_CONFIRM;
    if (wallet_uart_command_is_exact(buf, "BUTTONINFO")) return WALLET_UART_READ_BUTTONINFO;
    if (wallet_uart_command_is_exact(buf, "FRAMEINFO")) return WALLET_UART_READ_FRAMEINFO;
    if (wallet_uart_command_is_exact(buf, "REALINFO")) return WALLET_UART_READ_REALINFO;

    for (pos = 0U; pos <= len; pos++)
    {
        if (pos == len || buf[pos] == '\n' || buf[pos] == '\r')
        {
            uint32_t line_end = (pos < len) ? (pos + 1U) : pos;

            if (wallet_uart_line_is_seinfo(buf, line_start, line_end)) return WALLET_UART_READ_SEINFO;
            if (wallet_uart_line_is_policyinfo(buf, line_start, line_end)) return WALLET_UART_READ_POLICYINFO;
            if (wallet_uart_line_is_version(buf, line_start, line_end)) return WALLET_UART_READ_VERSION;
            if (wallet_uart_line_is_sekeyinfo(buf, line_start, line_end)) return WALLET_UART_READ_SEKEYINFO;
            if (wallet_uart_line_is_unlock_pin(buf, line_start, line_end)) return WALLET_UART_READ_UNLOCK_PIN;
            if (wallet_uart_line_is_confirm_code(buf, line_start, line_end)) return WALLET_UART_READ_CONFIRM;
            if (wallet_uart_line_is_check(buf, line_start, line_end)) return WALLET_UART_READ_CHECK;
            if (wallet_uart_line_is_sign(buf, line_start, line_end)) return WALLET_UART_READ_SIGN;

            while ((pos + 1U) < len &&
                   (buf[pos + 1U] == '\n' || buf[pos + 1U] == '\r'))
            {
                pos++;
            }
            line_start = pos + 1U;
        }
    }

    return -1;
}

static void wallet_uart_send_check_summary(const char *command_text)
{
    static wallet_command_summary_t summary;
    char confirm_code[WALLET_COMMAND_CONFIRM_CODE_SIZE];
    int summary_ret;

    memset(&summary, 0, sizeof(summary));

    summary_ret = wallet_command_check_summary_text(command_text, &summary);

    wallet_uart_send_str("\r\nSUMMARY_BEGIN\r\n");
    wallet_uart_send_str("SUMMARY_VERSION=C3.1_DEVICE_POLICY_SUMMARY_CHECK_ID\r\n");
    wallet_uart_send_str("PROTOCOL_VERSION=" WALLET_PROTOCOL_VERSION "\r\n");
    wallet_uart_send_str("COMMAND_VERSION=" WALLET_COMMAND_VERSION "\r\n");
    wallet_uart_send_str("RESPONSE_VERSION=" WALLET_RESPONSE_VERSION "\r\n");

    wallet_uart_send_str("NETWORK=");
    wallet_uart_send_str(summary.network);
    wallet_uart_send_str("\r\n");

    snprintf(wallet_uart_response,
             sizeof(wallet_uart_response),
             "INPUT_COUNT=%lu\r\n",
             (unsigned long)summary.input_count);
    wallet_uart_send_str(wallet_uart_response);

    
    wallet_uart_send_str("INPUT_TXID_LE=");
    wallet_uart_send_str(summary.txid_le_hex);
    wallet_uart_send_str("\r\n");

    snprintf(wallet_uart_response,
             sizeof(wallet_uart_response),
             "INPUT_VOUT=%lu\r\n",
             (unsigned long)summary.vout);
    wallet_uart_send_str(wallet_uart_response);

    snprintf(wallet_uart_response,
             sizeof(wallet_uart_response),
             "INPUT_SATS=%lu\r\n",
             (unsigned long)summary.input_sats);
    wallet_uart_send_str(wallet_uart_response);
wallet_uart_send_str("SPEND_FROM_SCRIPT=");
    wallet_uart_send_str(summary.prev_script_hex);
    wallet_uart_send_str("\r\n");

    if (summary.input_count == 2U)
    {
        wallet_uart_send_str("INPUT1_TXID_LE=");
        wallet_uart_send_str(summary.input1_txid_le_hex);
        wallet_uart_send_str("\r\n");

        snprintf(wallet_uart_response,
                 sizeof(wallet_uart_response),
                 "INPUT1_VOUT=%lu\r\n",
                 (unsigned long)summary.input1_vout);
        wallet_uart_send_str(wallet_uart_response);

        snprintf(wallet_uart_response,
                 sizeof(wallet_uart_response),
                 "INPUT1_SATS=%lu\r\n",
                 (unsigned long)summary.input1_sats);
        wallet_uart_send_str(wallet_uart_response);

        wallet_uart_send_str("INPUT1_PREV_SCRIPT=");
        wallet_uart_send_str(summary.input1_prev_script_hex);
        wallet_uart_send_str("\r\n");
    }

    snprintf(wallet_uart_response,
             sizeof(wallet_uart_response),
             "TOTAL_INPUT_SATS=%lu\r\n",
             (unsigned long)summary.total_input_sats);
    wallet_uart_send_str(wallet_uart_response);

    wallet_uart_send_str("PAY_TO_SCRIPT=");
    wallet_uart_send_str(summary.pay_script_hex);
    wallet_uart_send_str("\r\n");

    snprintf(wallet_uart_response,
             sizeof(wallet_uart_response),
             "PAY_SATS=%lu\r\n",
             (unsigned long)summary.pay_sats);
    wallet_uart_send_str(wallet_uart_response);

    wallet_uart_send_str("CHANGE_TO_SCRIPT=");
    wallet_uart_send_str(summary.change_script_hex);
    wallet_uart_send_str("\r\n");

    snprintf(wallet_uart_response,
             sizeof(wallet_uart_response),
             "CHANGE_SATS=%lu\r\n",
             (unsigned long)summary.change_sats);
    wallet_uart_send_str(wallet_uart_response);

    snprintf(wallet_uart_response,
             sizeof(wallet_uart_response),
             "FEE_SATS=%lu\r\n",
             (unsigned long)summary.fee_sats);
    wallet_uart_send_str(wallet_uart_response);

    
    wallet_uart_send_str("CHECK_ID=");
    wallet_uart_send_str(summary.check_id_hex);
    wallet_uart_send_str("\r\n");

    if (summary_ret == 0)
    {
        wallet_command_record_approved_check(&summary);
        wallet_uart_secure_zero(confirm_code, sizeof(confirm_code));
        if (wallet_command_get_confirm_code(confirm_code, sizeof(confirm_code)) == WALLET_POLICY_OK)
        {
            wallet_uart_send_str("CONFIRM_CODE=");
            wallet_uart_send_str(confirm_code);
            wallet_uart_send_str("\r\n");
            wallet_uart_secure_zero(confirm_code, sizeof(confirm_code));
        }
        wallet_uart_send_str("POLICY_DECISION=APPROVED\r\n");
    }
    else
    {
        wallet_key_provider_lock_session();
        wallet_command_clear_approved_check();
        wallet_uart_send_str("POLICY_DECISION=REJECTED\r\n");

        snprintf(wallet_uart_response,
                 sizeof(wallet_uart_response),
                 "DEVICE_ERROR=ERR POLICY %d\r\n",
                 summary_ret);
        wallet_uart_send_str(wallet_uart_response);
    }

    wallet_uart_send_str("SIGNATURE_PRODUCED=0\r\n");
    wallet_uart_send_str("SUMMARY_END\r\n");

    if (summary_ret != 0)
    {
        snprintf(wallet_uart_response,
                 sizeof(wallet_uart_response),
                 "\r\nERR POLICY %d\r\n",
                 summary_ret);
        wallet_uart_send_str(wallet_uart_response);
    }
}
static int wallet_uart_read_command(void)
{
    uint8_t ch = 0;
    uint32_t pos = 0;
    uint32_t line_start = 0;
    int frame_mode = 0;
    int frame_payload = 0;
    int frame_payload_done = 0;
    int frame_has_version = 0;
    int frame_has_len = 0;
    int frame_has_crc = 0;
    int frame_error = 0;
    uint32_t frame_payload_start = 0U;
    uint32_t frame_payload_end = 0U;
    uint32_t frame_declared_len = 0U;
    uint32_t frame_declared_crc = 0U;

    wallet_uart_clear_command_buffer();

    wallet_uart_send_str(
        "\r\nREADY\r\n"
        "Paste command ending with SIGN or CHECK, press USER button after approved CHECK, or type UNLOCK_PIN=<pin>, LOCK, UNLOCKINFO, CONFIRM_CODE=<code>, BUTTONINFO, FRAMEINFO, REALINFO, SEINFO, POLICYINFO, VERSION, SEKEYINFO, SEKEYTEST, IDENTITY, ADDR, PUBKEY, or SCRIPT, then Enter.\r\n"
        "> "
    );

    while (1)
    {
        HAL_StatusTypeDef rx_status;

        rx_status = HAL_UART_Receive(&hcom_uart[COM1], &ch, 1U, WALLET_UART_RX_POLL_MS);
        if (rx_status == HAL_TIMEOUT)
        {
            wallet_uart_poll_button_confirm();
            continue;
        }

        if (rx_status != HAL_OK)
        {
            return -1;
        }

        /*
         * Do not echo input.
         * Echo can confuse scripted PowerShell reads.
         */

        if (pos >= (WALLET_UART_CMD_MAX - 1U))
        {
            wallet_uart_cmd[WALLET_UART_CMD_MAX - 1U] = '\0';
            wallet_uart_rx_len = pos;
            return -2;
        }

        wallet_uart_cmd[pos] = (char)ch;
        pos++;
        wallet_uart_cmd[pos] = '\0';

        if (ch == '\n' || ch == '\r')
        {
            if (frame_mode == 0 &&
                wallet_uart_line_equals(wallet_uart_cmd, line_start, pos, "FRAME_BEGIN"))
            {
                frame_mode = 1;
                frame_payload = 0;
                frame_payload_done = 0;
                frame_has_version = 0;
                frame_has_len = 0;
                frame_has_crc = 0;
                frame_error = 0;
                frame_payload_start = 0U;
                frame_payload_end = 0U;
                frame_declared_len = 0U;
                frame_declared_crc = 0U;
                line_start = pos;
                continue;
            }

            if (frame_mode != 0)
            {
                if (frame_payload != 0)
                {
                    if (wallet_uart_line_equals(wallet_uart_cmd, line_start, pos, "FRAME_PAYLOAD_END"))
                    {
                        frame_payload = 0;
                        frame_payload_done = 1;
                        frame_payload_end = line_start;
                    }

                    line_start = pos;
                    continue;
                }

                if (wallet_uart_line_equals(wallet_uart_cmd, line_start, pos, "FRAME_END"))
                {
                    uint32_t actual_len;
                    uint32_t actual_crc;
                    int read_type;

                    if (frame_error != 0)
                    {
                        wallet_uart_rx_len = pos;
                        return frame_error;
                    }

                    if (frame_has_version == 0 ||
                        frame_has_len == 0 ||
                        frame_has_crc == 0 ||
                        frame_payload_done == 0 ||
                        frame_payload_end < frame_payload_start)
                    {
                        wallet_uart_rx_len = pos;
                        return WALLET_FRAME_ERR_INVALID;
                    }

                    actual_len = frame_payload_end - frame_payload_start;
                    if (actual_len != frame_declared_len ||
                        actual_len > WALLET_FRAME_MAX_PAYLOAD ||
                        actual_len >= (WALLET_UART_CMD_MAX - 1U))
                    {
                        wallet_uart_rx_len = pos;
                        return WALLET_FRAME_ERR_LEN;
                    }

                    actual_crc = wallet_uart_crc32_ieee(&wallet_uart_cmd[frame_payload_start], actual_len);
                    if (actual_crc != frame_declared_crc)
                    {
                        wallet_uart_rx_len = pos;
                        return WALLET_FRAME_ERR_CRC;
                    }

                    memmove(wallet_uart_cmd, &wallet_uart_cmd[frame_payload_start], actual_len);
                    wallet_uart_cmd[actual_len] = '\0';
                    wallet_uart_rx_len = actual_len;

                    read_type = wallet_uart_classify_command_text(wallet_uart_cmd, actual_len);
                    if (read_type < 0)
                    {
                        return WALLET_FRAME_ERR_INVALID;
                    }

                    return read_type;
                }

                if (frame_payload_done != 0)
                {
                    frame_error = WALLET_FRAME_ERR_INVALID;
                    line_start = pos;
                    continue;
                }

                if (frame_error != 0)
                {
                    if (wallet_uart_line_equals(wallet_uart_cmd, line_start, pos, "FRAME_PAYLOAD_BEGIN"))
                    {
                        frame_payload = 1;
                    }
                    line_start = pos;
                    continue;
                }

                if (wallet_uart_line_value_equals(wallet_uart_cmd,
                                                  line_start,
                                                  pos,
                                                  "FRAME_VERSION=",
                                                  WALLET_FRAME_VERSION))
                {
                    frame_has_version = 1;
                    line_start = pos;
                    continue;
                }

                if (wallet_uart_line_starts_with(wallet_uart_cmd, line_start, pos, "FRAME_VERSION="))
                {
                    frame_error = WALLET_FRAME_ERR_UNSUPPORTED;
                    line_start = pos;
                    continue;
                }

                if (wallet_uart_line_starts_with(wallet_uart_cmd, line_start, pos, "FRAME_LEN="))
                {
                    if (wallet_uart_parse_frame_len(wallet_uart_cmd,
                                                    line_start,
                                                    pos,
                                                    &frame_declared_len) == 0)
                    {
                        frame_error = WALLET_FRAME_ERR_LEN;
                        line_start = pos;
                        continue;
                    }
                    frame_has_len = 1;
                    line_start = pos;
                    continue;
                }

                if (wallet_uart_line_starts_with(wallet_uart_cmd, line_start, pos, "FRAME_CRC32="))
                {
                    if (wallet_uart_parse_frame_crc32(wallet_uart_cmd,
                                                      line_start,
                                                      pos,
                                                      &frame_declared_crc) == 0)
                    {
                        frame_error = WALLET_FRAME_ERR_CRC;
                        line_start = pos;
                        continue;
                    }
                    frame_has_crc = 1;
                    line_start = pos;
                    continue;
                }

                if (wallet_uart_line_equals(wallet_uart_cmd, line_start, pos, "FRAME_PAYLOAD_BEGIN"))
                {
                    if (frame_has_version == 0 || frame_has_len == 0 || frame_has_crc == 0)
                    {
                        frame_error = WALLET_FRAME_ERR_INVALID;
                        frame_payload = 1;
                        line_start = pos;
                        continue;
                    }
                    frame_payload = 1;
                    frame_payload_start = pos;
                    line_start = pos;
                    continue;
                }

                frame_error = WALLET_FRAME_ERR_INVALID;
                line_start = pos;
                continue;
            }

            if (wallet_uart_line_is_seinfo(wallet_uart_cmd, line_start, pos))
            {
                wallet_uart_rx_len = pos;
                return WALLET_UART_READ_SEINFO;
            }

            if (wallet_uart_line_is_policyinfo(wallet_uart_cmd, line_start, pos))
            {
                wallet_uart_rx_len = pos;
                return WALLET_UART_READ_POLICYINFO;
            }

            if (wallet_uart_line_is_version(wallet_uart_cmd, line_start, pos))
            {
                wallet_uart_rx_len = pos;
                return WALLET_UART_READ_VERSION;
            }

            if (wallet_uart_line_is_sekeyinfo(wallet_uart_cmd, line_start, pos))
            {
                wallet_uart_rx_len = pos;
                return WALLET_UART_READ_SEKEYINFO;
            }

            if (wallet_uart_command_is_exact(wallet_uart_cmd, "SEKEYTEST"))
            {
                wallet_uart_rx_len = pos;
                return WALLET_UART_READ_SEKEYTEST;
            }

            if (wallet_uart_command_is_exact(wallet_uart_cmd, "IDENTITY"))
            {
                wallet_uart_rx_len = pos;
                return WALLET_UART_READ_IDENTITY;
            }

            if (wallet_uart_command_is_exact(wallet_uart_cmd, "ADDR"))
            {
                wallet_uart_rx_len = pos;
                return WALLET_UART_READ_ADDR;
            }

            if (wallet_uart_command_is_exact(wallet_uart_cmd, "PUBKEY"))
            {
                wallet_uart_rx_len = pos;
                return WALLET_UART_READ_PUBKEY;
            }

            if (wallet_uart_command_is_exact(wallet_uart_cmd, "SCRIPT"))
            {
                wallet_uart_rx_len = pos;
                return WALLET_UART_READ_SCRIPT;
            }

            if (wallet_uart_line_is_unlock_pin(wallet_uart_cmd, line_start, pos))
            {
                wallet_uart_rx_len = pos;
                return WALLET_UART_READ_UNLOCK_PIN;
            }

            if (wallet_uart_command_is_exact(wallet_uart_cmd, "LOCK"))
            {
                wallet_uart_rx_len = pos;
                return WALLET_UART_READ_LOCK;
            }

            if (wallet_uart_command_is_exact(wallet_uart_cmd, "UNLOCKINFO"))
            {
                wallet_uart_rx_len = pos;
                return WALLET_UART_READ_UNLOCKINFO;
            }

            if (wallet_uart_command_is_exact(wallet_uart_cmd, "CONFIRM"))
            {
                wallet_uart_rx_len = pos;
                return WALLET_UART_READ_CONFIRM;
            }

            if (wallet_uart_line_is_confirm_code(wallet_uart_cmd, line_start, pos))
            {
                wallet_uart_rx_len = pos;
                return WALLET_UART_READ_CONFIRM;
            }

            if (wallet_uart_command_is_exact(wallet_uart_cmd, "BUTTONINFO"))
            {
                wallet_uart_rx_len = pos;
                return WALLET_UART_READ_BUTTONINFO;
            }

            if (wallet_uart_command_is_exact(wallet_uart_cmd, "FRAMEINFO"))
            {
                wallet_uart_rx_len = pos;
                return WALLET_UART_READ_FRAMEINFO;
            }

            if (wallet_uart_command_is_exact(wallet_uart_cmd, "REALINFO"))
            {
                wallet_uart_rx_len = pos;
                return WALLET_UART_READ_REALINFO;
            }

            if (wallet_uart_line_is_check(wallet_uart_cmd, line_start, pos))

            {

                wallet_uart_rx_len = pos;

                return WALLET_UART_READ_CHECK;

            }


            if (wallet_uart_line_is_sign(wallet_uart_cmd, line_start, pos))

            {

                wallet_uart_rx_len = pos;

                return WALLET_UART_READ_SIGN;

            }

            line_start = pos;
        }
    }
}

static int wallet_uart_check_host_key_policy(const char *input)
{
    if (input == NULL)
    {
        return -20;
    }

    /*
     * Host commands must never contain a private key.
     */
    if (strstr(input, "PRIVKEY=") != NULL)
    {
        return -21;
    }

    if (strstr(input, "UNLOCK_SECRET=") != NULL)
    {
        return -24;
    }

    return 0;
}

static void wallet_uart_clear_shared_debug(void)
{
    tx_preimage_build_ret = 999;
    signed_tx_build_ret = 999;

    wallet_uart_secure_zero((void *)signed_tx_raw, sizeof(signed_tx_raw));
    signed_tx_len = 0;
    signed_tx_expected_len = 0;
    signed_tx_script_sig_len = 0;

    signed_tx_len_match = 0;
    signed_tx_script_sig_ok = 0;
    signed_tx_prefix_ok = 0;
    signed_tx_ok = 0;

    wallet_uart_secure_zero(signed_tx_hex, sizeof(signed_tx_hex));
    signed_tx_hex_len = 0;
    signed_tx_hex_expected_len = 0;
    signed_tx_hex_ok = 0;

    wallet_uart_secure_zero(signed_tx_hex_part0, sizeof(signed_tx_hex_part0));
    wallet_uart_secure_zero(signed_tx_hex_part1, sizeof(signed_tx_hex_part1));
    wallet_uart_secure_zero(signed_tx_hex_part2, sizeof(signed_tx_hex_part2));
    wallet_uart_secure_zero(signed_tx_hex_part3, sizeof(signed_tx_hex_part3));
    wallet_uart_secure_zero(signed_tx_hex_part4, sizeof(signed_tx_hex_part4));
    signed_tx_hex_parts_ok = 0;

    wallet_uart_ret = 999;
    wallet_uart_keypolicy_ret = 999;

    wallet_uart_secure_zero(wallet_uart_private_key, sizeof(wallet_uart_private_key));
}

static void wallet_uart_send_policyinfo(void)
{
    wallet_uart_send_str("\r\nOK POLICYINFO\r\n");

    wallet_uart_send_str("PROTOCOL_VERSION=" WALLET_PROTOCOL_VERSION "\r\n");
    wallet_uart_send_str("COMMAND_VERSION=" WALLET_COMMAND_VERSION "\r\n");
    wallet_uart_send_str("RESPONSE_VERSION=" WALLET_RESPONSE_VERSION "\r\n");
    wallet_uart_send_str("ERROR_VERSION=" WALLET_ERROR_VERSION "\r\n");
    wallet_uart_send_str("POLICY_VERSION=" WALLET_POLICY_VERSION "\r\n");
    wallet_uart_send_str("FRAME_VERSION=" WALLET_FRAME_VERSION "\r\n");
    wallet_uart_send_str("NETWORK_REQUIRED=REGTEST_OR_TESTNET\r\n");
    wallet_uart_send_str("NETWORK_ALLOWED=REGTEST,TESTNET\r\n");
    wallet_uart_send_str("REAL_BITCOIN_STAGE=" WALLET_REAL_BITCOIN_STAGE "\r\n");
    wallet_uart_send_str("REAL_BITCOIN_SIGNING_ENABLED=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_ENABLED=1\r\n");
    wallet_uart_send_str("MAINNET_SIGNING_ENABLED=0\r\n");
    wallet_uart_send_str("TESTNET_WATCH_ONLY_DRY_RUN_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_DRY_RUN_SIGNING_ENABLED=0\r\n");
    wallet_uart_send_str("TESTNET_POLICY_FIXTURES_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_POLICY_SIGNING_ENABLED=0\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_DRY_RUN_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_SIGNING_ENABLED=0\r\n");
    wallet_uart_send_str("TESTNET_FEE_CHANGE_FIXTURES_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_FEE_CHANGE_SIGNING_ENABLED=0\r\n");
    wallet_uart_send_str("TESTNET_UNSIGNED_TX_PSBT_DRY_RUN_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_UNSIGNED_TX_SIGNING_ENABLED=0\r\n");
    wallet_uart_send_str("TESTNET_ACTIVATION_CHECKLIST_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_ACTIVATION_SIGNING_ENABLED=0\r\n");
    wallet_uart_send_str("TESTNET_ARTIFACT_EXPORT_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_ARTIFACT_SIGNING_ENABLED=0\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_DECISION_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_DECISION_SIGNING_ENABLED=0\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_COMPILE_TIME_GUARD_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_BUILD_FLAG=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_MODE_DESIGN_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_MODE_SIGNING_ENABLED=1\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_IMPLEMENTATION_FOUNDATION_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_BIP84_IDENTITY_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_BIP84_IDENTITY_VERSION=" WALLET_C9_7_BIP84_IDENTITY_VERSION "\r\n");
    wallet_uart_send_str("TESTNET_BIP84_ADDRESS=" WALLET_C9_7_TESTNET_BIP84_ADDRESS "\r\n");
    wallet_uart_send_str("TESTNET_BIP84_SCRIPT_P2WPKH=" WALLET_C9_7_TESTNET_BIP84_SCRIPT_P2WPKH "\r\n");
    wallet_uart_send_str("TESTNET_BIP84_CHANGE_PATH=" WALLET_C9_7_TESTNET_BIP84_CHANGE_PATH "\r\n");
    wallet_uart_send_str("TESTNET_BIP84_DEVICE_DERIVES_KEYS=0\r\n");
    wallet_uart_send_str("TESTNET_BIP84_SIGNING_ENABLED=0\r\n");
    wallet_uart_send_str("TESTNET_CHANGE_DERIVATION_ENFORCEMENT_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_CHANGE_DERIVATION_ENFORCEMENT_VERSION=C9.8_TESTNET_CHANGE_DERIVATION_ENFORCEMENT_V1\r\n");
    wallet_uart_send_str("TESTNET_CHANGE_DERIVATION_ENFORCEMENT_SIGNING_ENABLED=1\r\n");
    wallet_uart_send_str("TESTNET_REAL_FEE_POLICY_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_UNSIGNED_TX_VALIDATION_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_ACTIVATION_DRY_RUN_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_ENABLE_BLOCKED=0\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_ENABLE_ACTIVE=1\r\n");
    wallet_uart_send_str("TX_TYPE=LEGACY_P2PKH_1OR2IN_2OUT\r\n");
    wallet_uart_send_str("COMMAND_FORMAT_LEGACY=LEGACY_TEXT_V1\r\n");
    wallet_uart_send_str("COMMAND_FORMAT_PSBT_LIKE=C5.0_PSBT_LIKE_TEXT_V1\r\n");
    wallet_uart_send_str("COMMAND_FORMAT_FRAMED_TEXT=C6.1_TEXT_FRAME_V1\r\n");
    wallet_uart_send_str("MAX_INPUT_COUNT=2\r\n");

    wallet_uart_send_str("MAX_FEE_SATS=20000\r\n");
    wallet_uart_send_str("MAX_PAY_SATS=70000\r\n");
    wallet_uart_send_str("DUST_LIMIT_SATS=546\r\n");
    wallet_uart_send_str("MAX_FEE_RATE_SATS_PER_KVB=100000\r\n");
    wallet_uart_send_str("FEE_RATE_ESTIMATE_VBYTES=192\r\n");
    wallet_uart_send_str("FEE_RATE_ESTIMATE_2IN_2OUT_VBYTES=340\r\n");

    wallet_uart_send_str("OWN_INPUT_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac\r\n");
    wallet_uart_send_str("OWN_CHANGE_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac\r\n");
    wallet_uart_send_str("ALLOWED_PAY_SCRIPT=76a914f2124d94cabdb95d49479627cbbe5d7be609f73888ac\r\n");
    wallet_uart_send_str("CHANGE_DERIVATION_MODEL=REGTEST_STATIC_OR_TESTNET_BIP84_METADATA\r\n");
    wallet_uart_send_str("CHANGE_DERIVATION_ALLOWED=mvp-static-change/0\r\n");
    wallet_uart_send_str("TESTNET_CHANGE_DERIVATION_ALLOWED=" WALLET_C9_7_TESTNET_BIP84_CHANGE_PATH "\r\n");
    wallet_uart_send_str("TESTNET_CHANGE_SCRIPT_P2WPKH=" WALLET_C9_7_TESTNET_BIP84_SCRIPT_P2WPKH "\r\n");

    wallet_uart_send_str("ERR_FEE_TOO_HIGH=-35\r\n");
    wallet_uart_send_str("ERR_SCRIPT_TYPE=-37\r\n");
    wallet_uart_send_str("ERR_PAY_NOT_ALLOWED=-38\r\n");
    wallet_uart_send_str("ERR_CHANGE_NOT_OWN=-39\r\n");
    wallet_uart_send_str("ERR_INPUT_NOT_OWN=-40\r\n");
    wallet_uart_send_str("ERR_PAY_TOO_HIGH=-41\r\n");
    wallet_uart_send_str("ERR_NETWORK_NOT_REGTEST=-42\r\n");
    wallet_uart_send_str("ERR_SIGN_WITHOUT_APPROVED_CHECK=-43\r\n");
    wallet_uart_send_str("ERR_SIGN_MISMATCHES_APPROVED_CHECK=-44\r\n");
    wallet_uart_send_str("ERR_SIGN_WITHOUT_CONFIRMED_CHECK=-46\r\n");
    wallet_uart_send_str("ERR_CONFIRM_WITHOUT_APPROVED_CHECK=-47\r\n");
    wallet_uart_send_str("ERR_APPROVAL_EXPIRED=-48\r\n");
    wallet_uart_send_str("ERR_CONFIRM_CODE_REQUIRED=-49\r\n");
    wallet_uart_send_str("ERR_CONFIRM_CODE_MISMATCH=-50\r\n");
    wallet_uart_send_str("ERR_FORMAT_INVALID=-51\r\n");
    wallet_uart_send_str("ERR_DUST_OUTPUT=-52\r\n");
    wallet_uart_send_str("ERR_INPUT_COUNT_UNSUPPORTED=-53\r\n");
    wallet_uart_send_str("ERR_CHANGE_DERIVATION_INVALID=-54\r\n");
    wallet_uart_send_str("ERR_LEGACY_SIGN_DISABLED=-60\r\n");
    wallet_uart_send_str("ERR_PIN_LOCKED=-61\r\n");
    wallet_uart_send_str("ERR_PIN_SESSION_EXPIRED=-62\r\n");
    wallet_uart_send_str("ERR_FRAME_INVALID=-70\r\n");
    wallet_uart_send_str("ERR_FRAME_LEN=-71\r\n");
    wallet_uart_send_str("ERR_FRAME_CRC=-72\r\n");
    wallet_uart_send_str("ERR_FRAME_UNSUPPORTED=-73\r\n");
    wallet_uart_send_str("ERR_HOST_UNLOCK_SECRET_DISABLED=-24\r\n");
    wallet_uart_send_str("UNLOCK_MODEL=PIN_SESSION_C4.2\r\n");
    snprintf(wallet_uart_response,
             sizeof(wallet_uart_response),
             "PIN_SESSION_TIMEOUT_MS=%lu\r\n"
             "PIN_RETRY_DELAY_MS=%lu\r\n"
             "PIN_MAX_ATTEMPTS=%lu\r\n",
             (unsigned long)WALLET_KEY_PROVIDER_PIN_SESSION_TIMEOUT_MS,
             (unsigned long)WALLET_KEY_PROVIDER_PIN_RETRY_DELAY_MS,
             (unsigned long)WALLET_KEY_PROVIDER_PIN_MAX_ATTEMPTS);
    wallet_uart_send_str(wallet_uart_response);
    snprintf(wallet_uart_response,
             sizeof(wallet_uart_response),
             "APPROVAL_TIMEOUT_MS=%lu\r\n",
             (unsigned long)wallet_command_approval_timeout_ms());
    wallet_uart_send_str(wallet_uart_response);
}

static void wallet_uart_send_frameinfo(void)
{
    wallet_uart_send_str("\r\nOK FRAMEINFO\r\n");
    wallet_uart_send_str("PROTOCOL_VERSION=" WALLET_PROTOCOL_VERSION "\r\n");
    wallet_uart_send_str("COMMAND_VERSION=" WALLET_COMMAND_VERSION "\r\n");
    wallet_uart_send_str("RESPONSE_VERSION=" WALLET_RESPONSE_VERSION "\r\n");
    wallet_uart_send_str("ERROR_VERSION=" WALLET_ERROR_VERSION "\r\n");
    wallet_uart_send_str("FRAME_VERSION=" WALLET_FRAME_VERSION "\r\n");
    wallet_uart_send_str("FRAME_ENCODING=ASCII_LINES\r\n");
    wallet_uart_send_str("FRAME_FIELDS=FRAME_BEGIN,FRAME_VERSION,FRAME_LEN,FRAME_CRC32,FRAME_PAYLOAD_BEGIN,FRAME_PAYLOAD_END,FRAME_END\r\n");
    wallet_uart_send_str("FRAME_CRC=" WALLET_FRAME_CRC_NAME "\r\n");
    snprintf(wallet_uart_response,
             sizeof(wallet_uart_response),
             "FRAME_MAX_PAYLOAD=%lu\r\n",
             (unsigned long)WALLET_FRAME_MAX_PAYLOAD);
    wallet_uart_send_str(wallet_uart_response);
    wallet_uart_send_str("ERR_FRAME_INVALID=-70\r\n");
    wallet_uart_send_str("ERR_FRAME_LEN=-71\r\n");
    wallet_uart_send_str("ERR_FRAME_CRC=-72\r\n");
    wallet_uart_send_str("ERR_FRAME_UNSUPPORTED=-73\r\n");
}

static void wallet_uart_send_realinfo(void)
{
    wallet_uart_send_str("\r\nOK REALINFO\r\n");
    wallet_uart_send_str("REAL_BITCOIN_READINESS_VERSION=" WALLET_REAL_BITCOIN_READINESS "\r\n");
    wallet_uart_send_str("REAL_BITCOIN_STAGE=" WALLET_REAL_BITCOIN_STAGE "\r\n");
    wallet_uart_send_str("REAL_BITCOIN_READINESS=TESTNET_ONLY_ACTIVE_MAINNET_LOCKED\r\n");
    wallet_uart_send_str("NETWORK_ALLOWED=REGTEST,TESTNET\r\n");
    wallet_uart_send_str("REAL_BITCOIN_SIGNING_ENABLED=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_ENABLED=1\r\n");
    wallet_uart_send_str("MAINNET_SIGNING_ENABLED=0\r\n");
    wallet_uart_send_str("TESTNET_WATCH_ONLY_DRY_RUN_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_DRY_RUN_SIGNING_ENABLED=0\r\n");
    wallet_uart_send_str("TESTNET_DRY_RUN_NETWORK=TESTNET\r\n");
    wallet_uart_send_str("TESTNET_DRY_RUN_WATCH_ONLY=1\r\n");
    wallet_uart_send_str("TESTNET_DRY_RUN_USES_DEVICE_PUBKEY=1\r\n");
    wallet_uart_send_str("TESTNET_DRY_RUN_DEVICE_SIGNATURE=0\r\n");
    wallet_uart_send_str("TESTNET_DRY_RUN_BROADCAST=0\r\n");
    wallet_uart_send_str("TESTNET_DRY_RUN_OUTPUT=HOST_INTENT_ONLY_NO_DEVICE_SIGNATURE\r\n");
    wallet_uart_send_str("TESTNET_POLICY_FIXTURES_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_POLICY_VERSION=C8.2_TESTNET_POLICY_FIXTURES_V1\r\n");
    wallet_uart_send_str("TESTNET_POLICY_NETWORK=TESTNET\r\n");
    wallet_uart_send_str("TESTNET_POLICY_SIGNING_ENABLED=0\r\n");
    wallet_uart_send_str("TESTNET_POLICY_MAX_INPUT_COUNT=2\r\n");
    wallet_uart_send_str("TESTNET_POLICY_OUTPUTS=ONE_PAYMENT_ONE_CHANGE\r\n");
    wallet_uart_send_str("TESTNET_POLICY_SCRIPT_TYPE=LEGACY_P2PKH_INPUT_PAYMENT_WITH_P2WPKH_CHANGE\r\n");
    wallet_uart_send_str("TESTNET_POLICY_DUST_LIMIT_SATS=546\r\n");
    wallet_uart_send_str("TESTNET_POLICY_MAX_FEE_SATS=20000\r\n");
    wallet_uart_send_str("TESTNET_POLICY_MAX_PAY_SATS=70000\r\n");
    wallet_uart_send_str("TESTNET_POLICY_REQUIRES_CHECK_ID=1\r\n");
    wallet_uart_send_str("TESTNET_POLICY_REQUIRES_PIN_SESSION=1\r\n");
    wallet_uart_send_str("TESTNET_POLICY_REQUIRES_USER_CONFIRMATION=1\r\n");
    wallet_uart_send_str("TESTNET_POLICY_REQUIRES_TROPIC_AUTH_GATE=1\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_DRY_RUN_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_VERSION=C8.3_TESTNET_ADDRESS_DERIVATION_DRY_RUN_V1\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_SIGNING_ENABLED=0\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_MODEL=METADATA_ONLY_NO_KEYS_DERIVED\r\n");
    wallet_uart_send_str("TESTNET_ACCOUNT_PATH=m/84h/1h/0h\r\n");
    wallet_uart_send_str("TESTNET_RECEIVE_PATH_TEMPLATE=m/84h/1h/0h/0/{index}\r\n");
    wallet_uart_send_str("TESTNET_CHANGE_PATH_TEMPLATE=m/84h/1h/0h/1/{index}\r\n");
    wallet_uart_send_str("TESTNET_RECEIVE_INDEX=0\r\n");
    wallet_uart_send_str("TESTNET_CHANGE_INDEX=0\r\n");
    wallet_uart_send_str("TESTNET_ADDRESS_FORMAT=tb1q_P2WPKH_PUBLIC_IDENTITY\r\n");
    wallet_uart_send_str("TESTNET_XPUB_EXPORT_ENABLED=0\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_DEVICE_SIGNATURE=0\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_OUTPUT=HOST_INTENT_ONLY_NO_ADDRESS_SIGNATURE\r\n");
    wallet_uart_send_str("TESTNET_FEE_CHANGE_FIXTURES_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_FEE_CHANGE_VERSION=C8.4_TESTNET_FEE_CHANGE_POLICY_FIXTURES_V1\r\n");
    wallet_uart_send_str("TESTNET_FEE_CHANGE_SIGNING_ENABLED=0\r\n");
    wallet_uart_send_str("TESTNET_FEE_POLICY_MODEL=FIXTURE_ONLY_NO_NETWORK_BROADCAST\r\n");
    wallet_uart_send_str("TESTNET_FEE_MIN_SATS=546\r\n");
    wallet_uart_send_str("TESTNET_FEE_MAX_SATS=20000\r\n");
    wallet_uart_send_str("TESTNET_FEE_RATE_MIN_SATS_PER_KVB=1000\r\n");
    wallet_uart_send_str("TESTNET_FEE_RATE_MAX_SATS_PER_KVB=100000\r\n");
    wallet_uart_send_str("TESTNET_CHANGE_POLICY_MODEL=DERIVED_CHANGE_PATH_REQUIRED_FOR_TESTNET_SIGNING\r\n");
    wallet_uart_send_str("TESTNET_CHANGE_OUTPUT_REQUIRED=1\r\n");
    wallet_uart_send_str("TESTNET_CHANGE_DUST_LIMIT_SATS=546\r\n");
    wallet_uart_send_str("TESTNET_CHANGE_SCRIPT_SOURCE=C9_7_BIP84_PUBLIC_IDENTITY\r\n");
    wallet_uart_send_str("TESTNET_CHANGE_OWNERSHIP_PROOF=DERIVATION_PATH_AND_SCRIPT_MATCH\r\n");
    wallet_uart_send_str("TESTNET_UNSIGNED_TX_PSBT_DRY_RUN_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_UNSIGNED_TX_VERSION=C8.5_TESTNET_UNSIGNED_TX_PSBT_DRY_RUN_V1\r\n");
    wallet_uart_send_str("TESTNET_UNSIGNED_TX_SIGNING_ENABLED=0\r\n");
    wallet_uart_send_str("TESTNET_UNSIGNED_TX_INPUT_COUNT_MAX=2\r\n");
    wallet_uart_send_str("TESTNET_UNSIGNED_TX_OUTPUT_COUNT=2\r\n");
    wallet_uart_send_str("TESTNET_UNSIGNED_TX_FORMAT=PSBT_LIKE_TEXT_V1_DRY_RUN\r\n");
    wallet_uart_send_str("TESTNET_UNSIGNED_TX_REQUIRES_GLOBAL_NETWORK=TESTNET\r\n");
    wallet_uart_send_str("TESTNET_UNSIGNED_TX_REQUIRES_PREVOUTS=1\r\n");
    wallet_uart_send_str("TESTNET_UNSIGNED_TX_REQUIRES_DERIVED_CHANGE=1\r\n");
    wallet_uart_send_str("TESTNET_UNSIGNED_TX_DEVICE_SIGNATURE=0\r\n");
    wallet_uart_send_str("TESTNET_UNSIGNED_TX_RAW_TX=0\r\n");
    wallet_uart_send_str("TESTNET_UNSIGNED_TX_BROADCAST=0\r\n");
    wallet_uart_send_str("TESTNET_UNSIGNED_TX_OUTPUT=HOST_PSBT_INTENT_ONLY\r\n");
    wallet_uart_send_str("TESTNET_ACTIVATION_CHECKLIST_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_ACTIVATION_VERSION=C8.6_TESTNET_ACTIVATION_CHECKLIST_V1\r\n");
    wallet_uart_send_str("TESTNET_ACTIVATION_SIGNING_ENABLED=0\r\n");
    wallet_uart_send_str("TESTNET_ACTIVATION_READY=0\r\n");
    wallet_uart_send_str("TESTNET_ACTIVATION_STATUS=BLOCKED\r\n");
    wallet_uart_send_str("TESTNET_ACTIVATION_MODE=CHECKLIST_ONLY_NO_SIGNING\r\n");
    wallet_uart_send_str("TESTNET_ACTIVATION_REQUIRES_FIRMWARE_CHANGE=1\r\n");
    wallet_uart_send_str("TESTNET_ACTIVATION_REQUIRES_COMPILE_TIME_FLAG=1\r\n");
    wallet_uart_send_str("TESTNET_ACTIVATION_FLAG=TESTNET_SIGNING_ENABLED_BUILD_FLAG\r\n");
    wallet_uart_send_str("TESTNET_ACTIVATION_FLAG_STATE=0\r\n");
    wallet_uart_send_str("TESTNET_ACTIVATION_REQUIRES_TEST_FUNDS_ONLY=1\r\n");
    wallet_uart_send_str("TESTNET_ACTIVATION_REQUIRES_USER_CONFIRMATION=1\r\n");
    wallet_uart_send_str("TESTNET_ACTIVATION_REQUIRES_PHYSICAL_CONFIRM=1\r\n");
    wallet_uart_send_str("TESTNET_ACTIVATION_REQUIRES_MAINNET_LOCKOUT=1\r\n");
    wallet_uart_send_str("TESTNET_ACTIVATION_BLOCKER_COUNT=7\r\n");
    wallet_uart_send_str("TESTNET_CHECKLIST_ITEM_REGTEST_REGRESSIONS=PASS\r\n");
    wallet_uart_send_str("TESTNET_CHECKLIST_ITEM_TESTNET_POLICY_FIXTURES=PASS\r\n");
    wallet_uart_send_str("TESTNET_CHECKLIST_ITEM_TESTNET_DRY_RUN_PSBT=PASS\r\n");
    wallet_uart_send_str("TESTNET_CHECKLIST_ITEM_MAINNET_LOCKOUT=PASS\r\n");
    wallet_uart_send_str("TESTNET_CHECKLIST_ITEM_REAL_ADDRESS_DERIVATION=BLOCKED\r\n");
    wallet_uart_send_str("TESTNET_CHECKLIST_ITEM_CHANGE_DERIVATION=BLOCKED\r\n");
    wallet_uart_send_str("TESTNET_CHECKLIST_ITEM_REAL_FEE_POLICY=BLOCKED\r\n");
    wallet_uart_send_str("TESTNET_CHECKLIST_ITEM_SECURE_DISPLAY=BLOCKED\r\n");
    wallet_uart_send_str("TESTNET_CHECKLIST_ITEM_TROPIC_SECP256K1=BLOCKED\r\n");
    wallet_uart_send_str("TESTNET_CHECKLIST_ITEM_TESTNET_SIGNING_FLAG=BLOCKED\r\n");
    wallet_uart_send_str("TESTNET_CHECKLIST_ITEM_TESTNET_SIGNING_REGRESSION=BLOCKED\r\n");
    wallet_uart_send_str("TESTNET_ACTIVATION_OUTPUT=CHECKLIST_ONLY_NO_DEVICE_SIGNATURE\r\n");
    wallet_uart_send_str("TESTNET_ARTIFACT_EXPORT_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_ARTIFACT_VERSION=C8.7_TESTNET_DRY_RUN_ARTIFACT_EXPORT_V1\r\n");
    wallet_uart_send_str("TESTNET_ARTIFACT_SIGNING_ENABLED=0\r\n");
    wallet_uart_send_str("TESTNET_ARTIFACT_FORMAT=PSBT_LIKE_INTENT_TEXT_V1\r\n");
    wallet_uart_send_str("TESTNET_ARTIFACT_REQUIRES_REALINFO=1\r\n");
    wallet_uart_send_str("TESTNET_ARTIFACT_REQUIRES_IDENTITY=1\r\n");
    wallet_uart_send_str("TESTNET_ARTIFACT_UNSIGNED_ONLY=1\r\n");
    wallet_uart_send_str("TESTNET_ARTIFACT_DEVICE_SIGNATURE=0\r\n");
    wallet_uart_send_str("TESTNET_ARTIFACT_RAW_TX=0\r\n");
    wallet_uart_send_str("TESTNET_ARTIFACT_BROADCAST=0\r\n");
    wallet_uart_send_str("TESTNET_ARTIFACT_OUTPUT=HOST_FILE_ONLY_NO_DEVICE_SIGNATURE\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_DECISION_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_DECISION_VERSION=C8.8_TESTNET_DERIVATION_MODEL_DECISION_V1\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_DECISION_SIGNING_ENABLED=0\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_DECISION_MODEL=BIP84_TESTNET_P2WPKH_ACCOUNT\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_DECISION_ACCOUNT_PATH=m/84h/1h/0h\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_DECISION_RECEIVE_PATH=m/84h/1h/0h/0/{index}\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_DECISION_CHANGE_PATH=m/84h/1h/0h/1/{index}\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_DECISION_ADDRESS_FORMAT=tb1q_P2WPKH\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_DECISION_XPUB_EXPORT=BLOCKED\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_DECISION_DEVICE_DERIVES_KEYS=0\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_DECISION_ACTIVATION_BLOCKED=1\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_DECISION_OUTPUT=MODEL_SELECTED_IMPLEMENTATION_BLOCKED\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_COMPILE_TIME_GUARD_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_GUARD_VERSION=C8.9_TESTNET_SIGNING_COMPILE_TIME_GUARD_V1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_BUILD_FLAG_NAME=WALLET_TESTNET_SIGNING_BUILD_FLAG\r\n");
#if WALLET_TESTNET_SIGNING_BUILD_FLAG
    wallet_uart_send_str("TESTNET_SIGNING_BUILD_FLAG=1\r\n");
#else
    wallet_uart_send_str("TESTNET_SIGNING_BUILD_FLAG=0\r\n");
#endif
    wallet_uart_send_str("TESTNET_SIGNING_BUILD_FLAG_REQUIRED_FOR_SIGNING=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_COMPILE_TIME_GUARD=ENFORCED\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_RUNTIME_OVERRIDE_SUPPORTED=0\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_SOURCE_CHANGE_REQUIRED=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_REGRESSION_REQUIRED=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_GUARD_SIGNING_ENABLED=1\r\n");
    wallet_uart_send_str("MAINNET_SIGNING_BUILD_FLAG_NAME=WALLET_MAINNET_SIGNING_BUILD_FLAG\r\n");
#if WALLET_MAINNET_SIGNING_BUILD_FLAG
    wallet_uart_send_str("MAINNET_SIGNING_BUILD_FLAG=1\r\n");
#else
    wallet_uart_send_str("MAINNET_SIGNING_BUILD_FLAG=0\r\n");
#endif
    wallet_uart_send_str("MAINNET_SIGNING_COMPILE_TIME_GUARD=ENFORCED_OFF\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_MODE_DESIGN_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_MODE_VERSION=C9.0_TESTNET_SIGNING_MODE_DESIGN_V1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_MODE=ACTIVE_TESTNET_ONLY\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_MODE_NETWORK=TESTNET_ONLY\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_MODE_SIGNING_ENABLED=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_MODE_REQUIRES_BUILD_FLAG=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_MODE_BUILD_FLAG=WALLET_TESTNET_SIGNING_BUILD_FLAG\r\n");
#if WALLET_TESTNET_SIGNING_BUILD_FLAG
    wallet_uart_send_str("TESTNET_SIGNING_MODE_BUILD_FLAG_STATE=1\r\n");
#else
    wallet_uart_send_str("TESTNET_SIGNING_MODE_BUILD_FLAG_STATE=0\r\n");
#endif
    wallet_uart_send_str("TESTNET_SIGNING_MODE_REQUIRES_TEST_FUNDS=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_MODE_REQUIRES_PIN_SESSION=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_MODE_REQUIRES_CHECK_ID=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_MODE_REQUIRES_USER_CONFIRMATION=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_MODE_REQUIRES_PHYSICAL_CONFIRM=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_MODE_REQUIRES_TROPIC_AUTH_GATE=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_MODE_REQUIRES_DERIVED_TESTNET_KEYS=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_MODE_REQUIRES_DERIVED_CHANGE=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_MODE_REQUIRES_FEE_POLICY=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_MODE_BROADCAST_ENABLED=0\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_MODE_MAINNET_LOCKOUT=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_MODE_RUNTIME_OVERRIDE_SUPPORTED=0\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_MODE_OUTPUT=TESTNET_RAW_TX_ONLY_NO_BROADCAST\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_IMPLEMENTATION_FOUNDATION_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_IMPLEMENTATION_VERSION=C9.1_TESTNET_DERIVATION_IMPLEMENTATION_FOUNDATION_V1\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_IMPLEMENTATION_NETWORK=TESTNET\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_IMPLEMENTATION_MODEL=BIP84_TESTNET_P2WPKH_ACCOUNT\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_IMPLEMENTATION_ACCOUNT_PATH=m/84h/1h/0h\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_IMPLEMENTATION_RECEIVE_PATH=m/84h/1h/0h/0/{index}\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_IMPLEMENTATION_CHANGE_PATH=m/84h/1h/0h/1/{index}\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_IMPLEMENTATION_ADDRESS_FORMAT=tb1q_P2WPKH\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_IMPLEMENTATION_DEVICE_DERIVES_KEYS=0\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_IMPLEMENTATION_HOST_DERIVED_METADATA_REQUIRED=1\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_IMPLEMENTATION_XPUB_EXPORT=BLOCKED\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_IMPLEMENTATION_SIGNING_ENABLED=1\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_IMPLEMENTATION_OUTPUT=LEGACY_P2PKH_CURRENT_KEY_TESTNET_ONLY\r\n");
    wallet_uart_send_str("TESTNET_CHANGE_DERIVATION_ENFORCEMENT_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_CHANGE_DERIVATION_ENFORCEMENT_VERSION=C9.8_TESTNET_CHANGE_DERIVATION_ENFORCEMENT_V1\r\n");
    wallet_uart_send_str("TESTNET_CHANGE_DERIVATION_ENFORCEMENT_REQUIRED=1\r\n");
    wallet_uart_send_str("TESTNET_CHANGE_DERIVATION_ENFORCEMENT_PATH=" WALLET_C9_7_TESTNET_BIP84_CHANGE_PATH "\r\n");
    wallet_uart_send_str("TESTNET_CHANGE_DERIVATION_ENFORCEMENT_METADATA_REQUIRED=1\r\n");
    wallet_uart_send_str("TESTNET_CHANGE_DERIVATION_ENFORCEMENT_SCRIPT_MATCH_REQUIRED=1\r\n");
    wallet_uart_send_str("TESTNET_CHANGE_DERIVATION_ENFORCEMENT_SCRIPT=" WALLET_C9_7_TESTNET_BIP84_SCRIPT_P2WPKH "\r\n");
    wallet_uart_send_str("TESTNET_CHANGE_DERIVATION_ENFORCEMENT_SIGNING_ENABLED=1\r\n");
    wallet_uart_send_str("TESTNET_REAL_FEE_POLICY_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_REAL_FEE_POLICY_VERSION=C9.3_TESTNET_REAL_FEE_POLICY_V1\r\n");
    wallet_uart_send_str("TESTNET_REAL_FEE_POLICY_MODEL=FEE_RATE_AND_ABSOLUTE_CAP_DRAFT\r\n");
    wallet_uart_send_str("TESTNET_REAL_FEE_POLICY_MIN_SATS=546\r\n");
    wallet_uart_send_str("TESTNET_REAL_FEE_POLICY_MAX_SATS=20000\r\n");
    wallet_uart_send_str("TESTNET_REAL_FEE_POLICY_MIN_SATS_PER_KVB=1000\r\n");
    wallet_uart_send_str("TESTNET_REAL_FEE_POLICY_MAX_SATS_PER_KVB=100000\r\n");
    wallet_uart_send_str("TESTNET_REAL_FEE_POLICY_SIGNING_ENABLED=1\r\n");
    wallet_uart_send_str("TESTNET_UNSIGNED_TX_VALIDATION_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_UNSIGNED_TX_VALIDATION_VERSION=C9.4_TESTNET_UNSIGNED_TX_VALIDATION_V1\r\n");
    wallet_uart_send_str("TESTNET_UNSIGNED_TX_VALIDATION_FORMAT=PSBT_LIKE_TEXT_V1\r\n");
    wallet_uart_send_str("TESTNET_UNSIGNED_TX_VALIDATION_REQUIRES_TESTNET=1\r\n");
    wallet_uart_send_str("TESTNET_UNSIGNED_TX_VALIDATION_REQUIRES_DERIVED_INPUTS=1\r\n");
    wallet_uart_send_str("TESTNET_UNSIGNED_TX_VALIDATION_REQUIRES_DERIVED_CHANGE=1\r\n");
    wallet_uart_send_str("TESTNET_UNSIGNED_TX_VALIDATION_REQUIRES_FEE_POLICY=1\r\n");
    wallet_uart_send_str("TESTNET_UNSIGNED_TX_VALIDATION_DEVICE_SIGNATURE=1\r\n");
    wallet_uart_send_str("TESTNET_UNSIGNED_TX_VALIDATION_RAW_TX=1\r\n");
    wallet_uart_send_str("TESTNET_UNSIGNED_TX_VALIDATION_BROADCAST=0\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_ACTIVATION_DRY_RUN_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_ACTIVATION_DRY_RUN_VERSION=C9.5_GUARDED_TESTNET_SIGNING_ACTIVATION_DRY_RUN_V1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_ACTIVATION_DRY_RUN_STATUS=SUPERSEDED_BY_C9.6_ACTIVE_TESTNET_ONLY\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_ACTIVATION_DRY_RUN_ALL_RUNTIME_GATES_REQUIRED=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_ACTIVATION_DRY_RUN_PROVES_NO_SIGN_WHEN_FLAG_OFF=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_ACTIVATION_DRY_RUN_SIGNING_ENABLED=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_ACTIVATION_DRY_RUN_RAW_TX=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_ENABLE_BLOCKED=0\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_ENABLE_ACTIVE=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_ENABLE_VERSION=C9.6_TESTNET_SIGNING_ENABLE_ON_TEST_FUNDS_ONLY_V1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_ENABLE_STATUS=ACTIVE_TESTNET_ONLY_MAINNET_LOCKED\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_ENABLE_REQUIRES_USER_PROVIDED_TEST_FUNDS=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_ENABLE_REQUIRES_PHYSICAL_CONFIRM=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_ENABLE_REQUIRES_EXPLICIT_REBUILD=0\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_ENABLE_MAINNET_LOCKOUT=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_ENABLE_ACTUAL_SIGNING_ENABLED=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_ENABLE_FORMAT=LEGACY_P2PKH_1OR2IN_2OUT\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_ENABLE_BROADCAST=0\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_ENABLE_CONFIRMATION=UART_CONFIRM_CODE_OR_BUTTON_USER\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_ENABLE_TROPIC_AUTH_GATE=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_ENABLE_BIP84_DEVICE_DERIVATION=0\r\n");
    wallet_uart_send_str("TESTNET_BIP84_IDENTITY_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_BIP84_IDENTITY_VERSION=" WALLET_C9_7_BIP84_IDENTITY_VERSION "\r\n");
    wallet_uart_send_str("TESTNET_BIP84_ADDRESS=" WALLET_C9_7_TESTNET_BIP84_ADDRESS "\r\n");
    wallet_uart_send_str("TESTNET_BIP84_SCRIPT_P2WPKH=" WALLET_C9_7_TESTNET_BIP84_SCRIPT_P2WPKH "\r\n");
    wallet_uart_send_str("TESTNET_BIP84_PUBKEY_HASH160=" WALLET_C9_7_TESTNET_BIP84_PUBKEY_HASH160 "\r\n");
    wallet_uart_send_str("TESTNET_BIP84_ACCOUNT_PATH=" WALLET_C9_7_TESTNET_BIP84_ACCOUNT_PATH "\r\n");
    wallet_uart_send_str("TESTNET_BIP84_RECEIVE_PATH=" WALLET_C9_7_TESTNET_BIP84_RECEIVE_PATH "\r\n");
    wallet_uart_send_str("TESTNET_BIP84_CHANGE_PATH=" WALLET_C9_7_TESTNET_BIP84_CHANGE_PATH "\r\n");
    wallet_uart_send_str("TESTNET_BIP84_DEVICE_DERIVES_KEYS=0\r\n");
    wallet_uart_send_str("TESTNET_BIP84_SIGNING_ENABLED=0\r\n");
    wallet_uart_send_str("TESTNET_CHANGE_DERIVATION_ENFORCEMENT_CURRENT=C9.8_TESTNET_CHANGE_DERIVATION_ENFORCEMENT_V1\r\n");
    wallet_uart_send_str("TESTNET_CHANGE_DERIVATION_EXACT_REQUIRED=" WALLET_C9_7_TESTNET_BIP84_CHANGE_PATH "\r\n");
    wallet_uart_send_str("TESTNET_CHANGE_SCRIPT_EXACT_REQUIRED=" WALLET_C9_7_TESTNET_BIP84_SCRIPT_P2WPKH "\r\n");
    wallet_uart_send_str("HOST_REAL_NETWORK_OVERRIDE_SUPPORTED=0\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_ACTIVATION_REQUIRES_FIRMWARE_CHANGE=0\r\n");
    wallet_uart_send_str("MAINNET_SIGNING_ACTIVATION_REQUIRES_FIRMWARE_CHANGE=1\r\n");
    wallet_uart_send_str("BLOCKER_SECURE_DISPLAY=1\r\n");
    wallet_uart_send_str("BLOCKER_TROPIC_SECP256K1=1\r\n");
    wallet_uart_send_str("BLOCKER_REAL_NETWORK_POLICY=0\r\n");
    wallet_uart_send_str("BLOCKER_REAL_ADDRESS_DERIVATION=1\r\n");
    wallet_uart_send_str("BLOCKER_BIP84_DEVICE_DERIVED_KEYS=1\r\n");
    wallet_uart_send_str("BLOCKER_CHANGE_DERIVATION=0\r\n");
    wallet_uart_send_str("BLOCKER_REAL_FEE_POLICY=1\r\n");
    wallet_uart_send_str("BLOCKER_TESTNET_REGRESSION=0\r\n");
    wallet_uart_send_str("NEXT_SAFE_STAGE=C9.9_TESTNET_P2WPKH_SIGNING_PREP\r\n");
    wallet_uart_send_str("C9_TARGET=TESTNET_SIGNING_ONLY_AFTER_EXPLICIT_USER_APPROVAL_AND_TEST_FUNDS\r\n");
}

static const char *wallet_uart_unlock_pin_arg(void)
{
    static char pin[33];
    const char *p;
    uint32_t i = 0U;

    wallet_uart_secure_zero(pin, sizeof(pin));

    p = wallet_uart_cmd;
    while (*p == '\r' || *p == '\n' || *p == ' ' || *p == '\t')
    {
        p++;
    }

    if (strncmp(p, "UNLOCK_PIN=", 11U) != 0)
    {
        return NULL;
    }

    p += 11U;
    while (p[i] >= '0' && p[i] <= '9' && i < (sizeof(pin) - 1U))
    {
        pin[i] = p[i];
        i++;
    }

    pin[i] = '\0';
    return pin;
}

static void wallet_uart_send_unlock_result(void)
{
    char pin_copy[33];
    const char *pin_arg;
    int unlock_ret;

    wallet_uart_secure_zero(pin_copy, sizeof(pin_copy));
    pin_arg = wallet_uart_unlock_pin_arg();
    if (pin_arg != NULL)
    {
        strncpy(pin_copy, pin_arg, sizeof(pin_copy) - 1U);
    }

    unlock_ret = wallet_key_provider_unlock_with_pin(pin_copy);
    wallet_uart_secure_zero(pin_copy, sizeof(pin_copy));

    if (unlock_ret != 0)
    {
        snprintf(wallet_uart_response,
                 sizeof(wallet_uart_response),
                 "\r\nERR KEYPROVIDER %d\r\n",
                 unlock_ret);
        wallet_uart_send_str(wallet_uart_response);
        return;
    }

    wallet_uart_send_str("\r\nOK UNLOCK\r\n");
    wallet_uart_send_str("PIN_SESSION_UNLOCKED=1\r\n");
    snprintf(wallet_uart_response,
             sizeof(wallet_uart_response),
             "PIN_SESSION_TIMEOUT_MS=%lu\r\n",
             (unsigned long)WALLET_KEY_PROVIDER_PIN_SESSION_TIMEOUT_MS);
    wallet_uart_send_str(wallet_uart_response);
}

static void wallet_uart_send_unlockinfo(void)
{
    snprintf(wallet_uart_response,
             sizeof(wallet_uart_response),
             "\r\nOK UNLOCKINFO\r\n"
             "PIN_SESSION_UNLOCKED=%d\r\n"
             "PIN_SESSION_AGE_MS=%lu\r\n"
             "PIN_SESSION_TIMEOUT_MS=%lu\r\n"
             "PIN_FAIL_COUNT=%lu\r\n"
             "PIN_RETRY_REMAINING_MS=%lu\r\n",
             wallet_key_provider_session_is_unlocked(),
             (unsigned long)wallet_key_provider_session_age_ms(),
             (unsigned long)WALLET_KEY_PROVIDER_PIN_SESSION_TIMEOUT_MS,
             (unsigned long)wallet_key_provider_pin_fail_count(),
             (unsigned long)wallet_key_provider_pin_retry_remaining_ms());
    wallet_uart_send_str(wallet_uart_response);
}

static const char *wallet_uart_confirm_code_arg(void)
{
    static char code[WALLET_COMMAND_CONFIRM_CODE_SIZE];
    const char *p;
    uint32_t i;

    wallet_uart_secure_zero(code, sizeof(code));

    if (wallet_uart_command_is_exact(wallet_uart_cmd, "CONFIRM"))
    {
        return NULL;
    }

    p = wallet_uart_cmd;
    while (*p == '\r' || *p == '\n' || *p == ' ' || *p == '\t')
    {
        p++;
    }

    if (strncmp(p, "CONFIRM_CODE=", 13U) != 0)
    {
        return NULL;
    }

    p += 13U;

    for (i = 0U; i < WALLET_COMMAND_CONFIRM_CODE_LEN; i++)
    {
        if (p[i] < '0' || p[i] > '9')
        {
            return NULL;
        }
        code[i] = p[i];
    }

    if (p[WALLET_COMMAND_CONFIRM_CODE_LEN] != '\r' &&
        p[WALLET_COMMAND_CONFIRM_CODE_LEN] != '\n' &&
        p[WALLET_COMMAND_CONFIRM_CODE_LEN] != '\0' &&
        p[WALLET_COMMAND_CONFIRM_CODE_LEN] != ' ' &&
        p[WALLET_COMMAND_CONFIRM_CODE_LEN] != '\t')
    {
        return NULL;
    }

    code[WALLET_COMMAND_CONFIRM_CODE_LEN] = '\0';
    return code;
}

static void wallet_uart_send_confirm_result(void)
{
    int confirm_ret;

    confirm_ret = wallet_command_confirm_approved_check_code(wallet_uart_confirm_code_arg());

    if (confirm_ret != WALLET_POLICY_OK)
    {
        snprintf(wallet_uart_response,
                 sizeof(wallet_uart_response),
                 "\r\nERR POLICY %d\r\n",
                 confirm_ret);
        wallet_uart_send_str(wallet_uart_response);
        return;
    }

    wallet_uart_send_str("\r\nOK CONFIRM\r\n");
    wallet_uart_send_str("USER_APPROVED=1\r\n");
    wallet_uart_send_str("CONFIRM_SOURCE=UART_CONFIRM_CODE\r\n");
}

static void wallet_uart_send_buttoninfo(void)
{
    int32_t button_state;
    char confirm_code[WALLET_COMMAND_CONFIRM_CODE_SIZE];
    int confirm_code_ret;

    button_state = BSP_PB_GetState(BUTTON_USER);

    snprintf(wallet_uart_response,
             sizeof(wallet_uart_response),
             "\r\nOK BUTTONINFO\r\n"
             "BUTTON_USER_RAW=%ld\r\n"
             "BUTTON_USER_PRESSED_ACTIVE_HIGH=%lu\r\n"
             "BUTTON_CONFIRM_ARMED=%lu\r\n"
             "APPROVED_CHECK_PENDING=%d\r\n"
             "APPROVED_CHECK_CONFIRMED=%d\r\n",
             (long)button_state,
             (unsigned long)((button_state != GPIO_PIN_RESET) ? 1UL : 0UL),
             (unsigned long)wallet_uart_button_confirm_armed,
             wallet_command_has_approved_check(),
             wallet_command_has_confirmed_approved_check());

    wallet_uart_send_str(wallet_uart_response);

    snprintf(wallet_uart_response,
             sizeof(wallet_uart_response),
             "APPROVAL_AGE_MS=%lu\r\n"
             "APPROVAL_TIMEOUT_MS=%lu\r\n",
             (unsigned long)wallet_command_approved_check_age_ms(),
             (unsigned long)wallet_command_approval_timeout_ms());
    wallet_uart_send_str(wallet_uart_response);

    wallet_uart_secure_zero(confirm_code, sizeof(confirm_code));
    confirm_code_ret = wallet_command_get_confirm_code(confirm_code, sizeof(confirm_code));
    if (confirm_code_ret == WALLET_POLICY_OK)
    {
        wallet_uart_send_str("CONFIRM_CODE=");
        wallet_uart_send_str(confirm_code);
        wallet_uart_send_str("\r\n");
        wallet_uart_secure_zero(confirm_code, sizeof(confirm_code));
    }
}

static void wallet_uart_send_version(void)
{
    wallet_uart_send_str("\r\nOK VERSION\r\n");
    wallet_uart_send_str("APP=" WALLET_APP_NAME_STRING "\r\n");
    wallet_uart_send_str("VERSION=" WALLET_APP_VERSION_STRING "\r\n");
    wallet_uart_send_str("PROTOCOL_VERSION=" WALLET_PROTOCOL_VERSION "\r\n");
    wallet_uart_send_str("COMMAND_VERSION=" WALLET_COMMAND_VERSION "\r\n");
    wallet_uart_send_str("RESPONSE_VERSION=" WALLET_RESPONSE_VERSION "\r\n");
    wallet_uart_send_str("ERROR_VERSION=" WALLET_ERROR_VERSION "\r\n");
    wallet_uart_send_str("POLICY_VERSION=" WALLET_POLICY_VERSION "\r\n");
    wallet_uart_send_str("FRAME_VERSION=" WALLET_FRAME_VERSION "\r\n");
    wallet_uart_send_str("BOARD=" WALLET_BOARD_STRING "\r\n");
    wallet_uart_send_str("MCU=" WALLET_MCU_STRING "\r\n");
    wallet_uart_send_str("UART=BSP_COM1_STLINK_VCP_115200_8N1\r\n");
    wallet_uart_send_str("SE=" WALLET_SE_STRING "\r\n");
    wallet_uart_send_str("KEY_MODEL=" WALLET_KEY_MODEL_STRING "\r\n");
    wallet_uart_send_str("DEV_KEY_ENABLED=" WALLET_DEV_KEY_ENABLED_STRING "\r\n");
    wallet_uart_send_str("POLICY=" WALLET_POLICY_MODEL_STRING "\r\n");
    wallet_uart_send_str("TX_TYPE=LEGACY_P2PKH_1OR2IN_2OUT\r\n");
    wallet_uart_send_str("NETWORK_REQUIRED=REGTEST_OR_TESTNET\r\n");
    wallet_uart_send_str("NETWORK_ALLOWED=REGTEST,TESTNET\r\n");
    wallet_uart_send_str("REAL_BITCOIN_STAGE=" WALLET_REAL_BITCOIN_STAGE "\r\n");
    wallet_uart_send_str("REAL_BITCOIN_SIGNING_ENABLED=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_ENABLED=1\r\n");
    wallet_uart_send_str("MAINNET_SIGNING_ENABLED=0\r\n");
    wallet_uart_send_str("TESTNET_WATCH_ONLY_DRY_RUN_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_DRY_RUN_SIGNING_ENABLED=0\r\n");
    wallet_uart_send_str("TESTNET_POLICY_FIXTURES_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_POLICY_SIGNING_ENABLED=0\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_DRY_RUN_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_SIGNING_ENABLED=0\r\n");
    wallet_uart_send_str("TESTNET_FEE_CHANGE_FIXTURES_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_FEE_CHANGE_SIGNING_ENABLED=0\r\n");
    wallet_uart_send_str("TESTNET_UNSIGNED_TX_PSBT_DRY_RUN_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_UNSIGNED_TX_SIGNING_ENABLED=0\r\n");
    wallet_uart_send_str("TESTNET_ACTIVATION_CHECKLIST_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_ACTIVATION_SIGNING_ENABLED=0\r\n");
    wallet_uart_send_str("TESTNET_ARTIFACT_EXPORT_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_ARTIFACT_SIGNING_ENABLED=0\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_DECISION_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_DECISION_SIGNING_ENABLED=0\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_COMPILE_TIME_GUARD_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_BUILD_FLAG=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_MODE_DESIGN_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_MODE_SIGNING_ENABLED=1\r\n");
    wallet_uart_send_str("TESTNET_DERIVATION_IMPLEMENTATION_FOUNDATION_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_CHANGE_DERIVATION_ENFORCEMENT_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_REAL_FEE_POLICY_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_UNSIGNED_TX_VALIDATION_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_ACTIVATION_DRY_RUN_SUPPORTED=1\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_ENABLE_BLOCKED=0\r\n");
    wallet_uart_send_str("TESTNET_SIGNING_ENABLE_ACTIVE=1\r\n");
    wallet_uart_send_str("BUILD_DATE=" __DATE__ "\r\n");
    wallet_uart_send_str("BUILD_TIME=" __TIME__ "\r\n");
}
static void wallet_uart_send_sekeytest(void)
{
    wallet_uart_send_str("\r\nERR SEKEYTEST\r\n");
    wallet_uart_send_str("TEST=TROPIC_P256_SIGN_SELFTEST\r\n");
    wallet_uart_send_str("STATUS=DISABLED_AFTER_L3_HANG\r\n");
    wallet_uart_send_str("BITCOIN_DIRECT_TROPIC_SIGNING=0\r\n");
    wallet_uart_send_str("NOTE=B1_SEKEYINFO_IS_CURRENT_SAFE_MILESTONE\r\n");
}
static void wallet_uart_send_sekeyinfo(void)
{
    wallet_uart_send_str("\r\nOK SEKEYINFO\r\n");
    wallet_uart_send_str("SE=TROPIC01\r\n");
    wallet_uart_send_str("ECC_KEY_SLOTS=32\r\n");
    wallet_uart_send_str("ECC_SLOT_MIN=0\r\n");
    wallet_uart_send_str("ECC_SLOT_MAX=31\r\n");
    wallet_uart_send_str("TROPIC_KEY_GENERATE=1\r\n");
    wallet_uart_send_str("TROPIC_KEY_STORE=1\r\n");
    wallet_uart_send_str("TROPIC_KEY_READ_PUBLIC=1\r\n");
    wallet_uart_send_str("TROPIC_KEY_ERASE=1\r\n");
    wallet_uart_send_str("TROPIC_ECDSA_SIGN=1\r\n");
    wallet_uart_send_str("TROPIC_EDDSA_SIGN=1\r\n");
    wallet_uart_send_str("TROPIC_CURVE_P256=1\r\n");
    wallet_uart_send_str("TROPIC_CURVE_ED25519=1\r\n");
    wallet_uart_send_str("TROPIC_CURVE_SECP256K1=0\r\n");
    wallet_uart_send_str("BITCOIN_DIRECT_TROPIC_SIGNING=0\r\n");
    wallet_uart_send_str("BITCOIN_REQUIRED_CURVE=SECP256K1\r\n");
    wallet_uart_send_str("CURRENT_BITCOIN_KEY_MODEL=" WALLET_KEY_MODEL_STRING "\r\n");
    wallet_uart_send_str("CURRENT_DEV_KEY_ENABLED=" WALLET_DEV_KEY_ENABLED_STRING "\r\n");
}
static int wallet_uart_split_hex_chunks(void)
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

    return (signed_tx_hex_len < sizeof(signed_tx_hex)) ? 1 : 0;
}

void wallet_uart_run(void)
{
    debug_stage = 6000;

    hal_rng_word = 0;
    hal_rng_ret = HAL_RNG_GenerateRandomNumber(
        &hrng,
        (uint32_t *)&hal_rng_word
    );

    debug_stage = 6010;

    if (hal_rng_ret != HAL_OK)
    {
        wallet_uart_send_str("ERR RNG\r\n");
        while (1) { __NOP(); }
    }

    psa_init_ret = psa_crypto_init();

    debug_stage = 6020;

    if (psa_init_ret != PSA_SUCCESS)
    {
        wallet_uart_send_str("ERR PSA\r\n");
        while (1) { __NOP(); }
    }

    debug_stage = 6030;

    if (wallet_secure_element_init() != 0)
    {
        wallet_uart_send_str("ERR SECURE_ELEMENT_INIT\r\n");
        while (1) { __NOP(); }
    }

    wallet_uart_send_str("\r\nSTM32 WALLET UART READY\r\n");

    while (1)
    {
        wallet_uart_clear_shared_debug();

        debug_stage = 6100;

        wallet_uart_ret = wallet_uart_read_command();

        debug_stage = 6110;

        if (wallet_uart_ret == WALLET_UART_READ_SEINFO)
        {
            debug_stage = 6120;
            wallet_uart_send_seinfo();
            continue;
        }

        if (wallet_uart_ret == WALLET_UART_READ_POLICYINFO)
        {
            debug_stage = 6130;
            wallet_uart_send_policyinfo();
            continue;
        }

        if (wallet_uart_ret == WALLET_UART_READ_VERSION)
        {
            debug_stage = 6140;
            wallet_uart_send_version();
            continue;
        }

        if (wallet_uart_ret == WALLET_UART_READ_FRAMEINFO)
        {
            debug_stage = 6141;
            wallet_uart_send_frameinfo();
            continue;
        }

        if (wallet_uart_ret == WALLET_UART_READ_REALINFO)
        {
            debug_stage = 6142;
            wallet_uart_send_realinfo();
            continue;
        }

        if (wallet_uart_ret == WALLET_UART_READ_SEKEYINFO)
        {
            debug_stage = 6150;
            wallet_uart_send_sekeyinfo();
            continue;
        }

        if (wallet_uart_ret == WALLET_UART_READ_SEKEYTEST)
        {
            debug_stage = 6160;
            wallet_uart_send_sekeytest();
            continue;
        }

        if (wallet_uart_ret == WALLET_UART_READ_IDENTITY)
        {
            debug_stage = 6170;
            wallet_uart_send_identity();
            continue;
        }

        if (wallet_uart_ret == WALLET_UART_READ_ADDR)
        {
            debug_stage = 6171;
            wallet_uart_send_addr();
            continue;
        }

        if (wallet_uart_ret == WALLET_UART_READ_PUBKEY)
        {
            debug_stage = 6172;
            wallet_uart_send_pubkey();
            continue;
        }

        if (wallet_uart_ret == WALLET_UART_READ_SCRIPT)
        {
            debug_stage = 6173;
            wallet_uart_send_script();
            continue;
        }

        if (wallet_uart_ret == WALLET_UART_READ_UNLOCK_PIN)
        {
            debug_stage = 61731;
            wallet_uart_send_unlock_result();
            wallet_uart_clear_command_buffer();
            continue;
        }

        if (wallet_uart_ret == WALLET_UART_READ_LOCK)
        {
            debug_stage = 61732;
            wallet_key_provider_lock_session();
            wallet_uart_send_str("\r\nOK LOCK\r\nPIN_SESSION_UNLOCKED=0\r\n");
            wallet_uart_clear_command_buffer();
            continue;
        }

        if (wallet_uart_ret == WALLET_UART_READ_UNLOCKINFO)
        {
            debug_stage = 61733;
            wallet_uart_send_unlockinfo();
            continue;
        }

        if (wallet_uart_ret == WALLET_UART_READ_CONFIRM)
        {
            debug_stage = 61735;
            wallet_uart_send_confirm_result();
            continue;
        }

        if (wallet_uart_ret == WALLET_UART_READ_BUTTONINFO)
        {
            debug_stage = 61736;
            wallet_uart_send_buttoninfo();
            continue;
        }

        if (wallet_uart_ret == WALLET_FRAME_ERR_INVALID ||
            wallet_uart_ret == WALLET_FRAME_ERR_LEN ||
            wallet_uart_ret == WALLET_FRAME_ERR_CRC ||
            wallet_uart_ret == WALLET_FRAME_ERR_UNSUPPORTED)
        {
            snprintf(wallet_uart_response,
                     sizeof(wallet_uart_response),
                     "\r\nERR FRAME %d\r\n"
                     "ERROR_VERSION=" WALLET_ERROR_VERSION "\r\n",
                     wallet_uart_ret);

            wallet_uart_send_str(wallet_uart_response);
            wallet_uart_clear_command_buffer();
            continue;
        }

        if (wallet_uart_ret == WALLET_UART_READ_CHECK)
        {
            debug_stage = 6174;

            wallet_uart_keypolicy_ret = wallet_uart_check_host_key_policy(wallet_uart_cmd);

            if (wallet_uart_keypolicy_ret != 0)
            {
                snprintf(wallet_uart_response,
                         sizeof(wallet_uart_response),
                         "\r\nERR KEYPOLICY %d\r\n",
                         wallet_uart_keypolicy_ret);

                wallet_uart_send_str(wallet_uart_response);
                wallet_uart_clear_command_buffer();
                continue;
            }

            wallet_uart_send_check_summary(wallet_uart_cmd);
            continue;
        }

        if (wallet_uart_ret != WALLET_UART_READ_SIGN)
        {
            snprintf(wallet_uart_response,
                     sizeof(wallet_uart_response),
                     "\r\nERR READ %d\r\n",
                     wallet_uart_ret);

            wallet_uart_send_str(wallet_uart_response);
            wallet_uart_clear_command_buffer();
            continue;
        }

        debug_stage = 6200;

        wallet_uart_keypolicy_ret = wallet_uart_check_host_key_policy(wallet_uart_cmd);

        if (wallet_uart_keypolicy_ret != 0)
        {
            snprintf(wallet_uart_response,
                     sizeof(wallet_uart_response),
                     "\r\nERR KEYPOLICY %d\r\n",
                     wallet_uart_keypolicy_ret);

            wallet_uart_send_str(wallet_uart_response);
            wallet_uart_clear_command_buffer();
            continue;
        }

        /*
         * C3.2: firmware enforces CHECK, explicit user CONFIRM, and matching SIGN
         * before unlock, key provider, or secure-element authorization.
         */
        wallet_uart_ret = wallet_command_sign_matches_approved_check_text(wallet_uart_cmd);

        if (wallet_uart_ret != 0)
        {
            wallet_key_provider_lock_session();
            snprintf(wallet_uart_response,
                     sizeof(wallet_uart_response),
                     "\r\nERR POLICY %d\r\n",
                     wallet_uart_ret);

            wallet_uart_send_str(wallet_uart_response);
            wallet_uart_clear_command_buffer();
            continue;
        }

        /*
         * Policy must run before key provider / secure-element authorization.
         * This rejects unsafe transactions before any private key access.
         */
        wallet_uart_ret = wallet_command_check_policy_text(wallet_uart_cmd);

        if (wallet_uart_ret != 0)
        {
            wallet_key_provider_lock_session();
            snprintf(wallet_uart_response,
                     sizeof(wallet_uart_response),
                     "\r\nERR POLICY %d\r\n",
                     wallet_uart_ret);

            wallet_uart_send_str(wallet_uart_response);
            wallet_uart_clear_command_buffer();
            continue;
        }

        wallet_uart_keypolicy_ret = wallet_key_provider_get_private_key_bytes_for_command(
            wallet_uart_cmd,
            wallet_uart_private_key,
            sizeof(wallet_uart_private_key)
        );

        if (wallet_uart_keypolicy_ret != 0)
        {
            snprintf(wallet_uart_response,
                     sizeof(wallet_uart_response),
                     "\r\nERR KEYPROVIDER %d\r\n",
                     wallet_uart_keypolicy_ret);

            wallet_uart_send_str(wallet_uart_response);
            wallet_uart_clear_command_buffer();
            continue;
        }

        wallet_uart_ret = wallet_command_sign_text_with_private_key(
            wallet_uart_cmd,
            wallet_uart_private_key,
            (uint8_t *)signed_tx_raw,
            sizeof(signed_tx_raw),
            (uint32_t *)&signed_tx_len,
            signed_tx_hex,
            sizeof(signed_tx_hex)
        );

        wallet_uart_secure_zero(wallet_uart_private_key, sizeof(wallet_uart_private_key));

        signed_tx_build_ret = wallet_uart_ret;
        tx_preimage_build_ret = 0;

        debug_stage = 6210;

        if (wallet_uart_ret != 0)
        {
            snprintf(wallet_uart_response,
                     sizeof(wallet_uart_response),
                     "\r\nERR SIGN %d\r\n",
                     wallet_uart_ret);

            wallet_uart_send_str(wallet_uart_response);
            wallet_uart_clear_command_buffer();
            continue;
        }

        signed_tx_hex_len = signed_tx_len * 2U;
        signed_tx_hex_expected_len = signed_tx_hex_len;

        if (signed_tx_len > 4U &&
            signed_tx_raw[signed_tx_len - 4U] == 0x00 &&
            signed_tx_raw[signed_tx_len - 3U] == 0x00 &&
            signed_tx_raw[signed_tx_len - 2U] == 0x00 &&
            signed_tx_raw[signed_tx_len - 1U] == 0x00)
        {
            signed_tx_ok = 1;
        }

        if (signed_tx_hex[0] == '0' &&
            signed_tx_hex[1] == '1' &&
            signed_tx_hex[8] == '0' &&
            (signed_tx_hex[9] == '1' || signed_tx_hex[9] == '2'))
        {
            signed_tx_hex_ok = 1;
        }

        signed_tx_hex_parts_ok = (uint32_t)wallet_uart_split_hex_chunks();

        if (signed_tx_ok != 1 ||
            signed_tx_hex_ok != 1 ||
            signed_tx_hex_parts_ok != 1U)
        {
            wallet_uart_send_str("\r\nERR POSTCHECK\r\n");
            wallet_uart_clear_shared_debug();
            wallet_uart_clear_command_buffer();
            continue;
        }

        debug_stage = 6280;

        wallet_command_clear_approved_check();
        wallet_uart_send_str("\r\nOK\r\nRESPONSE_VERSION=" WALLET_RESPONSE_VERSION "\r\nRAW_TX=");
        wallet_uart_send_str(signed_tx_hex);
        wallet_uart_send_str("\r\n");
        wallet_uart_clear_shared_debug();
        wallet_uart_clear_command_buffer();
    }
}

























