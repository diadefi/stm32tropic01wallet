#include "wallet_core.h"

#include "psa/crypto.h"

#include "ecdsa.h"
#include "secp256k1.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

static void wallet_core_secure_zero(void *buf, size_t len)
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

static int wallet_buf_append(uint8_t *out,
                             uint32_t out_size,
                             uint32_t *pos,
                             const uint8_t *data,
                             uint32_t data_len)
{
    if (out == NULL || pos == NULL)
    {
        return 0;
    }

    if (data_len > 0U && data == NULL)
    {
        return 0;
    }

    if (*pos > out_size)
    {
        return 0;
    }

    if (data_len > (out_size - *pos))
    {
        return 0;
    }

    if (data_len > 0U)
    {
        memcpy(&out[*pos], data, data_len);
    }

    *pos += data_len;

    return 1;
}

static int wallet_buf_append_u8(uint8_t *out,
                                uint32_t out_size,
                                uint32_t *pos,
                                uint8_t value)
{
    return wallet_buf_append(out, out_size, pos, &value, 1U);
}

static int wallet_buf_append_u32_le(uint8_t *out,
                                    uint32_t out_size,
                                    uint32_t *pos,
                                    uint32_t value)
{
    uint8_t tmp[4];

    tmp[0] = (uint8_t)(value & 0xFFU);
    tmp[1] = (uint8_t)((value >> 8) & 0xFFU);
    tmp[2] = (uint8_t)((value >> 16) & 0xFFU);
    tmp[3] = (uint8_t)((value >> 24) & 0xFFU);

    return wallet_buf_append(out, out_size, pos, tmp, 4U);
}

static int wallet_buf_append_u64_le(uint8_t *out,
                                    uint32_t out_size,
                                    uint32_t *pos,
                                    uint64_t value)
{
    uint8_t tmp[8];

    tmp[0] = (uint8_t)(value & 0xFFU);
    tmp[1] = (uint8_t)((value >> 8) & 0xFFU);
    tmp[2] = (uint8_t)((value >> 16) & 0xFFU);
    tmp[3] = (uint8_t)((value >> 24) & 0xFFU);
    tmp[4] = (uint8_t)((value >> 32) & 0xFFU);
    tmp[5] = (uint8_t)((value >> 40) & 0xFFU);
    tmp[6] = (uint8_t)((value >> 48) & 0xFFU);
    tmp[7] = (uint8_t)((value >> 56) & 0xFFU);

    return wallet_buf_append(out, out_size, pos, tmp, 8U);
}

int wallet_bytes_to_hex(const uint8_t *in,
                        uint32_t in_len,
                        char *out,
                        uint32_t out_size)
{
    static const char hex_chars[] = "0123456789abcdef";

    if (in == NULL || out == NULL)
    {
        return 0;
    }

    if (out_size < ((in_len * 2U) + 1U))
    {
        return 0;
    }

    for (uint32_t i = 0; i < in_len; i++)
    {
        out[i * 2U] = hex_chars[(in[i] >> 4) & 0x0FU];
        out[(i * 2U) + 1U] = hex_chars[in[i] & 0x0FU];
    }

    out[in_len * 2U] = '\0';

    return 1;
}

