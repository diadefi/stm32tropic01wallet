#ifndef WALLET_UART_H
#define WALLET_UART_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void wallet_uart_run(void);

extern volatile int wallet_uart_keypolicy_ret;
extern volatile int wallet_uart_ret;
extern volatile uint32_t wallet_uart_rx_len;
extern volatile uint32_t wallet_uart_tx_len;

#ifdef __cplusplus
}
#endif

#endif /* WALLET_UART_H */
