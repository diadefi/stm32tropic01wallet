#ifndef WALLET_BUILD_CONFIG_H
#define WALLET_BUILD_CONFIG_H

/*
 * Prototype safety switch.
 *
 * Current working model:
 * - Bitcoin private key is still a dev key in MCU firmware.
 * - TROPIC01 is currently used as an authorization gate before that key is released.
 *
 * Set WALLET_ENABLE_DEV_PRIVATE_KEY to 0 only after a real TROPIC-backed
 * signing/key path is implemented.
 */
#define WALLET_ENABLE_DEV_PRIVATE_KEY 0

#if WALLET_ENABLE_DEV_PRIVATE_KEY
#define WALLET_DEV_KEY_ENABLED_STRING "0"
#define WALLET_KEY_MODEL_STRING "KDF_AES_GCM_WRAPPED_SECP256K1_KEY_BLOB_TROPIC_AUTH_GATE"
#else
#define WALLET_DEV_KEY_ENABLED_STRING "0"
#define WALLET_KEY_MODEL_STRING "KDF_AES_GCM_WRAPPED_SECP256K1_KEY_BLOB_TROPIC_AUTH_GATE"
#endif

#define WALLET_APP_NAME_STRING       "STM32_BITCOIN_HWALLET_PROTO"
#define WALLET_APP_VERSION_STRING "0.5.0-kdf-aead-keyblob"
#define WALLET_POLICY_MODEL_STRING   "REGTEST_TESTNET_P2PKH_ALLOWLIST_V1"
#define WALLET_BOARD_STRING          "NUCLEO-U575ZI-Q"
#define WALLET_MCU_STRING            "STM32U575ZITxQ"
#define WALLET_SE_STRING             "TROPIC01"

/*
 * C9.6 explicit activation: allow TESTNET signing only.
 *
 * This does not enable MAINNET signing, direct TROPIC secp256k1 signing,
 * host PRIVKEY use, broadcast, or BIP84/device-derived-key signing.
 */
#define WALLET_TESTNET_SIGNING_BUILD_FLAG 1
#define WALLET_MAINNET_SIGNING_BUILD_FLAG 0

#endif /* WALLET_BUILD_CONFIG_H */

#define WALLET_PLAINTEXT_DEV_KEY_COMPILED_IN_STRING "0"