int wallet_build_legacy_p2pkh_sighash_preimage(
    const wallet_legacy_p2pkh_tx_t *tx,
    uint8_t *out,
    uint32_t out_size,
    uint32_t *out_len)
{
    uint32_t p = 0;

    if (tx == NULL || out == NULL || out_len == NULL)
    {
        return -1;
    }

    if (tx->prev_txid_le == NULL ||
        tx->prev_script_pubkey == NULL ||
        tx->pay_script_pubkey == NULL ||
        tx->change_script_pubkey == NULL)
    {
        return -2;
    }

    if (tx->prev_script_pubkey_len > 252U ||
        tx->pay_script_pubkey_len > 252U ||
        tx->change_script_pubkey_len > 252U)
    {
        return -3;
    }

    memset(out, 0, out_size);

    if (!wallet_buf_append_u32_le(out, out_size, &p, 1U)) return -10;
    if (!wallet_buf_append_u8(out, out_size, &p, 1U)) return -11;
    if (!wallet_buf_append(out, out_size, &p, tx->prev_txid_le, 32U)) return -12;
    if (!wallet_buf_append_u32_le(out, out_size, &p, tx->prev_vout)) return -13;
    if (!wallet_buf_append_u8(out, out_size, &p, (uint8_t)tx->prev_script_pubkey_len)) return -14;
    if (!wallet_buf_append(out, out_size, &p, tx->prev_script_pubkey, tx->prev_script_pubkey_len)) return -15;
    if (!wallet_buf_append_u32_le(out, out_size, &p, tx->sequence)) return -16;
    if (!wallet_buf_append_u8(out, out_size, &p, 2U)) return -17;

    if (!wallet_buf_append_u64_le(out, out_size, &p, tx->pay_value_sats)) return -18;
    if (!wallet_buf_append_u8(out, out_size, &p, (uint8_t)tx->pay_script_pubkey_len)) return -19;
    if (!wallet_buf_append(out, out_size, &p, tx->pay_script_pubkey, tx->pay_script_pubkey_len)) return -20;

    if (!wallet_buf_append_u64_le(out, out_size, &p, tx->change_value_sats)) return -21;
    if (!wallet_buf_append_u8(out, out_size, &p, (uint8_t)tx->change_script_pubkey_len)) return -22;
    if (!wallet_buf_append(out, out_size, &p, tx->change_script_pubkey, tx->change_script_pubkey_len)) return -23;

    if (!wallet_buf_append_u32_le(out, out_size, &p, tx->locktime)) return -24;
    if (!wallet_buf_append_u32_le(out, out_size, &p, WALLET_SIGHASH_ALL)) return -25;

    *out_len = p;

    return 0;
}

int wallet_build_signed_legacy_p2pkh_tx(
    const wallet_legacy_p2pkh_tx_t *tx,
    const uint8_t *signature_der_sighash,
    uint32_t signature_der_sighash_len,
    const uint8_t *pubkey33,
    uint8_t *out,
    uint32_t out_size,
    uint32_t *out_len,
    uint32_t *script_sig_len_out)
{
    uint32_t p = 0;
    uint32_t script_sig_len = 0;

    if (tx == NULL ||
        signature_der_sighash == NULL ||
        pubkey33 == NULL ||
        out == NULL ||
        out_len == NULL ||
        script_sig_len_out == NULL)
    {
        return -1;
    }

    if (tx->prev_txid_le == NULL ||
        tx->pay_script_pubkey == NULL ||
        tx->change_script_pubkey == NULL)
    {
        return -2;
    }

    if (signature_der_sighash_len == 0U ||
        signature_der_sighash_len > 81U)
    {
        return -3;
    }

    if (pubkey33[0] != 0x02 && pubkey33[0] != 0x03)
    {
        return -4;
    }

    if (tx->pay_script_pubkey_len > 252U ||
        tx->change_script_pubkey_len > 252U)
    {
        return -5;
    }

    script_sig_len = 1U + signature_der_sighash_len + 1U + 33U;

    if (script_sig_len > 252U)
    {
        return -6;
    }

    memset(out, 0, out_size);

    if (!wallet_buf_append_u32_le(out, out_size, &p, 1U)) return -10;
    if (!wallet_buf_append_u8(out, out_size, &p, 1U)) return -11;
    if (!wallet_buf_append(out, out_size, &p, tx->prev_txid_le, 32U)) return -12;
    if (!wallet_buf_append_u32_le(out, out_size, &p, tx->prev_vout)) return -13;

    if (!wallet_buf_append_u8(out, out_size, &p, (uint8_t)script_sig_len)) return -14;
    if (!wallet_buf_append_u8(out, out_size, &p, (uint8_t)signature_der_sighash_len)) return -15;
    if (!wallet_buf_append(out, out_size, &p, signature_der_sighash, signature_der_sighash_len)) return -16;
    if (!wallet_buf_append_u8(out, out_size, &p, 0x21U)) return -17;
    if (!wallet_buf_append(out, out_size, &p, pubkey33, 33U)) return -18;

    if (!wallet_buf_append_u32_le(out, out_size, &p, tx->sequence)) return -19;
    if (!wallet_buf_append_u8(out, out_size, &p, 2U)) return -20;

    if (!wallet_buf_append_u64_le(out, out_size, &p, tx->pay_value_sats)) return -21;
    if (!wallet_buf_append_u8(out, out_size, &p, (uint8_t)tx->pay_script_pubkey_len)) return -22;
    if (!wallet_buf_append(out, out_size, &p, tx->pay_script_pubkey, tx->pay_script_pubkey_len)) return -23;

    if (!wallet_buf_append_u64_le(out, out_size, &p, tx->change_value_sats)) return -24;
    if (!wallet_buf_append_u8(out, out_size, &p, (uint8_t)tx->change_script_pubkey_len)) return -25;
    if (!wallet_buf_append(out, out_size, &p, tx->change_script_pubkey, tx->change_script_pubkey_len)) return -26;

    if (!wallet_buf_append_u32_le(out, out_size, &p, tx->locktime)) return -27;

    *out_len = p;
    *script_sig_len_out = script_sig_len;

    return 0;
}

