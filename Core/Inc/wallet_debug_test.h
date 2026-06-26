#ifndef WALLET_DEBUG_TEST_H
#define WALLET_DEBUG_TEST_H

#include "main.h"
#include "psa/crypto.h"

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void wallet_debug_run_regression_test(void);

/* Debug globals kept non-static so STM32CubeIDE Expressions can inspect them. */
extern volatile uint32_t debug_stage;

extern volatile HAL_StatusTypeDef hal_rng_ret;
extern volatile uint32_t hal_rng_word;
extern volatile psa_status_t psa_init_ret;

extern volatile psa_status_t psa_sha_ret;
extern volatile uint32_t psa_sha_len;

extern volatile uint8_t secp_privkey[32];
extern volatile uint8_t secp_pubkey[65];
extern volatile uint8_t secp_pubkey_compressed[33];
extern volatile uint8_t hash160_sha256[32];
extern volatile uint8_t hash160_out[20];

extern volatile int secp_pubkey_ok;
extern volatile int secp_pubkey_compressed_ok;
extern volatile int hash160_ok;

extern volatile uint8_t tx_preimage[192];
extern volatile uint32_t tx_preimage_len;

extern volatile uint8_t tx_hash1[32];
extern volatile uint8_t tx_digest[32];

extern volatile psa_status_t tx_sha1_ret;
extern volatile psa_status_t tx_sha2_ret;
extern volatile uint32_t tx_sha1_len;
extern volatile uint32_t tx_sha2_len;

extern volatile uint8_t tx_signature64[64];
extern volatile uint8_t tx_signature_der[80];
extern volatile uint8_t tx_signature_der_sighash[81];

extern volatile int tx_sign_ret;
extern volatile int tx_verify_ret;
extern volatile int tx_signature_der_len;
extern volatile int tx_signature_der_sighash_len;

extern volatile int tx_der_ok;
extern volatile int tx_sighash_byte_ok;
extern volatile int tx_signing_ok;

extern volatile int tx_preimage_build_ret;
extern volatile int signed_tx_build_ret;

extern volatile uint8_t signed_tx_raw[512];
extern volatile uint32_t signed_tx_len;
extern volatile uint32_t signed_tx_expected_len;
extern volatile uint32_t signed_tx_script_sig_len;

extern volatile int signed_tx_len_match;
extern volatile int signed_tx_script_sig_ok;
extern volatile int signed_tx_prefix_ok;
extern volatile int signed_tx_ok;

extern char signed_tx_hex[1024];

extern volatile uint32_t signed_tx_hex_len;
extern volatile uint32_t signed_tx_hex_expected_len;
extern volatile uint32_t signed_tx_hex_ok;

extern char signed_tx_hex_part0[101];
extern char signed_tx_hex_part1[101];
extern char signed_tx_hex_part2[101];
extern char signed_tx_hex_part3[101];
extern char signed_tx_hex_part4[101];

extern volatile uint32_t signed_tx_hex_parts_ok;

#ifdef __cplusplus
}
#endif

#endif /* WALLET_DEBUG_TEST_H */
