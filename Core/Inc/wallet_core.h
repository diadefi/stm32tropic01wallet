#ifndef WALLET_CORE_H
#define WALLET_CORE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define WALLET_SIGHASH_ALL 0x01U
#define WALLET_LEGACY_P2PKH_MAX_INPUTS 2U

/*
 * Current supported transaction shape:
 *   legacy P2PKH
 *   one input
 *   output 0 = payment
 *   output 1 = change
 *
 * Amounts are in satoshis. Script lengths currently support compact-size
 * single-byte lengths only, so keep scripts <= 252 bytes.
 */
typedef struct
{
    const uint8_t *prev_txid_le;
    uint32_t prev_vout;

    const uint8_t *prev_script_pubkey;
    uint32_t prev_script_pubkey_len;

    const uint8_t *pay_script_pubkey;
    uint32_t pay_script_pubkey_len;
    uint64_t pay_value_sats;

    const uint8_t *change_script_pubkey;
    uint32_t change_script_pubkey_len;
    uint64_t change_value_sats;

    uint32_t sequence;
    uint32_t locktime;
} wallet_legacy_p2pkh_tx_t;

typedef struct
{
    const uint8_t *prev_txid_le;
    uint32_t prev_vout;

    const uint8_t *prev_script_pubkey;
    uint32_t prev_script_pubkey_len;
    uint64_t input_value_sats;

    uint32_t sequence;
} wallet_legacy_p2pkh_input_t;

typedef struct
{
    const wallet_legacy_p2pkh_input_t *inputs;
    uint32_t input_count;

    const uint8_t *pay_script_pubkey;
    uint32_t pay_script_pubkey_len;
    uint64_t pay_value_sats;

    const uint8_t *change_script_pubkey;
    uint32_t change_script_pubkey_len;
    uint64_t change_value_sats;

    uint32_t locktime;
} wallet_legacy_p2pkh_multi_tx_t;

int wallet_bytes_to_hex(const uint8_t *in,
                        uint32_t in_len,
                        char *out,
                        uint32_t out_size);

int wallet_build_legacy_p2pkh_sighash_preimage(
    const wallet_legacy_p2pkh_tx_t *tx,
    uint8_t *out,
    uint32_t out_size,
    uint32_t *out_len);

int wallet_build_signed_legacy_p2pkh_tx(
    const wallet_legacy_p2pkh_tx_t *tx,
    const uint8_t *signature_der_sighash,
    uint32_t signature_der_sighash_len,
    const uint8_t *pubkey33,
    uint8_t *out,
    uint32_t out_size,
    uint32_t *out_len,
    uint32_t *script_sig_len_out);

/*
 * Higher-level signing API for the next host-driven phase.
 * input_value_sats is not part of legacy P2PKH sighash serialization, but it
 * is accepted here so callers can keep fee/policy data with the signing call.
 */
int wallet_sign_p2pkh_2out_tx(
    const uint8_t prev_txid_le[32],
    uint32_t prev_vout,
    const uint8_t *prev_script_pubkey,
    uint32_t prev_script_pubkey_len,
    uint64_t input_value_sats,

    const uint8_t *recipient_script_pubkey,
    uint32_t recipient_script_pubkey_len,
    uint64_t recipient_value_sats,

    const uint8_t *change_script_pubkey,
    uint32_t change_script_pubkey_len,
    uint64_t change_value_sats,

    const uint8_t private_key[32],

    uint8_t *out_raw_tx,
    uint32_t out_raw_tx_size,
    uint32_t *out_raw_tx_len);

int wallet_sign_p2pkh_multi_2out_tx(
    const wallet_legacy_p2pkh_input_t *inputs,
    uint32_t input_count,

    const uint8_t *recipient_script_pubkey,
    uint32_t recipient_script_pubkey_len,
    uint64_t recipient_value_sats,

    const uint8_t *change_script_pubkey,
    uint32_t change_script_pubkey_len,
    uint64_t change_value_sats,

    const uint8_t private_key[32],

    uint8_t *out_raw_tx,
    uint32_t out_raw_tx_size,
    uint32_t *out_raw_tx_len);

#ifdef __cplusplus
}
#endif

#endif /* WALLET_CORE_H */