static int wallet_build_legacy_p2pkh_multi_sighash_preimage(
    const wallet_legacy_p2pkh_multi_tx_t *tx,
    uint32_t signing_input_index,
    uint8_t *out,
    uint32_t out_size,
    uint32_t *out_len)
{
    uint32_t p = 0;

    if (tx == NULL || tx->inputs == NULL || out == NULL || out_len == NULL)
    {
        return -1;
    }

    if (tx->input_count == 0U ||
        tx->input_count > WALLET_LEGACY_P2PKH_MAX_INPUTS ||
        signing_input_index >= tx->input_count)
    {
        return -2;
    }

    if (tx->pay_script_pubkey == NULL ||
        tx->change_script_pubkey == NULL ||
        tx->pay_script_pubkey_len > 252U ||
        tx->change_script_pubkey_len > 252U)
    {
        return -3;
    }

    memset(out, 0, out_size);

    if (!wallet_buf_append_u32_le(out, out_size, &p, 1U)) return -10;
    if (!wallet_buf_append_u8(out, out_size, &p, (uint8_t)tx->input_count)) return -11;

    for (uint32_t i = 0; i < tx->input_count; i++)
    {
        const wallet_legacy_p2pkh_input_t *input = &tx->inputs[i];
        uint32_t script_len = (i == signing_input_index) ?
                              input->prev_script_pubkey_len : 0U;

        if (input->prev_txid_le == NULL ||
            input->prev_script_pubkey == NULL ||
            input->prev_script_pubkey_len > 252U)
        {
            return -12;
        }

        if (!wallet_buf_append(out, out_size, &p, input->prev_txid_le, 32U)) return -13;
        if (!wallet_buf_append_u32_le(out, out_size, &p, input->prev_vout)) return -14;
        if (!wallet_buf_append_u8(out, out_size, &p, (uint8_t)script_len)) return -15;
        if (script_len > 0U &&
            !wallet_buf_append(out, out_size, &p, input->prev_script_pubkey, script_len)) return -16;
        if (!wallet_buf_append_u32_le(out, out_size, &p, input->sequence)) return -17;
    }

    if (!wallet_buf_append_u8(out, out_size, &p, 2U)) return -18;

    if (!wallet_buf_append_u64_le(out, out_size, &p, tx->pay_value_sats)) return -19;
    if (!wallet_buf_append_u8(out, out_size, &p, (uint8_t)tx->pay_script_pubkey_len)) return -20;
    if (!wallet_buf_append(out, out_size, &p, tx->pay_script_pubkey, tx->pay_script_pubkey_len)) return -21;

    if (!wallet_buf_append_u64_le(out, out_size, &p, tx->change_value_sats)) return -22;
    if (!wallet_buf_append_u8(out, out_size, &p, (uint8_t)tx->change_script_pubkey_len)) return -23;
    if (!wallet_buf_append(out, out_size, &p, tx->change_script_pubkey, tx->change_script_pubkey_len)) return -24;

    if (!wallet_buf_append_u32_le(out, out_size, &p, tx->locktime)) return -25;
    if (!wallet_buf_append_u32_le(out, out_size, &p, WALLET_SIGHASH_ALL)) return -26;

    *out_len = p;
    return 0;
}

