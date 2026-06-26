#ifndef WALLET_SECURE_ELEMENT_H
#define WALLET_SECURE_ELEMENT_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
int wallet_secure_element_p256_selftest(char *out, uint32_t out_size);

#endif

/*
 * Secure-element authorization layer.
 *
 * This version performs a real libtropic/TROPIC01 smoke check:
 *   - lt_init()
 *   - lt_get_tr01_mode()
 *   - lt_get_info_chip_id()
 *
 * Key release is still a dev-key release in wallet_key_provider.c,
 * but it is now gated by live TROPIC01 communication.
 */
int wallet_secure_element_init(void);
int wallet_secure_element_authorize_key_use(void);

extern volatile int wallet_secure_element_init_ret;
extern volatile int wallet_secure_element_authorize_ret;
extern volatile uint32_t wallet_secure_element_auth_count;

extern volatile int wallet_secure_element_lt_init_ret;
extern volatile int wallet_secure_element_lt_mode_ret;
extern volatile int wallet_secure_element_lt_chip_id_ret;
extern volatile int wallet_secure_element_lt_deinit_ret;
extern volatile uint32_t wallet_secure_element_mode_value;
extern volatile uint32_t wallet_secure_element_initialized;

extern volatile uint32_t wallet_secure_element_init_attempts;
extern volatile int wallet_secure_element_last_attempt_ret;



#ifdef __cplusplus
}
int wallet_secure_element_p256_selftest(char *out, uint32_t out_size);

#endif

int wallet_secure_element_p256_selftest(char *out, uint32_t out_size);

#endif /* WALLET_SECURE_ELEMENT_H */

