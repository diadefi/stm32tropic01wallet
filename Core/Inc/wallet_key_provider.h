#ifndef WALLET_KEY_PROVIDER_H
#define WALLET_KEY_PROVIDER_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define WALLET_KEY_PROVIDER_PRIVKEY_BYTES_LEN 32U
#define WALLET_KEY_PROVIDER_PRIVKEY_HEX_LEN   64U
#define WALLET_KEY_PROVIDER_PIN_SESSION_TIMEOUT_MS 30000U
#define WALLET_KEY_PROVIDER_PIN_RETRY_DELAY_MS    1000U
#define WALLET_KEY_PROVIDER_PIN_MAX_ATTEMPTS      3U

#define WALLET_KEY_PROVIDER_ERR_UNLOCK_MISSING    -22
#define WALLET_KEY_PROVIDER_ERR_UNLOCK_BAD        -23
#define WALLET_KEY_PROVIDER_ERR_PIN_LOCKED        -61
#define WALLET_KEY_PROVIDER_ERR_PIN_EXPIRED       -62

int wallet_key_provider_get_private_key_bytes(uint8_t *out_key,
                                               size_t out_key_size);

int wallet_key_provider_get_private_key_bytes_for_command(const char *command_text,
                                                           uint8_t *out_key,
                                                           size_t out_key_size);

int wallet_key_provider_get_private_key_hex(char *out_hex,
                                            size_t out_hex_size);

int wallet_key_provider_unlock_with_pin(const char *pin_text);
void wallet_key_provider_lock_session(void);
int wallet_key_provider_session_is_unlocked(void);
uint32_t wallet_key_provider_session_age_ms(void);
uint32_t wallet_key_provider_pin_fail_count(void);
uint32_t wallet_key_provider_pin_retry_remaining_ms(void);

#ifdef __cplusplus
}
#endif

#endif /* WALLET_KEY_PROVIDER_H */