static int wallet_build_signed_legacy_p2pkh_multi_tx(
    const wallet_legacy_p2pkh_multi_tx_t *tx,
    const uint8_t signatures_der_sighash[WALLET_LEGACY_P2PKH_MAX_INPUTS][81],
    const uint32_t signature_der_sighash_lens[WALLET_LEGACY_P2PKH_MAX_INPUTS],
    const uint8_t *pubkey33,
    uint8_t *out,
    uint32_t out_size,
    uint32_t *out_len)
{
    uint32_t p = 0;

    if (tx == NULL || tx->inputs == NULL ||
        signatures_der_sighash == NULL ||
        signature_der_sighash_lens == NULL ||
        pubkey33 == NULL ||
        out == NULL ||
        out_len == NULL)
    {
        return -1;
    }

    if (tx->input_count == 0U ||
        tx->input_count > WALLET_LEGACY_P2PKH_MAX_INPUTS)
    {
        return -2;
    }

    memset(out, 0, out_size);

    if (!wallet_buf_append_u32_le(out, out_size, &p, 1U)) return -10;
    if (!wallet_buf_append_u8(out, out_size, &p, (uint8_t)tx->input_count)) return -11;

    for (uint32_t i = 0; i < tx->input_count; i++)
    {
        const wallet_legacy_p2pkh_input_t *input = &tx->inputs[i];
        uint32_t sig_len = signature_der_sighash_lens[i];
        uint32_t script_sig_len = 1U + sig_len + 1U + 33U;

        if (input->prev_txid_le == NULL ||
            sig_len == 0U ||
            sig_len > 81U ||
            script_sig_len > 252U)
        {
            return -12;
        }

        if (!wallet_buf_append(out, out_size, &p, input->prev_txid_le, 32U)) return -13;
        if (!wallet_buf_append_u32_le(out, out_size, &p, input->prev_vout)) return -14;
        if (!wallet_buf_append_u8(out, out_size, &p, (uint8_t)script_sig_len)) return -15;
        if (!wallet_buf_append_u8(out, out_size, &p, (uint8_t)sig_len)) return -16;
        if (!wallet_buf_append(out, out_size, &p, signatures_der_sighash[i], sig_len)) return -17;
        if (!wallet_buf_append_u8(out, out_size, &p, 0x21U)) return -18;
        if (!wallet_buf_append(out, out_size, &p, pubkey33, 33U)) return -19;
        if (!wallet_buf_append_u32_le(out, out_size, &p, input->sequence)) return -20;
    }

    if (!wallet_buf_append_u8(out, out_size, &p, 2U)) return -21;

    if (!wallet_buf_append_u64_le(out, out_size, &p, tx->pay_value_sats)) return -22;
    if (!wallet_buf_append_u8(out, out_size, &p, (uint8_t)tx->pay_script_pubkey_len)) return -23;
    if (!wallet_buf_append(out, out_size, &p, tx->pay_script_pubkey, tx->pay_script_pubkey_len)) return -24;

    if (!wallet_buf_append_u64_le(out, out_size, &p, tx->change_value_sats)) return -25;
    if (!wallet_buf_append_u8(out, out_size, &p, (uint8_t)tx->change_script_pubkey_len)) return -26;
    if (!wallet_buf_append(out, out_size, &p, tx->change_script_pubkey, tx->change_script_pubkey_len)) return -27;

    if (!wallet_buf_append_u32_le(out, out_size, &p, tx->locktime)) return -28;

    *out_len = p;
    return 0;
}

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
    uint32_t *out_raw_tx_len)
{
    wallet_legacy_p2pkh_multi_tx_t tx;
    uint8_t pubkey33[33];
    uint8_t preimage[384];
    uint32_t preimage_len = 0;
    uint8_t hash1[32];
    uint8_t digest[32];
    uint8_t sig64[64];
    uint8_t sig_der[80];
    uint8_t sig_der_sighash[WALLET_LEGACY_P2PKH_MAX_INPUTS][81];
    uint32_t sig_der_sighash_lens[WALLET_LEGACY_P2PKH_MAX_INPUTS];
    size_t hash_len = 0;
    psa_status_t psa_ret;
    int der_len;
    int ret = 0;
    uint64_t input_sum = 0ULL;
    uint64_t output_sum;

    if (inputs == NULL ||
        input_count == 0U ||
        input_count > WALLET_LEGACY_P2PKH_MAX_INPUTS ||
        recipient_script_pubkey == NULL ||
        change_script_pubkey == NULL ||
        private_key == NULL ||
        out_raw_tx == NULL ||
        out_raw_tx_len == NULL)
    {
        return -1;
    }

    output_sum = recipient_value_sats + change_value_sats;
    if (output_sum < recipient_value_sats)
    {
        return -2;
    }

    for (uint32_t i = 0; i < input_count; i++)
    {
        if (inputs[i].input_value_sats > (UINT64_MAX - input_sum))
        {
            return -3;
        }
        input_sum += inputs[i].input_value_sats;
    }

    if (input_sum != 0ULL && input_sum < output_sum)
    {
        return -4;
    }

    memset(&tx, 0, sizeof(tx));
    memset(pubkey33, 0, sizeof(pubkey33));
    memset(preimage, 0, sizeof(preimage));
    memset(hash1, 0, sizeof(hash1));
    memset(digest, 0, sizeof(digest));
    memset(sig64, 0, sizeof(sig64));
    memset(sig_der, 0, sizeof(sig_der));
    memset(sig_der_sighash, 0, sizeof(sig_der_sighash));
    memset(sig_der_sighash_lens, 0, sizeof(sig_der_sighash_lens));

    ecdsa_get_public_key33(&secp256k1, private_key, pubkey33);

    if (pubkey33[0] != 0x02 && pubkey33[0] != 0x03)
    {
        ret = -5;
        goto cleanup;
    }

    tx.inputs = inputs;
    tx.input_count = input_count;
    tx.pay_script_pubkey = recipient_script_pubkey;
    tx.pay_script_pubkey_len = recipient_script_pubkey_len;
    tx.pay_value_sats = recipient_value_sats;
    tx.change_script_pubkey = change_script_pubkey;
    tx.change_script_pubkey_len = change_script_pubkey_len;
    tx.change_value_sats = change_value_sats;
    tx.locktime = 0U;

    for (uint32_t i = 0; i < input_count; i++)
    {
        if (wallet_build_legacy_p2pkh_multi_sighash_preimage(&tx,
                                                             i,
                                                             preimage,
                                                             sizeof(preimage),
                                                             &preimage_len) != 0)
        {
            ret = -6;
            goto cleanup;
        }

        hash_len = 0;
        psa_ret = psa_hash_compute(PSA_ALG_SHA_256,
                                   preimage,
                                   preimage_len,
                                   hash1,
                                   sizeof(hash1),
                                   &hash_len);

        if (psa_ret != PSA_SUCCESS || hash_len != 32U)
        {
            ret = -7;
            goto cleanup;
        }

        hash_len = 0;
        psa_ret = psa_hash_compute(PSA_ALG_SHA_256,
                                   hash1,
                                   sizeof(hash1),
                                   digest,
                                   sizeof(digest),
                                   &hash_len);

        if (psa_ret != PSA_SUCCESS || hash_len != 32U)
        {
            ret = -8;
            goto cleanup;
        }

        if (ecdsa_sign_digest(&secp256k1,
                              private_key,
                              digest,
                              sig64,
                              NULL,
                              NULL) != 0)
        {
            ret = -9;
            goto cleanup;
        }

        der_len = ecdsa_sig_to_der(sig64, sig_der);

        if (der_len <= 0 || der_len > 80)
        {
            ret = -10;
            goto cleanup;
        }

        memcpy(sig_der_sighash[i], sig_der, (uint32_t)der_len);
        sig_der_sighash[i][der_len] = (uint8_t)WALLET_SIGHASH_ALL;
        sig_der_sighash_lens[i] = (uint32_t)der_len + 1U;

        wallet_core_secure_zero(preimage, sizeof(preimage));
        wallet_core_secure_zero(hash1, sizeof(hash1));
        wallet_core_secure_zero(digest, sizeof(digest));
        wallet_core_secure_zero(sig64, sizeof(sig64));
        wallet_core_secure_zero(sig_der, sizeof(sig_der));
    }

    ret = wallet_build_signed_legacy_p2pkh_multi_tx(&tx,
                                                    sig_der_sighash,
                                                    sig_der_sighash_lens,
                                                    pubkey33,
                                                    out_raw_tx,
                                                    out_raw_tx_size,
                                                    out_raw_tx_len);

cleanup:
    wallet_core_secure_zero(pubkey33, sizeof(pubkey33));
    wallet_core_secure_zero(preimage, sizeof(preimage));
    wallet_core_secure_zero(hash1, sizeof(hash1));
    wallet_core_secure_zero(digest, sizeof(digest));
    wallet_core_secure_zero(sig64, sizeof(sig64));
    wallet_core_secure_zero(sig_der, sizeof(sig_der));
    wallet_core_secure_zero(sig_der_sighash, sizeof(sig_der_sighash));
    wallet_core_secure_zero(sig_der_sighash_lens, sizeof(sig_der_sighash_lens));
    wallet_core_secure_zero(&tx, sizeof(tx));
    return ret;
}

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
    uint32_t *out_raw_tx_len)
{
    wallet_legacy_p2pkh_tx_t tx;
    uint8_t pubkey33[33];
    uint8_t preimage[256];
    uint32_t preimage_len = 0;
    uint8_t hash1[32];
    uint8_t digest[32];
    uint8_t sig64[64];
    uint8_t sig_der[80];
    uint8_t sig_der_sighash[81];
    uint32_t sig_der_sighash_len = 0;
    uint32_t script_sig_len = 0;
    size_t hash_len = 0;
    psa_status_t psa_ret;
    int der_len;
    int ret = 0;
    uint64_t output_sum;

    if (prev_txid_le == NULL ||
        prev_script_pubkey == NULL ||
        recipient_script_pubkey == NULL ||
        change_script_pubkey == NULL ||
        private_key == NULL ||
        out_raw_tx == NULL ||
        out_raw_tx_len == NULL)
    {
        return -1;
    }

    output_sum = recipient_value_sats + change_value_sats;

    if (output_sum < recipient_value_sats)
    {
        return -2;
    }

    if (input_value_sats != 0ULL && input_value_sats < output_sum)
    {
        return -3;
    }

    memset(pubkey33, 0, sizeof(pubkey33));
    memset(preimage, 0, sizeof(preimage));
    memset(hash1, 0, sizeof(hash1));
    memset(digest, 0, sizeof(digest));
    memset(sig64, 0, sizeof(sig64));
    memset(sig_der, 0, sizeof(sig_der));
    memset(sig_der_sighash, 0, sizeof(sig_der_sighash));

    ecdsa_get_public_key33(&secp256k1, private_key, pubkey33);

    if (pubkey33[0] != 0x02 && pubkey33[0] != 0x03)
    {
        ret = -4;
        goto cleanup;
    }

    tx.prev_txid_le = prev_txid_le;
    tx.prev_vout = prev_vout;
    tx.prev_script_pubkey = prev_script_pubkey;
    tx.prev_script_pubkey_len = prev_script_pubkey_len;
    tx.pay_script_pubkey = recipient_script_pubkey;
    tx.pay_script_pubkey_len = recipient_script_pubkey_len;
    tx.pay_value_sats = recipient_value_sats;
    tx.change_script_pubkey = change_script_pubkey;
    tx.change_script_pubkey_len = change_script_pubkey_len;
    tx.change_value_sats = change_value_sats;
    tx.sequence = 0xFFFFFFFFU;
    tx.locktime = 0U;

    if (wallet_build_legacy_p2pkh_sighash_preimage(&tx,
                                                   preimage,
                                                   sizeof(preimage),
                                                   &preimage_len) != 0)
    {
        ret = -5;
        goto cleanup;
    }

    hash_len = 0;
    psa_ret = psa_hash_compute(PSA_ALG_SHA_256,
                               preimage,
                               preimage_len,
                               hash1,
                               sizeof(hash1),
                               &hash_len);

    if (psa_ret != PSA_SUCCESS || hash_len != 32U)
    {
        ret = -6;
        goto cleanup;
    }

    hash_len = 0;
    psa_ret = psa_hash_compute(PSA_ALG_SHA_256,
                               hash1,
                               sizeof(hash1),
                               digest,
                               sizeof(digest),
                               &hash_len);

    if (psa_ret != PSA_SUCCESS || hash_len != 32U)
    {
        ret = -7;
        goto cleanup;
    }

    if (ecdsa_sign_digest(&secp256k1,
                          private_key,
                          digest,
                          sig64,
                          NULL,
                          NULL) != 0)
    {
        ret = -8;
        goto cleanup;
    }

    der_len = ecdsa_sig_to_der(sig64, sig_der);

    if (der_len <= 0 || der_len > 80)
    {
        ret = -9;
        goto cleanup;
    }

    memcpy(sig_der_sighash, sig_der, (uint32_t)der_len);
    sig_der_sighash[der_len] = (uint8_t)WALLET_SIGHASH_ALL;
    sig_der_sighash_len = (uint32_t)der_len + 1U;

    ret = wallet_build_signed_legacy_p2pkh_tx(&tx,
                                              sig_der_sighash,
                                              sig_der_sighash_len,
                                              pubkey33,
                                              out_raw_tx,
                                              out_raw_tx_size,
                                              out_raw_tx_len,
                                              &script_sig_len);
    (void)script_sig_len;

cleanup:
    wallet_core_secure_zero(pubkey33, sizeof(pubkey33));
    wallet_core_secure_zero(preimage, sizeof(preimage));
    wallet_core_secure_zero(hash1, sizeof(hash1));
    wallet_core_secure_zero(digest, sizeof(digest));
    wallet_core_secure_zero(sig64, sizeof(sig64));
    wallet_core_secure_zero(sig_der, sizeof(sig_der));
    wallet_core_secure_zero(sig_der_sighash, sizeof(sig_der_sighash));
    return ret;
}
