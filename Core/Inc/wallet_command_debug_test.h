#ifndef WALLET_COMMAND_DEBUG_TEST_H
#define WALLET_COMMAND_DEBUG_TEST_H

#include "wallet_debug_test.h"

#ifdef __cplusplus
extern "C" {
#endif

void wallet_command_debug_run_regression_test(void);

extern volatile int wallet_command_ret;

#ifdef __cplusplus
}
#endif

#endif /* WALLET_COMMAND_DEBUG_TEST_H */
