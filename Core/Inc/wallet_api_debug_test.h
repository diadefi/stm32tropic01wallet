#ifndef WALLET_API_DEBUG_TEST_H
#define WALLET_API_DEBUG_TEST_H

#include "wallet_debug_test.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Second regression test:
 * Calls the high-level wallet_sign_p2pkh_2out_tx() API instead of manually
 * building the preimage, hashing, signing, DER-encoding, and serializing.
 */
void wallet_api_debug_run_regression_test(void);

/* Debug value for STM32CubeIDE Expressions view. Expected final value: 0. */
extern volatile int wallet_sign_api_ret;

#ifdef __cplusplus
}
#endif

#endif /* WALLET_API_DEBUG_TEST_H */
