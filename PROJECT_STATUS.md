# Project Status

This is a working prototype of a Bitcoin hardware wallet built with an STM32U5 board and a TROPIC01 secure element.

The project currently focuses on the core signing flow: checking a transaction on-device, requiring approval, unlocking the key path, using TROPIC01 as an auth gate, and returning a signed transaction over UART.

# Current Snapshot

The public repo is based on a validated hardware checkpoint. The board was built, flashed, and tested with PowerShell regression scripts against Bitcoin Core regtest.

strongest validated checkpoint reached:

ALL_REGRESSIONS_PASS


- STM32 firmware builds and flashes.
- The board accepts wallet commands over UART.
- Regtest Bitcoin transactions can be signed end-to-end.
- Device policy rejects unsafe transactions before signing.
- CHECK and SIGN are bound together.
- CHECK_ID commits to the approved transaction.
- Signing requires an unlock session.
- TROPIC01 is used as an authentication gate.
- Regression scripts cover the main positive and negative flows.

Model

TROPIC01 is currently used as an auth gate.

Bitcoin secp256k1 signing still happens in STM32 firmware because the available TROPIC01 signing curves do not expose Bitcoin secp256k1 signing for this prototype.This retains open-source architecture best 

 Milestone
- Regtest signing loop working
- Device-side policy checks
- Firmware-enforced CHECK-before-SIGN
- CHECK_ID transaction commitment
- User confirmation flow
- PIN/session unlock model
- TROPIC01 auth gate
- PSBT-like command format
- Testnet-readiness groundwork

The next major work is SegWit/testnet signing, cleaner board portability, and a 

 Next: custom STM32U5 + TROPIC01 hardware-wallet architecture with stronger display/button approval, better key handling, and testnet-first validation. -> startup MVP

