# HardwarePrototype checkpoint

## Milestone

HardwarePrototype_SEKEYINFO_B1_ALL_REGRESSIONS_PASS

## Passing proof

- UART_PROBE_PASS
- STM32_REGTEST_FULL_LOOP_PASS
- LIVE_NEGATIVE_POLICY_REGRESSION_PASS
- ALL_REGRESSIONS_PASS

## Working commands

- VERSION
- POLICYINFO
- SEINFO
- SEKEYINFO
- SIGN

## Current Bitcoin signing model

Host transaction
-> STM32 policy validation
-> TROPIC01 init/auth gate
-> STM32 dev-key secp256k1 signing
-> raw transaction returned

## Important truth

The Bitcoin private key is still a development key in STM32 firmware.

VERSION reports:

KEY_MODEL=DEV_KEY_IN_MCU_TROPIC_AUTH_GATE
DEV_KEY_ENABLED=1

## TROPIC01 capability result

SEKEYINFO reports:

TROPIC_ECDSA_SIGN=1
TROPIC_EDDSA_SIGN=1
TROPIC_CURVE_P256=1
TROPIC_CURVE_ED25519=1
TROPIC_CURVE_SECP256K1=0
BITCOIN_DIRECT_TROPIC_SIGNING=0

## Meaning

TROPIC01 is working as a real SPI/libtropic device and authorization gate.

TROPIC01 is not currently the Bitcoin private-key holder.

Direct Bitcoin signing inside TROPIC01 is not supported by the exposed curve set because Bitcoin requires secp256k1.

## Do not do casually

Do not run experimental SEKEYTEST / L3 ECC operations on the main working tree without making a fresh backup first.

## Next tracks

1. Demo/release packaging:
   - keep current firmware stable
   - keep all regression scripts passing
   - document the prototype honestly

2. Production key architecture:
   - choose secp256k1-capable secure signing hardware, or
   - keep TROPIC01 as authorization/attestation and use another protected secp256k1 key path

3. TROPIC L3 research:
   - only in a separate copy/backup
   - add small diagnostics before any key generate/read/sign test

## C1.1 unlock-secret gate - PASS

Milestone:

HardwarePrototype_C1_1_UNLOCK_SECRET_ALL_REGRESSIONS_PASS

Behavior proven:

- Missing unlock secret rejects signing:
  ERR POLICY -22

- Wrong unlock secret rejects signing:
  ERR POLICY -23

- Correct unlock secret signs:
  UNLOCK_SECRET=mvp-regtest-unlock
  HOST_TX_GENERATOR_PASS

- Existing policy regressions still pass:
  LIVE_NEGATIVE_POLICY_REGRESSION_PASS
  ALL_REGRESSIONS_PASS

Current key model:

- Bitcoin private key is still the development key path.
- This milestone only adds a pre-key-use unlock gate.
- Encrypted key blob is not implemented yet.

Next milestone:

C1.2_ENCRYPTED_KEY_BLOB_MVP

Target:

- Remove obvious plaintext private key array from firmware.
- Store encrypted secp256k1 key blob.
- Use unlock secret to derive unwrap key.
- Decrypt only into RAM for signing.
- Wipe RAM key after signing.

## C1.2 encrypted key blob + truthful labels - PASS

Milestone:

HardwarePrototype_C1_2_KEYBLOB_LABELS_ALL_REGRESSIONS_PASS

Confirmed behavior:

- Missing unlock secret rejects signing:
  ERR POLICY -22

- Wrong unlock secret rejects signing:
  ERR POLICY -23

- Correct unlock secret unwraps key blob and signs:
  HOST_TX_GENERATOR_PASS

- Negative live policy regression still passes:
  LIVE_NEGATIVE_POLICY_REGRESSION_PASS

- Master regression still passes:
  ALL_REGRESSIONS_PASS

Truthful reported key model:

- CURRENT_BITCOIN_KEY_MODEL=PIN_WRAPPED_SECP256K1_KEY_BLOB_TROPIC_AUTH_GATE
- CURRENT_DEV_KEY_ENABLED=0
- TROPIC_CURVE_SECP256K1=0
- BITCOIN_DIRECT_TROPIC_SIGNING=0

Current architecture:

Host command
-> STM32 policy check
-> unlock secret required
-> TROPIC01 authorization gate
-> encrypted secp256k1 key blob unwrap in STM32 RAM
-> STM32 signs
-> RAM key wiped after use

Honest security status:

This is still an MVP. The Bitcoin key is no longer an obvious plaintext key array, but the current blob wrapper is not production-grade AEAD. TROPIC01 still gates authorization but does not directly sign secp256k1.

## C1.3 plaintext-key reference cleanup - PASS

Milestone:

HardwarePrototype_C1_3_NO_PLAINTEXT_REFS_ALL_REGRESSIONS_PASS

Confirmed:

- Dangerous old plaintext key references were removed from debug/test source files.
- UART probe still passes.
- SEKEYINFO reports:
  CURRENT_BITCOIN_KEY_MODEL=PIN_WRAPPED_SECP256K1_KEY_BLOB_TROPIC_AUTH_GATE
  CURRENT_DEV_KEY_ENABLED=0
  TROPIC_CURVE_SECP256K1=0
  BITCOIN_DIRECT_TROPIC_SIGNING=0

- Live negative policy regression still passes.
- Master regression still passes:
  ALL_REGRESSIONS_PASS

Current architecture:

Host command
-> STM32 policy check
-> unlock secret required
-> TROPIC01 authorization gate
-> encrypted secp256k1 key blob unwrap in STM32 RAM
-> STM32 signs
-> RAM key wiped after use

Next milestone:

C1.4 regression hardening

Targets:

- Add explicit missing-unlock rejection test to wallet_regtest_live_negative_policy.ps1.
- Add explicit wrong-unlock rejection test to wallet_regtest_live_negative_policy.ps1.
- Add probe assertions for key-model truth labels.
- Add source-audit script for plaintext key remnants.

## C1.4 hardened regression suite - PASS

Milestone:

HardwarePrototype_C1_4_HARDENED_REGRESSION_ALL_PASS

Confirmed:

- Source audit passes:
  SOURCE_AUDIT_PASS

- Truth-label assertions pass:
  TRUTH_LABEL_ASSERT_PASS

- Unlock-gate regression passes:
  MISSING_UNLOCK_REJECTED -> ERR POLICY -22
  WRONG_UNLOCK_REJECTED -> ERR POLICY -23
  UNLOCK_GATE_REGRESSION_PASS

- Positive full regtest loop still passes.
- Live negative policy regression still passes.
- Master suite passes:
  ALL_REGRESSIONS_PASS

Current key model:

- CURRENT_BITCOIN_KEY_MODEL=PIN_WRAPPED_SECP256K1_KEY_BLOB_TROPIC_AUTH_GATE
- CURRENT_DEV_KEY_ENABLED=0
- TROPIC_CURVE_SECP256K1=0
- BITCOIN_DIRECT_TROPIC_SIGNING=0

Current architecture:

Host command
-> STM32 policy check
-> unlock secret required
-> TROPIC01 authorization gate
-> encrypted secp256k1 key blob unwrap in STM32 RAM
-> STM32 signs
-> RAM key wiped after use

Next milestone:

C1.5_AEAD_KEY_BLOB

Target:

- Replace MVP XOR/SHA key blob wrapper with PSA AEAD if supported.
- Preferred: PSA AES-GCM-256.
- Fallback: PSA AES-CTR + HMAC-SHA256 style construction if AES-GCM is unavailable.
- Keep all existing regressions passing.

## C1.5 AES-GCM key blob - PASS

Milestone:

HardwarePrototype_C1_5_AES_GCM_KEYBLOB_ALL_PASS

Confirmed:

- AES-GCM key blob firmware builds and links.
- Missing unlock secret rejects signing:
  ERR POLICY -22

- Wrong unlock secret rejects signing:
  ERR POLICY -23

- Correct unlock secret decrypts AES-GCM key blob and signs.
- Hardened master suite still passes:
  ALL_REGRESSIONS_PASS

Current key model:

- AES_GCM_WRAPPED_SECP256K1_KEY_BLOB_TROPIC_AUTH_GATE
- CURRENT_DEV_KEY_ENABLED=0
- TROPIC_CURVE_SECP256K1=0
- BITCOIN_DIRECT_TROPIC_SIGNING=0

Current architecture:

Host command
-> STM32 policy check
-> unlock secret required
-> TROPIC01 authorization gate
-> AES-GCM authenticated key-blob decrypt in STM32 RAM
-> STM32 signs
-> RAM key wiped after use

Notes:

- The key blob now uses PSA AES-GCM authenticated decryption instead of the earlier XOR/SHA wrapper.
- This is still an MVP because unlock_secret is not yet processed by a slow password KDF.
- Added minimal unused MbedTLS link shims to satisfy unused TF-PSA/MbedTLS objects pulled into the build.

## C1.7 host sync hardening - PASS

Milestone:

HardwarePrototype_C1_7_HOST_SYNC_HARDENED_ALL_PASS

Confirmed:

- Host generator now drains stale UART output.
- Host generator forces a fresh VERSION/READY sync before SIGN.
- Host generator clears serial buffer immediately before SIGN.
- Host generator only accepts RAW_TX or ERR POLICY from the post-SIGN response window.
- Back-to-back signing regression passes:
  HOST_SYNC_REGRESSION_PASS

- Full hardened master suite passes:
  ALL_REGRESSIONS_PASS

Current firmware/key model:

- VERSION=0.5.0-kdf-aead-keyblob
- CURRENT_BITCOIN_KEY_MODEL=KDF_AES_GCM_WRAPPED_SECP256K1_KEY_BLOB_TROPIC_AUTH_GATE
- CURRENT_DEV_KEY_ENABLED=0
- TROPIC_CURVE_SECP256K1=0
- BITCOIN_DIRECT_TROPIC_SIGNING=0

Current test stack:

- UART_PROBE
- HOST_SYNC
- POSITIVE_FULL_LOOP
- NEGATIVE_POLICY
- SOURCE_AUDIT
- TRUTH_LABEL_ASSERTIONS
- UNLOCK_GATE

## C1.8 clean expected-error output - PASS

Milestone:

HardwarePrototype_C1_8_CLEAN_EXPECTED_ERRORS_ALL_PASS

Confirmed:

- Expected wallet policy rejections no longer produce PowerShell stack traces.
- wallet_generate_tx_command.ps1 now exits 2 for expected wallet ERR POLICY responses instead of throwing.
- Negative wrappers still assert expected errors:
  ERR POLICY -22
  ERR POLICY -23
  ERR POLICY -35
  ERR POLICY -38
  ERR POLICY -39
  ERR POLICY -40
  ERR POLICY -41
  ERR POLICY -42

- Full hardened master suite passes:
  ALL_REGRESSIONS_PASS

Current key model:

- VERSION=0.5.0-kdf-aead-keyblob
- CURRENT_BITCOIN_KEY_MODEL=KDF_AES_GCM_WRAPPED_SECP256K1_KEY_BLOB_TROPIC_AUTH_GATE
- CURRENT_DEV_KEY_ENABLED=0
- TROPIC_CURVE_SECP256K1=0
- BITCOIN_DIRECT_TROPIC_SIGNING=0

Current hardened host suite:

- UART_PROBE
- HOST_SYNC
- POSITIVE_FULL_LOOP
- NEGATIVE_POLICY
- SOURCE_AUDIT
- TRUTH_LABEL_ASSERTIONS
- UNLOCK_GATE

## C2.0 device identity reporting - PASS

Milestone:

HardwarePrototype_C2_0_DEVICE_IDENTITY_REPORTING_ALL_PASS

Confirmed:

- Firmware prompt now exposes:
  IDENTITY
  ADDR
  PUBKEY
  SCRIPT

- IDENTITY command validates:
  IDENTITY_VERSION=C2.0_DEVICE_IDENTITY_REPORTING
  NETWORK=REGTEST
  ADDRESS=mrCDrCybB6J1vRfbwM5hemdJz73FwDBC8r
  PUBKEY_COMPRESSED=0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798
  SCRIPT_P2PKH=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac
  CURRENT_BITCOIN_KEY_MODEL=KDF_AES_GCM_WRAPPED_SECP256K1_KEY_BLOB_TROPIC_AUTH_GATE
  CURRENT_DEV_KEY_ENABLED=0

- Master regression still passes:
  ALL_REGRESSIONS_PASS

Note:

The cosmetic VERSION= line may still report the prior app version. C2.0 validation is based on IDENTITY_VERSION and the identity command contents.

## C2.2 signing confirmation transcript - PASS

Milestone:

HardwarePrototype_C2_2_SIGNING_CONFIRMATION_TRANSCRIPT_ALL_PASS

Confirmed:

- Host generator now prints a signing confirmation transcript.
- Transcript includes:
  TRANSCRIPT_VERSION=C2.2_HOST_CONFIRMATION_TRANSCRIPT
  TRANSCRIPT_SOURCE=HOST_FROM_DEVICE_IDENTITY_AND_SIGN_COMMAND
  SECURE_DISPLAY=0
  NETWORK
  DEVICE_NETWORK
  SPEND_FROM_DEVICE_ADDRESS
  SPEND_FROM_DEVICE_SCRIPT
  DEVICE_KEY_MODEL
  INPUT_TXID_LE
  INPUT_VOUT
  INPUT_SATS
  PREV_SCRIPT
  PAY_TO_SCRIPT
  PAY_SATS
  CHANGE_TO_SCRIPT
  CHANGE_SATS
  FEE_SATS
  UNLOCK_SECRET_PRESENT
  HOST_EXPECTS_DEVICE_POLICY_CHECK

- Successful signing reports:
  POLICY_DECISION=APPROVED_AND_SIGNED
  RAW_TX_PRESENT=1

- Expected rejection reports:
  POLICY_DECISION=REJECTED_BY_DEVICE
  DEVICE_ERROR=<ERR POLICY code>
  RAW_TX_PRESENT=0

- Full master suite passes:
  ALL_REGRESSIONS_PASS

MVP note:

This is a host-side confirmation transcript, not a secure-device display. It is useful for MVP demos and regression evidence, but it does not replace a trusted display/physical confirmation flow.

## C2.3 device-side transaction CHECK/SUMMARY - PASS

Milestone:

HardwarePrototype_C2_3_DEVICE_SIDE_TX_CHECK_SUMMARY_ALL_PASS

Confirmed:

- Firmware accepts command blocks ending with CHECK.
- CHECK returns a device-side transaction policy summary.
- CHECK does not sign.
- CHECK does not produce RAW_TX.
- CHECK does not require unlock secret.
- CHECK does not trigger TROPIC authorization.
- AUTH_COUNT remains unchanged across CHECK.
- Valid CHECK returns POLICY_DECISION=APPROVED.
- Bad payment script CHECK returns POLICY_DECISION=REJECTED with ERR POLICY -38.
- Existing SIGN path still works.
- Full master suite passes:
  ALL_REGRESSIONS_PASS

Current CHECK summary behavior:

- SUMMARY_BEGIN
- SUMMARY_VERSION=C2.3_DEVICE_POLICY_SUMMARY
- NETWORK=REGTEST
- SPEND_FROM_SCRIPT=<device own script>
- PAY_TO_SCRIPT=<allowlisted script>
- PAY_SATS=60000
- CHANGE_TO_SCRIPT=<device own script>
- CHANGE_SATS=30000
- FEE_SATS=10000
- POLICY_DECISION=APPROVED or REJECTED
- SIGNATURE_PRODUCED=0
- SUMMARY_END

MVP significance:

The STM32 can now evaluate and summarize a candidate transaction before signing. This moves the transaction-confirmation path closer to a real hardware-wallet model, where the device, not just the host, states what it is about to authorize.

## C2.3 device-side transaction CHECK/SUMMARY - PASS

Milestone:

HardwarePrototype_C2_3_DEVICE_SIDE_TX_CHECK_SUMMARY_ALL_PASS

Confirmed:

- Firmware accepts command blocks ending with CHECK.
- CHECK returns a device-side transaction policy summary.
- CHECK does not sign.
- CHECK does not produce RAW_TX.
- CHECK does not require unlock secret.
- CHECK does not trigger TROPIC authorization.
- AUTH_COUNT remains unchanged across CHECK.
- Valid CHECK returns POLICY_DECISION=APPROVED.
- Bad payment script CHECK returns POLICY_DECISION=REJECTED with ERR POLICY -38.
- Existing SIGN path still works.
- Full master suite passes:
  ALL_REGRESSIONS_PASS

Current CHECK summary behavior:

- SUMMARY_BEGIN
- SUMMARY_VERSION=C2.3_DEVICE_POLICY_SUMMARY
- NETWORK=REGTEST
- SPEND_FROM_SCRIPT=<device own script>
- PAY_TO_SCRIPT=<allowlisted script>
- PAY_SATS=60000
- CHANGE_TO_SCRIPT=<device own script>
- CHANGE_SATS=30000
- FEE_SATS=10000
- POLICY_DECISION=APPROVED or REJECTED
- SIGNATURE_PRODUCED=0
- SUMMARY_END

MVP significance:

The STM32 can now evaluate and summarize a candidate transaction before signing. This moves the transaction-confirmation path closer to a real hardware-wallet model, where the device, not just the host, states what it is about to authorize.

## C2.4 host requires device CHECK before SIGN - PASS

Milestone:

HardwarePrototype_C2_4_HOST_REQUIRES_DEVICE_CHECK_BEFORE_SIGN_ALL_PASS

Confirmed:

- Host transaction generator sends CHECK before SIGN.
- CHECK uses the same candidate transaction fields as SIGN.
- CHECK response includes SUMMARY_VERSION=C2.3_DEVICE_POLICY_SUMMARY.
- CHECK response includes POLICY_DECISION=APPROVED before host proceeds to SIGN.
- CHECK response includes SIGNATURE_PRODUCED=0.
- CHECK response does not contain RAW_TX.
- Host clears serial buffer after CHECK before sending SIGN.
- Positive regtest full-loop signs, broadcasts, mines, and verifies.
- Positive proof lines:
  DEVICE_CHECK_POLICY_DECISION=APPROVED
  DEVICE_CHECK_RAW_TX_PRESENT=0
  DEVICE_CHECK_SIGNATURE_PRODUCED=0
  DEVICE_CHECK_BEFORE_SIGN_PASS
  STM32_REGTEST_FULL_LOOP_PASS
- Full master suite passes:
  ALL_REGRESSIONS_PASS

MVP significance:

The host no longer asks the STM32 to sign immediately. It first requires the STM32 to evaluate and summarize the candidate transaction, then proceeds to SIGN only after the device-side CHECK approves the transaction candidate.

## C2.5 exact device CHECK summary binding - PASS

Milestone:

HardwarePrototype_C2_5_EXACT_DEVICE_CHECK_SUMMARY_BINDING_ALL_PASS

Confirmed:

- Host sends CHECK before SIGN.
- Device returns C2.3 CHECK summary.
- Host verifies SUMMARY_VERSION.
- Host verifies NETWORK.
- Host verifies SPEND_FROM_SCRIPT.
- Host verifies PAY_TO_SCRIPT.
- Host verifies PAY_SATS.
- Host verifies CHANGE_TO_SCRIPT.
- Host verifies CHANGE_SATS.
- Host verifies computed FEE_SATS.
- Host verifies POLICY_DECISION=APPROVED.
- Host verifies SIGNATURE_PRODUCED=0.
- Host rejects mismatched summaries before SIGN.
- CHECK produces no RAW_TX.
- SIGN produces RAW_TX only after CHECK passes.
- Full master suite passes:
  ALL_REGRESSIONS_PASS

MVP significance:

The host now verifies that the device-approved CHECK summary exactly matches the candidate transaction before requesting a signature.

## C2.6 device CHECK input binding - PASS

Milestone:

HardwarePrototype_C2_6_DEVICE_CHECK_INPUT_BINDING_ALL_PASS

Patch:

- Fixed firmware UART formatting for INPUT_SATS in Core\Src\wallet_uart.c.
- Changed CHECK summary INPUT_SATS printing from embedded-unsupported %llu formatting to %lu with an unsigned long cast.
- This fixed the device output from INPUT_SATS=lu to INPUT_SATS=100000.

Confirmed:

- Firmware clean/headless build passed with 0 errors, 1 warning.
- Firmware flashed and verified through STM32_Programmer_CLI over ST-LINK/SWD.
- Device CHECK summary now reports:
  INPUT_TXID_LE=<exact command TXID_LE>
  INPUT_VOUT=<exact command VOUT>
  INPUT_SATS=<exact command INPUT_SATS>
- Host verifies C2.6 summary fields exactly before SIGN.
- CHECK produces no RAW_TX.
- CHECK does not increment TROPIC AUTH_COUNT.
- SIGN still produces RAW_TX only after CHECK passes.
- Positive regtest full-loop signs, broadcasts, mines, and verifies.
- Full master suite passes:
  ALL_REGRESSIONS_PASS

Proof commands run:

- .\tools\wallet_device_check_summary_regression.ps1
- .\tools\wallet_regtest_full_loop.ps1
- .\tools\wallet_run_all_regressions.ps1

Operational note:

- Initial STM32_Programmer_CLI flash failed with ST-LINK DEV_CONNECT_ERR because stale CubeIDE debug/server processes were holding the probe.
- Stopped arm-none-eabi-gdb, ST-LINK_gdbserver, and stlinkserver; left STM32CubeIDE open.
- Flash then succeeded normally over SWD under hardware reset.

MVP significance:

The device CHECK summary is now bound to the input identity as well as outputs and fee. The host rejects any mismatch in TXID, VOUT, or INPUT_SATS before requesting SIGN, reducing the chance that host/device policy approval is accidentally applied to a different UTXO candidate.

## C2.7 host/device transcript consistency regression - PASS

Milestone:

HardwarePrototype_C2_7_TRANSCRIPT_CHECK_SIGN_CONSISTENCY_PASS

Added:

- tools\wallet_c2_7_transcript_check_sign_consistency_regression.ps1
- C2.7 consistency proof block in tools\wallet_generate_tx_command.ps1
- Master regression step C2_7_TRANSCRIPT_CHECK_SIGN_CONSISTENCY

Confirmed:

- Host transcript fields, device CHECK summary fields, and final SIGN command fields all agree before signing.
- Verified fields:
  NETWORK, TXID_LE, VOUT, INPUT_SATS, PREV_SCRIPT, PAY_SCRIPT, PAY_SATS, CHANGE_SCRIPT, CHANGE_SATS, FEE_SATS.
- Proof marker:
  C2_7_TRANSCRIPT_CHECK_SIGN_CONSISTENCY_PASS

MVP significance:

This proves the host pipeline is checking and signing the same transaction candidate, not just independently producing plausible transcript and CHECK data.

## C2.8 negative host-binding regression - PASS

Milestone:

HardwarePrototype_C2_8_NEGATIVE_HOST_BINDING_PASS

Added:

- tools\wallet_c2_8_negative_host_binding_regression.ps1
- Controlled host-side CheckBindingTamperField / CheckBindingTamperValue test hooks in tools\wallet_generate_tx_command.ps1
- Master regression step C2_8_NEGATIVE_HOST_BINDING

Confirmed tamper cases:

- PAY_SATS mismatch
- CHANGE_SATS mismatch
- INPUT_TXID_LE mismatch
- INPUT_VOUT mismatch
- INPUT_SATS mismatch
- FEE_SATS mismatch

Expected and observed result for every case:

- POLICY_DECISION=REJECTED_BY_HOST_CHECK_BINDING
- RAW_TX_PRESENT=0
- SIGN_SENT=0
- NO_SIGN_SENT

MVP significance:

This proves the host binding checks actually stop signing if the device CHECK summary does not exactly match the expected candidate transaction.

## C2.9 no SIGN after failed CHECK proof - PASS

Milestone:

HardwarePrototype_C2_9_NO_SIGN_AFTER_FAILED_CHECK_PASS

Updated:

- tools\wallet_regtest_live_negative_policy.ps1 now asserts failed CHECK stops before SIGN.
- tools\wallet_generate_tx_command.ps1 now emits SIGN_SENT=0 and NO_SIGN_SENT for device CHECK rejection.

Confirmed failed-CHECK cases:

- MAINNET / non-regtest rejected
- fee too high rejected
- pay too high rejected
- bad pay script rejected
- bad change script rejected
- bad input script rejected

Expected and observed result for every case:

- POLICY_DECISION=REJECTED_BY_DEVICE_CHECK
- RAW_TX_PRESENT=0
- SIGN_SENT=0
- NO_SIGN_SENT
- C2_9_NO_SIGN_AFTER_FAILED_CHECK_CONFIRMED

Full proof:

- .\tools\wallet_c2_7_transcript_check_sign_consistency_regression.ps1 passed.
- .\tools\wallet_c2_8_negative_host_binding_regression.ps1 passed.
- .\tools\wallet_regtest_live_negative_policy.ps1 passed with C2.9 assertions.
- .\tools\wallet_run_all_regressions.ps1 passed with ALL_REGRESSIONS_PASS.

MVP significance:

The host now has explicit regression proof that failed device CHECK responses do not proceed to SIGN. This closes the host-side "ask anyway" gap for current negative policy cases.

## C3.0 firmware-enforced CHECK-before-SIGN - PASS

Milestone:

HardwarePrototype_C3_0_FIRMWARE_ENFORCED_CHECK_BEFORE_SIGN_ALL_PASS

Firmware changes:

- Added policy errors:
  ERR_SIGN_WITHOUT_APPROVED_CHECK=-43
  ERR_SIGN_MISMATCHES_APPROVED_CHECK=-44
- Added firmware-side pending approved CHECK state in Core\Src\wallet_command.c.
- CHECK approved now records the exact approved candidate summary.
- CHECK rejected now clears any pending approval.
- SIGN now calls wallet_command_sign_matches_approved_check_text before unlock, key provider, TROPIC auth, or signing.
- Successful SIGN clears the pending approved CHECK.
- Mismatched SIGN clears the pending approved CHECK and rejects with ERR POLICY -44.
- POLICYINFO now reports the C3.0 error labels.

Candidate fields bound by firmware:

- NETWORK
- TXID_LE
- VOUT
- INPUT_SATS
- PREV_SCRIPT
- PAY_SCRIPT
- PAY_SATS
- CHANGE_SCRIPT
- CHANGE_SATS
- FEE_SATS

New regression:

- tools\wallet_c3_0_firmware_check_before_sign_regression.ps1
- Master regression step C3_0_FIRMWARE_CHECK_BEFORE_SIGN

Confirmed C3.0 cases:

- SIGN without a prior approved CHECK rejects with ERR POLICY -43 and no RAW_TX.
- CHECK approved then matching SIGN produces RAW_TX.
- Immediate second SIGN without another CHECK rejects with ERR POLICY -43 and no RAW_TX.
- CHECK approved then mismatched SIGN rejects with ERR POLICY -44 and no RAW_TX.
- CHECK rejected by policy stores no approval; later SIGN rejects with ERR POLICY -43.
- CHECK itself still does not require unlock, does not sign, and does not change TROPIC AUTH_COUNT.
- SIGN still requires unlock and TROPIC auth gate after firmware CHECK binding passes.

Validation run:

- STM32CubeIDE headless clean/build passed: 0 errors, 1 warning.
- STM32_Programmer_CLI flash and verify succeeded.
- .\tools\wallet_c3_0_firmware_check_before_sign_regression.ps1 passed.
- .\tools\wallet_device_check_summary_regression.ps1 passed.
- .\tools\wallet_regtest_full_loop.ps1 passed.
- .\tools\wallet_run_all_regressions.ps1 passed with ALL_REGRESSIONS_PASS.

MVP significance:

The STM32 now enforces CHECK-before-SIGN in firmware. The host can no longer directly request SIGN unless the device itself has already approved the exact same transaction candidate through CHECK.

## C3.1 CHECK_ID candidate commitment - PASS

Date: 2026-06-20

Milestone:

C3.1_CHECK_ID_CANDIDATE_COMMITMENT_ALL_PASS

What changed:

- Firmware now computes deterministic CHECK_ID using SHA-256 over the CHECK/SIGN candidate fields:
  NETWORK, TXID_LE, VOUT, INPUT_SATS, PREV_SCRIPT, PAY_SCRIPT, PAY_SATS, CHANGE_SCRIPT, CHANGE_SATS, FEE_SATS.
- CHECK summaries now report SUMMARY_VERSION=C3.1_DEVICE_POLICY_SUMMARY_CHECK_ID and CHECK_ID=<64 lowercase hex chars>.
- Approved CHECK state stores the computed CHECK_ID.
- SIGN recomputes CHECK_ID from its command candidate and rejects mismatches with ERR POLICY -44 before unlock/key/TROPIC signing.
- Matching CHECK_ID still signs once and then clears the pending approval through the C3.0 one-shot path.
- Host CHECK path now rejects missing or malformed CHECK_ID.
- Added tools/wallet_c3_1_check_id_commitment_regression.ps1 and wired it into tools/wallet_run_all_regressions.ps1.

Passing proof:

- C3_1_CHECK_ID_COMMITMENT_REGRESSION_PASS
- DEVICE_CHECK_SUMMARY_REGRESSION_PASS
- STM32_REGTEST_FULL_LOOP_PASS
- ALL_REGRESSIONS_PASS

Backup:

C:\stm32_backups\HardwarePrototype_C3_1_CHECK_ID_CANDIDATE_COMMITMENT_ALL_PASS

## C3.2 UART CONFIRM approval gate - PASS

Date: 2026-06-20

Milestone:

C3.2_UART_CONFIRM_APPROVAL_GATE_ALL_PASS

What changed:

- Firmware now requires explicit CONFIRM after an approved CHECK before SIGN is allowed.
- CHECK approved stores a pending candidate but marks it unconfirmed.
- CONFIRM without pending approved CHECK rejects with ERR POLICY -47.
- SIGN after CHECK but before CONFIRM rejects with ERR POLICY -46 and produces no RAW_TX.
- CHECK + CONFIRM + matching SIGN signs once, then clears approval through the one-shot path.
- Failed CHECK clears pending approval and leaves no confirmable candidate.
- Host generator now performs CHECK, verifies the summary and CHECK_ID, sends CONFIRM, verifies OK CONFIRM, then sends SIGN.
- POLICYINFO reports ERR_SIGN_WITHOUT_CONFIRMED_CHECK=-46 and ERR_CONFIRM_WITHOUT_APPROVED_CHECK=-47.
- Added tools/wallet_c3_2_uart_confirm_gate_regression.ps1 and wired it into tools/wallet_run_all_regressions.ps1.

Passing proof:

- C3_0_FIRMWARE_CHECK_BEFORE_SIGN_REGRESSION_PASS
- C3_1_CHECK_ID_COMMITMENT_REGRESSION_PASS
- C3_2_UART_CONFIRM_GATE_REGRESSION_PASS
- DEVICE_CHECK_SUMMARY_REGRESSION_PASS
- STM32_REGTEST_FULL_LOOP_PASS
- ALL_REGRESSIONS_PASS

Backup:

C:\stm32_backups\HardwarePrototype_C3_2_UART_CONFIRM_APPROVAL_GATE_ALL_PASS

## C3.3 physical USER button confirmation - PASS

Date: 2026-06-20

Milestone:

C3.3_PHYSICAL_BUTTON_CONFIRMATION_ALL_PASS

What changed:

- Firmware initializes the NUCLEO USER button before entering the wallet UART loop.
- Firmware polls USER button while UART is idle, without slowing active byte-by-byte UART command receipt.
- If a CHECK-approved candidate is pending, a USER button press calls the same approval path as UART CONFIRM.
- USER button confirmation is one-shot per pending CHECK; repeated button presses after confirmation do not spam additional OK BUTTON_CONFIRM responses.
- Successful button approval emits:
  OK BUTTON_CONFIRM
  USER_APPROVED=1
  CONFIRM_SOURCE=BUTTON_USER
- UART CONFIRM remains available as the software/dev-mode approval path for automation.
- Added BUTTONINFO diagnostic command reporting raw USER button GPIO state and approval pending/confirmed state.
- Added tools/wallet_c3_3_physical_button_confirm_regression.ps1 as a manual physical regression. It is intentionally not wired into tools/wallet_run_all_regressions.ps1 because it requires a human button press.

Passing proof:

- BUTTONINFO physical diagnostic showed BUTTON_USER_RAW toggling 0/1 during real USER button presses.
- C3_3_FOCUSED_BUTTON_POSITIVE_PASS proved CHECK approved -> USER button confirmed -> SIGN produced RAW_TX -> second SIGN rejected.
- C3_3_PHYSICAL_BUTTON_CONFIRM_REGRESSION_PASS proved no-button SIGN rejects with ERR POLICY -46, button-confirmed SIGN succeeds, and sign-twice rejects with ERR POLICY -43.
- STM32CubeIDE headless clean/build passed: 0 errors, 1 warning.
- STM32_Programmer_CLI flash and verify succeeded.
- Full automated master regression passed after reset with ALL_REGRESSIONS_PASS.

Backup:

C:\stm32_backups\HardwarePrototype_C3_3_PHYSICAL_BUTTON_CONFIRMATION_ALL_PASS

## C3.4 approval timeout and one-shot hardening - PASS

Date: 2026-06-20

Milestone:

C3.4_APPROVAL_TIMEOUT_ONE_SHOT_ALL_PASS

What changed:

- Firmware now expires pending and confirmed approvals after 10 seconds.
- Pending CHECK approvals expire before CONFIRM and reject with ERR POLICY -48.
- Confirmed approvals expire before SIGN and reject with ERR POLICY -48.
- Expired approvals clear pending state, so stale CHECK approvals cannot be reused.
- Expired SIGN attempts produce no RAW_TX and do not trigger the TROPIC auth gate.
- Fresh CHECK + CONFIRM + matching SIGN still signs once and clears approval.
- Immediate second SIGN without a new CHECK still rejects with ERR POLICY -43.
- POLICYINFO and BUTTONINFO report APPROVAL_TIMEOUT_MS=10000.
- Added tools/wallet_c3_4_approval_timeout_regression.ps1 and wired it into tools/wallet_run_all_regressions.ps1.

Passing proof:

- C3_4_POLICYINFO_TIMEOUT_PASS
- C3_4_PENDING_CHECK_TIMEOUT_PASS
- C3_4_CONFIRMED_SIGN_TIMEOUT_PASS
- C3_4_FRESH_SIGN_ONE_SHOT_PASS
- C3_4_APPROVAL_TIMEOUT_REGRESSION_PASS
- STM32CubeIDE headless clean/build passed: 0 errors, 1 warning.
- STM32_Programmer_CLI flash and verify succeeded.
- Full automated master regression passed with ALL_REGRESSIONS_PASS.

Backup:

C:\stm32_backups\HardwarePrototype_C3_4_APPROVAL_TIMEOUT_ONE_SHOT_ALL_PASS

## C3.5 device-side confirmation code - PASS

Date: 2026-06-20

Milestone:

C3.5_DEVICE_CONFIRM_CODE_ALL_PASS

What changed:

- Approved CHECK summaries now emit a six-digit CONFIRM_CODE derived from the pending CHECK_ID.
- UART/dev approval now requires CONFIRM_CODE=<code>; bare CONFIRM rejects with ERR POLICY -49 when a pending CHECK exists.
- Wrong CONFIRM_CODE rejects with ERR POLICY -50, produces no RAW_TX, and clears the pending approval.
- Correct CONFIRM_CODE marks the pending CHECK as user-approved and reports CONFIRM_SOURCE=UART_CONFIRM_CODE.
- Physical USER button confirmation remains available as the hardware approval path.
- POLICYINFO reports ERR_CONFIRM_CODE_REQUIRED=-49 and ERR_CONFIRM_CODE_MISMATCH=-50.
- BUTTONINFO can report the pending CONFIRM_CODE for diagnostics.
- Host generator now parses CONFIRM_CODE only after an approved CHECK and sends CONFIRM_CODE=<code> before SIGN.
- Host generator CHECK-line pacing was hardened to 80 ms per line to keep long serial regression runs stable.
- Added tools/wallet_c3_5_confirm_code_regression.ps1 and wired it into tools/wallet_run_all_regressions.ps1.

Passing proof:

- C3_5_POLICYINFO_CONFIRM_CODE_PASS
- C3_5_CONFIRM_CODE_PRESENT_PASS
- C3_5_BARE_CONFIRM_REJECT_PASS
- C3_5_WRONG_CONFIRM_CODE_REJECT_PASS
- C3_5_RIGHT_CONFIRM_CODE_SIGN_PASS
- C3_5_CONFIRM_CODE_REGRESSION_PASS
- LIVE_NEGATIVE_POLICY_REGRESSION_PASS after host rejected-CHECK CONFIRM_CODE handling fix.
- STM32CubeIDE headless clean/build passed: 0 errors, 1 warning.
- STM32_Programmer_CLI flash and verify succeeded.
- Full automated master regression passed with ALL_REGRESSIONS_PASS.

Backup:

C:\stm32_backups\HardwarePrototype_C3_5_DEVICE_CONFIRM_CODE_ALL_PASS

## C4.0 legacy/debug signing disabled - PASS

Date: 2026-06-20

Milestone:

C4.0_LEGACY_DEBUG_SIGNING_DISABLED_ALL_PASS

What changed:

- The legacy wallet_command_sign_text API no longer parses host-supplied PRIVKEY and now returns WALLET_POLICY_ERR_LEGACY_SIGN_DISABLED (-60).
- The command debug regression hook now expects the legacy API to be disabled instead of signing.
- UART still rejects any command containing PRIVKEY= with ERR KEYPOLICY -21 before CHECK/SIGN authorization or TROPIC auth.
- POLICYINFO now reports ERR_LEGACY_SIGN_DISABLED=-60.
- Source audit now proves:
  - active wallet_command.c does not parse host PRIVKEY
  - legacy wallet_command_sign_text returns WALLET_POLICY_ERR_LEGACY_SIGN_DISABLED
  - UART does not call legacy wallet_command_sign_text
  - UART uses wallet_command_sign_text_with_private_key through the key-provider path
- Added tools/wallet_c4_0_legacy_sign_disabled_regression.ps1 and wired it into tools/wallet_run_all_regressions.ps1.

Passing proof:

- C4_0_POLICYINFO_LEGACY_DISABLED_PASS
- C4_0_UART_PRIVKEY_REJECT_NO_AUTH_PASS
- C4_0_LEGACY_SIGN_DISABLED_REGRESSION_PASS
- C4_0_LEGACY_SIGN_DISABLED_SOURCE_AUDIT_PASS
- STM32CubeIDE headless clean/build passed: 0 errors, 1 warning.
- STM32_Programmer_CLI flash and verify succeeded.
- Full automated master regression passed with ALL_REGRESSIONS_PASS.

Backup:

C:\stm32_backups\HardwarePrototype_C4_0_LEGACY_DEBUG_SIGNING_DISABLED_ALL_PASS

## C4.1 secret and buffer zeroization cleanup - PASS

Date: 2026-06-20

Milestone:

C4.1_SECRET_BUFFER_ZEROIZATION_ALL_PASS

What changed:

- Added volatile secure-zero helpers for wallet command state, UART buffers, key-provider outputs, and signing-core temporary buffers.
- Key-provider private-key output buffers now use secure zeroing on initialization and all error paths.
- UART private-key, raw transaction, raw-hex, chunk, and SIGN command buffers are wiped after SIGN success/failure paths.
- Signing-core temporary buffers for pubkey, sighash preimage, hashes, digest, raw signature, DER signature, and sighash signature are wiped through a common cleanup exit.
- Approved CHECK state and CHECK_ID/confirmation comparison temporaries are securely cleared after use.
- CHECK/CONFIRM timing remains protocol-safe; the UART command buffer is not cleared in the fast CHECK-to-CHECK handoff path after the C3.1 regression caught that race.
- Added tools/wallet_c4_1_secret_zeroization_audit.ps1 and wired it into tools/wallet_run_all_regressions.ps1.
- Source audit now asserts the C4.1 secure-zero paths and still verifies the C4.0 legacy signing lockout.

Passing proof:

- C4_1_SECRET_ZEROIZATION_SOURCE_AUDIT_PASS
- C4_1_PRIVATE_KEY_SECURE_ZERO_ASSERTION_PASS
- C4_1_UNLOCK_COMMAND_BUFFER_CLEAR_ASSERTION_PASS
- C4_1_PENDING_APPROVAL_CLEAR_ASSERTION_PASS
- C4_1_SIGNING_TEMP_BUFFER_CLEAR_ASSERTION_PASS
- C4_1_SECRET_ZEROIZATION_AUDIT_PASS
- C3_1_CHECK_ID_COMMITMENT_REGRESSION_PASS after fixing the CHECK buffer-clear timing race.
- STM32CubeIDE headless clean/build passed: 0 errors, 1 warning.
- STM32_Programmer_CLI flash and verify succeeded.
- Full automated master regression passed with ALL_REGRESSIONS_PASS.

Backup:

C:\stm32_backups\HardwarePrototype_C4_1_SECRET_BUFFER_ZEROIZATION_ALL_PASS

## C4.2 PIN/session unlock model - PASS

Date: 2026-06-20

Milestone:

C4.2_PIN_SESSION_ALL_PASS

What changed:

- Replaced host-provided static UNLOCK_SECRET signing with a device PIN/session model.
- Added UNLOCK_PIN=<pin>, LOCK, and UNLOCKINFO UART commands.
- The encrypted secp256k1 key blob is unwrapped only through the supplied PIN credential; the plaintext signing key is held only in a RAM session buffer.
- SIGN requires an active PIN session, still requires the TROPIC01 auth gate, and clears the session after successful key use.
- Missing PIN/session returns ERR KEYPROVIDER -22.
- Wrong PIN returns ERR KEYPROVIDER -23 and does not trigger TROPIC auth.
- Expired PIN session returns ERR KEYPROVIDER -62.
- Legacy UNLOCK_SECRET= is rejected at UART key policy with ERR KEYPOLICY -24.
- POLICYINFO reports UNLOCK_MODEL=PIN_SESSION_C4.2, PIN_SESSION_TIMEOUT_MS=30000, PIN_RETRY_DELAY_MS=1000, PIN_MAX_ATTEMPTS=3, ERR_PIN_LOCKED=-61, ERR_PIN_SESSION_EXPIRED=-62, and ERR_HOST_UNLOCK_SECRET_DISABLED=-24.
- Host transaction generation now unlocks with UNLOCK_PIN before CHECK, then proceeds through CHECK, CONFIRM_CODE, and SIGN.
- CHECK and early SIGN policy failures clear any active PIN session to prevent stale authorizations.
- C3.1 serial regression harness now waits for the final UART prompt marker before sending the next command, preventing first-line truncation during repeated CHECK tests.
- Added tools/wallet_c4_2_pin_session_regression.ps1 and wired it into tools/wallet_run_all_regressions.ps1.

Passing proof:

- C4_2_POLICYINFO_PIN_SESSION_PASS
- C4_2_UNLOCKINFO_LOCKED_PASS
- C4_2_WRONG_PIN_NO_AUTH_PASS
- C4_2_LEGACY_UNLOCK_SECRET_DISABLED_PASS
- C4_2_PIN_SESSION_SIGN_PASS
- C4_2_PIN_SESSION_REGRESSION_PASS
- C4_2_PIN_SESSION_SOURCE_AUDIT_PASS
- C3_1_CHECK_ID_COMMITMENT_REGRESSION_PASS after prompt-wait hardening.
- STM32CubeIDE headless clean/build passed: 0 errors, 1 warning.
- STM32_Programmer_CLI flash and verify succeeded.
- Full automated master regression passed with ALL_REGRESSIONS_PASS.

Backup:

C:\stm32_backups\HardwarePrototype_C4_2_PIN_SESSION_ALL_PASS

## C5.0 PSBT-like text command format - PASS

Date: 2026-06-20

Milestone:

C5.0_PSBT_LIKE_FORMAT_ALL_PASS

What changed:

- Added a backwards-compatible PSBT-like text command format for the current one-input/two-output regtest transaction model.
- Legacy command fields remain supported unchanged.
- New host command format:
  - WALLET_CMD_FORMAT=C5.0_PSBT_LIKE_TEXT_V1
  - PSBT_GLOBAL_NETWORK
  - PSBT_INPUT_COUNT=1
  - PSBT_INPUT0_TXID_LE
  - PSBT_INPUT0_VOUT
  - PSBT_INPUT0_SATS
  - PSBT_INPUT0_PREV_SCRIPT
  - PSBT_OUTPUT_COUNT=2
  - PSBT_OUTPUT0_ROLE=PAYMENT
  - PSBT_OUTPUT0_SCRIPT
  - PSBT_OUTPUT0_SATS
  - PSBT_OUTPUT1_ROLE=CHANGE
  - PSBT_OUTPUT1_SCRIPT
  - PSBT_OUTPUT1_SATS
- Firmware maps the C5.0 PSBT-like fields onto the same canonical candidate fields used by legacy CHECK/SIGN.
- CHECK_ID, host/device transcript binding, CONFIRM_CODE, PIN session, one-shot approval, policy checks, and TROPIC auth gate all remain on the existing enforced path.
- POLICYINFO now reports COMMAND_FORMAT_LEGACY=LEGACY_TEXT_V1 and COMMAND_FORMAT_PSBT_LIKE=C5.0_PSBT_LIKE_TEXT_V1.
- Host generator now supports -CommandFormat PsbtLike while keeping Legacy as the default.
- Host transcript now records COMMAND_FORMAT.
- Added tools/wallet_c5_0_psbt_like_format_regression.ps1 and wired it into tools/wallet_run_all_regressions.ps1.
- Source audit now asserts the C5.0 firmware aliases and POLICYINFO advertisement.

Passing proof:

- C5_0_POLICYINFO_FORMAT_PASS
- C5_0_PSBT_LIKE_SIGN_PASS
- C5_0_PSBT_LIKE_FORMAT_REGRESSION_PASS
- C5_0_PSBT_LIKE_FORMAT_SOURCE_AUDIT_PASS
- STM32CubeIDE headless clean/build passed: 0 errors, 1 warning.
- STM32_Programmer_CLI flash and verify succeeded.
- Full automated master regression passed with ALL_REGRESSIONS_PASS.

Backup:

C:\stm32_backups\HardwarePrototype_C5_0_PSBT_LIKE_FORMAT_ALL_PASS

## C5.0.1 strict PSBT-like validation + C5.2 output policy hardening - PASS

Date: 2026-06-20

Milestone:

C5_0_1_STRICT_PSBT_LIKE_AND_C5_2_OUTPUT_POLICY_ALL_PASS

What changed:

- Added strict firmware validation for the C5.0 PSBT-like text format.
- New format policy error: ERR_FORMAT_INVALID=-51.
- PSBT-like commands now require WALLET_CMD_FORMAT=C5.0_PSBT_LIKE_TEXT_V1, PSBT_INPUT_COUNT=1, PSBT_OUTPUT_COUNT=2, PSBT_OUTPUT0_ROLE=PAYMENT, and PSBT_OUTPUT1_ROLE=CHANGE.
- Firmware rejects malformed PSBT-like commands, wrong input count, wrong output roles, and mixed legacy/PSBT-like field sets before signing.
- Added output dust checks with DUST_LIMIT_SATS=546 and ERR_DUST_OUTPUT=-52.
- Added fee-rate sanity for the current 1-input/2-output estimate: MAX_FEE_RATE_SATS_PER_KVB=100000 and FEE_RATE_ESTIMATE_VBYTES=192. Excessive fee rate is rejected with ERR POLICY -35.
- POLICYINFO now reports the new C5.0.1/C5.2 constants and errors.
- Extended tools/wallet_c5_0_psbt_like_format_regression.ps1 with strict format negatives and C5.2 output-policy negatives.
- C5.1 multi-input and C5.3 derivation/change-path support were assessed but not implemented in this pass. True support requires multi-input sighash/serialization, larger UART/raw-tx buffers, multi-input CHECK_ID binding, and a real derivation model instead of the current fixed device script.

Passing proof:

- C5_0_POLICYINFO_FORMAT_PASS
- C5_0_1_MISSING_FORMAT_REJECT_PASS
- C5_0_1_WRONG_INPUT_COUNT_REJECT_PASS
- C5_0_1_WRONG_OUTPUT_ROLE_REJECT_PASS
- C5_0_1_MIXED_LEGACY_FIELDS_REJECT_PASS
- C5_0_1_STRICT_FORMAT_VALIDATION_PASS
- C5_2_PAYMENT_DUST_REJECT_PASS
- C5_2_CHANGE_DUST_REJECT_PASS
- C5_2_FEE_RATE_REJECT_PASS
- C5_2_OUTPUT_POLICY_EXPANSION_PASS
- C5_0_PSBT_LIKE_SIGN_PASS
- C5_0_PSBT_LIKE_FORMAT_REGRESSION_PASS
- C5_0_PSBT_LIKE_FORMAT_SOURCE_AUDIT_PASS
- STM32CubeIDE headless clean/build passed: 0 errors, 1 warning.
- STM32_Programmer_CLI flash and verify succeeded.
- Full automated master regression passed with ALL_REGRESSIONS_PASS.

Backup:

C:\stm32_backups\HardwarePrototype_C5_0_1_STRICT_PSBT_C5_2_POLICY_ALL_PASS

## C5.1 two-input PSBT-like signing + C5.3A change derivation metadata - PASS

Date: 2026-06-20

Milestone:

C5_1_TWO_INPUT_C5_3_CHANGE_METADATA_ALL_PASS

What changed:

- Added firmware support for PSBT-like two-input legacy P2PKH candidates with PSBT_INPUT_COUNT=2.
- CHECK summaries now include INPUT_COUNT, INPUT1_TXID_LE, INPUT1_VOUT, INPUT1_SATS, INPUT1_PREV_SCRIPT, and TOTAL_INPUT_SATS when applicable.
- CHECK_ID binding now commits to INPUT_COUNT, all input outpoints/scripts/amounts, TOTAL_INPUT_SATS, outputs, and fee using C5.1_CHECK_ID_MULTI_INPUT_V1.
- SIGN can now produce a signed legacy P2PKH 2-input/2-output raw transaction; focused regression proved RAW_TX starts with 0100000002.
- Fee-rate policy now uses 192 vbytes for 1-input/2-output and 340 vbytes for 2-input/2-output.
- UART/raw buffers were increased for larger two-input transactions and the old internal 500-hex post-check ceiling was removed.
- Host generator now supports -InputCount 2, second-input fields, total-input binding, and optional -ChangeDerivation.
- Added C5.3A change derivation metadata gate for the current fixed MVP change script: PSBT_OUTPUT1_DERIVATION=mvp-static-change/0 is accepted; wrong metadata rejects with ERR POLICY -54.
- This is not full HD/address derivation yet. It is a truthful metadata gate around the current fixed-script key model; real derivation remains a later key-model milestone.
- TROPIC01 connectivity was rechecked after wiring correction: SEINFO reported INIT_RET=0, INITIALIZED=1, LT_CHIP_ID_RET=0.

Passing proof:

- C5_0_POLICYINFO_FORMAT_PASS
- C5_0_1_STRICT_FORMAT_VALIDATION_PASS
- C5_2_OUTPUT_POLICY_EXPANSION_PASS
- C5_3_CHANGE_DERIVATION_INVALID_REJECT_PASS
- C5_0_PSBT_LIKE_SIGN_PASS
- C5_1_TWO_INPUT_PSBT_LIKE_SIGN_PASS
- C5_3_CHANGE_DERIVATION_METADATA_PASS
- C5_0_PSBT_LIKE_FORMAT_REGRESSION_PASS
- C5_1_TWO_INPUT_SOURCE_AUDIT_PASS
- C5_3_CHANGE_DERIVATION_METADATA_SOURCE_AUDIT_PASS
- STM32CubeIDE headless clean/build passed: 0 errors, 1 warning.
- STM32_Programmer_CLI flash and verify succeeded.
- Full automated master regression passed with ALL_REGRESSIONS_PASS.

Backup:

C:\stm32_backups\HardwarePrototype_C5_1_TWO_INPUT_C5_3_CHANGE_METADATA_ALL_PASS

## C6.0 versioned protocol + C6.1 framed text protocol - PASS

Date: 2026-06-21

Milestone:

C6_0_VERSIONED_PROTOCOL_C6_1_FRAMED_TEXT_ALL_PASS

What changed:

- Added C6.0 versioned protocol labels to UART discovery and policy responses: PROTOCOL_VERSION, COMMAND_VERSION, RESPONSE_VERSION, ERROR_VERSION, and POLICY_VERSION.
- Added FRAMEINFO discovery for C6.1 framed text command support.
- Added compatible C6.1 text frames around the existing UART line protocol using FRAME_BEGIN, FRAME_VERSION, FRAME_LEN, FRAME_CRC32, FRAME_PAYLOAD_BEGIN, FRAME_PAYLOAD_END, and FRAME_END.
- Added CRC32_IEEE validation and payload byte-length validation before unwrapping framed commands.
- Framed commands reuse the existing command parser after validation, so legacy plain-text commands remain supported.
- Added frame error reporting: ERR_FRAME_INVALID=-70, ERR_FRAME_LEN=-71, ERR_FRAME_CRC=-72, and ERR_FRAME_UNSUPPORTED=-73.
- Added frame-drain behavior so malformed/unsupported frames are consumed through FRAME_END before the device returns an error.
- Added focused regression tools/wallet_c6_0_c6_1_protocol_regression.ps1.
- Added the C6.0/C6.1 regression to the master regression suite.
- Extended source audit coverage for C6.0 version labels, C6.1 framed text hooks, CRC32 handling, and master-suite inclusion.

Passing proof:

- C6_0_VERSIONED_PROTOCOL_FIELDS_PASS
- C6_1_FRAMEINFO_PASS
- C6_1_FRAMED_POLICYINFO_PASS
- C6_1_FRAME_LEN_REJECT_PASS
- C6_1_FRAME_CRC_REJECT_PASS
- C6_1_FRAME_UNSUPPORTED_REJECT_PASS
- C6_1_FRAMED_CHECK_PASS
- C6_1_FRAMED_FAILED_CHECK_CLEARS_PENDING_PASS
- C6_0_C6_1_PROTOCOL_REGRESSION_PASS
- C6_0_VERSIONED_PROTOCOL_SOURCE_AUDIT_PASS
- C6_1_FRAMED_TEXT_SOURCE_AUDIT_PASS
- STM32CubeIDE clean/build and flash were completed manually after the final frame-drain source fix.
- Full automated master regression passed with ALL_REGRESSIONS_PASS.

Backup:

C:\stm32_backups\HardwarePrototype_C6_0_VERSIONED_PROTOCOL_C6_1_FRAMED_TEXT_ALL_PASS

## C6.2 one-command hardware CI harness - PASS

Date: 2026-06-20

Milestone:

C6_2_HARDWARE_CI_ALL_PASS

What changed:

- Added tools/wallet_hardware_ci.ps1 as the one-command hardware loop.
- The harness can clean/build firmware with STM32CubeIDE headless, flash with STM32_Programmer_CLI, probe UART, run focused C6.0/C6.1 protocol checks, run the full master regression suite, save a timestamped log, and create a milestone backup.
- The harness supports SkipBuild, SkipFlash, SkipBackup, and AppendStatus options for repeated hardware runs.

Passing proof:

- WALLET_HARDWARE_CI_PASS
- Full automated master regression passed with ALL_REGRESSIONS_PASS.

Log:

C:\Users\mando\OneDrive\Desktop\newstm32\HardwarePrototype\logs\wallet_hardware_ci_20260620_231609.log

Backup:

C:\stm32_backups\HardwarePrototype_C6_2_HARDWARE_CI_ALL_PASS

## C4.3 TROPIC auth policy strengthening - PASS

Date: 2026-06-21

Milestone:

C4_3_TROPIC_AUTH_POLICY_ALL_PASS

What changed:

- Added tools/wallet_c4_3_tropic_auth_policy_regression.ps1.
- The regression uses SEINFO AUTH_COUNT as the hardware oracle for the TROPIC auth gate.
- Proved CHECK does not trigger TROPIC auth.
- Proved failed policy CHECK does not trigger TROPIC auth.
- Proved wrong PIN unlock does not trigger TROPIC auth.
- Proved SIGN mismatch after approved CHECK/CONFIRM does not trigger TROPIC auth.
- Proved one successful approved SIGN increments AUTH_COUNT by exactly one.
- Added the C4.3 regression to the master regression suite.
- Extended source audit coverage for AUTH_COUNT exposure, key-provider TROPIC auth routing, C4.3 regression assertions, and master-suite inclusion.

Passing proof:

- C4_3_CHECK_NO_AUTH_PASS
- C4_3_FAILED_POLICY_NO_AUTH_PASS
- C4_3_WRONG_PIN_NO_AUTH_PASS
- C4_3_SIGN_MISMATCH_NO_AUTH_PASS
- C4_3_SUCCESSFUL_SIGN_AUTH_ONCE_PASS
- C4_3_TROPIC_AUTH_POLICY_REGRESSION_PASS
- C4_3_TROPIC_AUTH_POLICY_SOURCE_AUDIT_PASS
- Full automated master regression passed with ALL_REGRESSIONS_PASS.

Backup:

C:\stm32_backups\HardwarePrototype_C4_3_TROPIC_AUTH_POLICY_ALL_PASS

## C3.3 physical button confirmation hardening - PASS

Date: 2026-06-21

Milestone:

C3_3_PHYSICAL_BUTTON_CONFIRM_ALL_PASS

What changed:

- Verified the physical USER button confirmation path on the STM32 board.
- Confirmed CHECK approved creates a pending candidate, the USER button marks it approved on-device, and SIGN succeeds only after the physical confirmation.
- Confirmed CHECK without UART CONFIRM or button approval rejects SIGN.
- Confirmed immediate second SIGN after a successful button-approved SIGN rejects with ERR POLICY -43.
- Added ready-flag support to tools/wallet_c3_3_physical_button_confirm_regression.ps1 so the manual button window can be synchronized reliably.
- Extended source audit coverage for the physical button confirmation path and regression assertions.

Passing proof:

- C3_3_SIGN_WITHOUT_BUTTON_OR_CONFIRM_REJECT_PASS
- OK BUTTON_CONFIRM
- USER_APPROVED=1
- CONFIRM_SOURCE=BUTTON_USER
- C3_3_CHECK_BUTTON_SIGN_PASS
- C3_3_SIGN_TWICE_AFTER_BUTTON_REJECT_PASS
- C3_3_PHYSICAL_BUTTON_CONFIRM_REGRESSION_PASS
- C3_3_PHYSICAL_BUTTON_CONFIRM_SOURCE_AUDIT_PASS

Backup:

C:\stm32_backups\HardwarePrototype_C3_3_PHYSICAL_BUTTON_CONFIRM_ALL_PASS

## C3.6 physical button fresh-press hardening - IN PROGRESS

Date: 2026-06-21

Milestone:

C3_6_PHYSICAL_BUTTON_FRESH_PRESS_BUILD_FLASHED

What changed:

- Hardened the USER button approval path so a stale button hold cannot automatically approve a newly created CHECK candidate.
- Added BUTTON_CONFIRM_ARMED to BUTTONINFO so the host can inspect whether the device has seen a released button state before accepting a fresh physical press.
- Added tools/wallet_c3_6_physical_button_fresh_press_regression.ps1 for the manual stale-held-button proof.
- Extended source audit coverage for the fresh physical press arming path and C3.6 regression assertions.

Current validation:

- Firmware clean build passed with 0 errors.
- Firmware flash and verify passed.
- Source audit passed with C3_6_PHYSICAL_BUTTON_FRESH_PRESS_SOURCE_AUDIT_PASS.

Still pending:

- Manual physical C3.6 regression: hold USER before CHECK, prove stale hold is ignored, release/press again, then SIGN succeeds.

## C7.0 real-network safety gate - PASS

Date: 2026-06-21

Milestone:

C7_0_REAL_NETWORK_SAFETY_ALL_PASS

What changed:

- Firmware reports the current real-Bitcoin stage as C7.0_REAL_NETWORK_SAFETY_GATE.
- VERSION and POLICYINFO explicitly report NETWORK_ALLOWED=REGTEST.
- VERSION and POLICYINFO explicitly report REAL_BITCOIN_SIGNING_ENABLED=0, TESTNET_SIGNING_ENABLED=0, and MAINNET_SIGNING_ENABLED=0.
- Added a focused C7.0 regression proving TESTNET and MAINNET CHECK requests are rejected with ERR POLICY -42.
- Added host-level C7.0 checks proving rejected real-network candidates do not send SIGN and do not produce RAW_TX.
- Added source-audit coverage proving the C7.0 labels, C7.0 regression script, and master-suite inclusion are present.

Harness hardening during validation:

- Hardened tools/wallet_c3_1_check_id_commitment_regression.ps1 to force a fresh VERSION/READY prompt before its first CHECK.
- Hardened tools/wallet_generate_tx_command.ps1 so fresh UART sync waits for the full prompt and PSBT-like command blocks use a slightly longer inter-line delay.
- This documents the transient integration issue seen during master runs: some long serial command sequences could be parsed incomplete at regression boundaries, causing missing or malformed CHECK_ID failures even though focused firmware behavior was correct.

Passing proof:

- C7_0_REAL_NETWORK_SAFETY_REGRESSION_PASS
- C7_0_REAL_NETWORK_SAFETY_SOURCE_AUDIT_PASS
- C5_0_PSBT_LIKE_FORMAT_REGRESSION_PASS
- C6_0_C6_1_PROTOCOL_REGRESSION_PASS
- C4_3_TROPIC_AUTH_POLICY_REGRESSION_PASS
- SOURCE_AUDIT_PASS
- Full automated master regression passed with ALL_REGRESSIONS_PASS.

Master log:

logs\master_c7_0_after_generator_hardening_20260621_031443.out.log

Backup:

C:\stm32_backups\HardwarePrototype_C7_0_REAL_NETWORK_SAFETY_ALL_PASS

## C8.0 real-Bitcoin readiness manifest - PASS

Date: 2026-06-21

Milestone:

C8_0_REAL_BITCOIN_READINESS_ALL_PASS

What changed:

- Firmware now reports REAL_BITCOIN_STAGE=C8.0_REAL_BITCOIN_READINESS_MANIFEST.
- Added REALINFO as an explicit device readiness manifest for the future real-Bitcoin path.
- REALINFO reports REAL_BITCOIN_READINESS=NOT_READY and keeps NETWORK_ALLOWED=REGTEST.
- REALINFO explicitly reports REAL_BITCOIN_SIGNING_ENABLED=0, TESTNET_SIGNING_ENABLED=0, and MAINNET_SIGNING_ENABLED=0.
- REALINFO documents the current blockers before real Bitcoin signing can be safely enabled:
  secure display, TROPIC secp256k1 support, real-network policy, address derivation, change derivation, real fee policy, and testnet regression coverage.
- C7.0 real-network safety regression was forward-hardened so it still proves real-network signing is disabled even as the stage label advances.
- Added a focused C8.0 regression proving VERSION, POLICYINFO, and REALINFO agree on the readiness stage and that TESTNET/MAINNET CHECK requests still reject with ERR POLICY -42.
- Added source-audit coverage for the C8.0 firmware manifest, C8.0 regression assertions, and master-suite inclusion.

Passing proof:

- C8_0_VERSION_STAGE_PASS
- C8_0_POLICYINFO_STAGE_PASS
- C8_0_REALINFO_MANIFEST_PASS
- C8_0_REAL_SIGNING_DISABLED_PASS
- C8_0_READINESS_BLOCKERS_PASS
- C8_0_REAL_NETWORK_STILL_REJECTS_PASS
- C8_0_READINESS_AUTH_UNCHANGED
- C8_0_REAL_BITCOIN_READINESS_REGRESSION_PASS
- C8_0_REAL_BITCOIN_READINESS_SOURCE_AUDIT_PASS
- Full automated master regression passed with ALL_REGRESSIONS_PASS.

Master log:

logs\master_c8_0_realinfo_20260621_034729.out.log

Backup:

C:\stm32_backups\HardwarePrototype_C8_0_REAL_BITCOIN_READINESS_ALL_PASS

## C8.1 testnet watch-only dry-run - PASS

Date: 2026-06-21

Milestone:

C8_1_TESTNET_WATCH_ONLY_DRY_RUN_ALL_PASS

What changed:

- Firmware now reports REAL_BITCOIN_STAGE=C8.1_TESTNET_WATCH_ONLY_DRY_RUN.
- VERSION, POLICYINFO, and REALINFO advertise TESTNET_WATCH_ONLY_DRY_RUN_SUPPORTED=1.
- VERSION, POLICYINFO, and REALINFO continue to report REAL_BITCOIN_SIGNING_ENABLED=0, TESTNET_SIGNING_ENABLED=0, and MAINNET_SIGNING_ENABLED=0.
- REALINFO now explicitly describes the testnet dry-run as watch-only:
  TESTNET_DRY_RUN_WATCH_ONLY=1, TESTNET_DRY_RUN_DEVICE_SIGNATURE=0, and TESTNET_DRY_RUN_BROADCAST=0.
- REALINFO reports BLOCKER_TESTNET_REGRESSION=0 because focused and master regressions now cover the safe testnet dry-run path.
- C8.0 readiness regression was forward-hardened so it continues to prove the safety properties while later C8.x stage labels advance.
- Added tools/wallet_c8_1_testnet_watch_only_dry_run_regression.ps1.
- Added C8.1 to the master regression suite and source audit.

Passing proof:

- Firmware clean build passed with 0 errors and 1 warning.
- Firmware flash and verify passed.
- UART probe showed C8.1 labels on the live STM32 device.
- C8_0_REAL_BITCOIN_READINESS_REGRESSION_PASS
- C8_1_REALINFO_WATCH_ONLY_PASS
- C8_1_VERSION_POLICY_WATCH_ONLY_PASS
- C8_1_HOST_TESTNET_WATCH_ONLY_TRANSCRIPT_PASS
- C8_1_HOST_TESTNET_NO_SIGN_PASS
- C8_1_TESTNET_WATCH_ONLY_DRY_RUN_REGRESSION_PASS
- C8_1_TESTNET_WATCH_ONLY_DRY_RUN_SOURCE_AUDIT_PASS
- Full automated master regression passed with ALL_REGRESSIONS_PASS.

Safety notes:

- C8.1 does not enable testnet signing.
- C8.1 does not enable mainnet signing.
- TESTNET and MAINNET candidates still reject with ERR POLICY -42 before SIGN.
- The C8.1 host dry-run proof produced RAW_TX_PRESENT=0, SIGN_SENT=0, and NO_SIGN_SENT.
- TROPIC AUTH_COUNT remained unchanged during C8.1 manifest, identity, and rejected testnet dry-run checks.

Master log:

logs\master_c8_1_testnet_dry_run_20260621_041938.out.log

Backup:

C:\stm32_backups\HardwarePrototype_C8_1_TESTNET_WATCH_ONLY_DRY_RUN_ALL_PASS

## C8.2 testnet policy fixtures - PASS

Date: 2026-06-21

Milestone:

C8_2_TESTNET_POLICY_FIXTURES_ALL_PASS

What changed:

- Firmware now reports REAL_BITCOIN_STAGE=C8.2_TESTNET_POLICY_FIXTURES.
- VERSION, POLICYINFO, and REALINFO advertise TESTNET_POLICY_FIXTURES_SUPPORTED=1.
- VERSION, POLICYINFO, and REALINFO continue to report REAL_BITCOIN_SIGNING_ENABLED=0, TESTNET_SIGNING_ENABLED=0, and MAINNET_SIGNING_ENABLED=0.
- REALINFO now includes a testnet policy fixture manifest:
  network TESTNET, max input count 2, one payment plus one change output, legacy P2PKH only, dust limit 546 sats, max fee 20000 sats, and max payment 70000 sats.
- REALINFO records future testnet signing requirements before any testnet signing can be enabled:
  CHECK_ID, PIN session, user confirmation, and TROPIC auth gate.
- C8.1 watch-only dry-run regression was forward-hardened so it remains valid as C8.x stage labels advance.
- Added tools/wallet_c8_2_testnet_policy_fixtures_regression.ps1.
- Added C8.2 to the master regression suite and source audit.

Passing proof:

- Firmware clean build passed with 0 errors and 1 warning.
- Firmware flash and verify passed.
- C8_1_TESTNET_WATCH_ONLY_DRY_RUN_REGRESSION_PASS on C8.2 firmware.
- C8_2_REALINFO_POLICY_FIXTURES_PASS
- C8_2_VERSION_POLICY_FIXTURE_LABELS_PASS
- C8_2_HOST_TESTNET_POLICY_FIXTURE_TRANSCRIPT_PASS
- C8_2_HOST_TWO_INPUT_TESTNET_NO_SIGN_PASS
- C8_2_TESTNET_POLICY_FIXTURES_REGRESSION_PASS
- C8_2_TESTNET_POLICY_FIXTURES_SOURCE_AUDIT_PASS
- Full automated master regression passed with ALL_REGRESSIONS_PASS.

Safety notes:

- C8.2 does not enable testnet signing.
- C8.2 does not enable mainnet signing.
- TESTNET policy fixtures are host/device readiness metadata only.
- The C8.2 two-input TESTNET fixture rejected at CHECK with ERR POLICY -42.
- The C8.2 host proof produced RAW_TX_PRESENT=0, SIGN_SENT=0, and NO_SIGN_SENT.
- TROPIC AUTH_COUNT remained unchanged during C8.2 manifest and rejected testnet fixture checks.

Master log:

logs\master_c8_2_policy_fixtures_20260621_045027.out.log

Backup:

C:\stm32_backups\HardwarePrototype_C8_2_TESTNET_POLICY_FIXTURES_ALL_PASS

## C8.3 testnet address derivation dry-run - PASS

Date: 2026-06-21

Milestone:

C8_3_TESTNET_ADDRESS_DERIVATION_DRY_RUN_ALL_PASS

What changed:

- Firmware now reports REAL_BITCOIN_STAGE=C8.5_TESTNET_UNSIGNED_TX_PSBT_DRY_RUN while preserving the C8.3 derivation manifest.
- VERSION, POLICYINFO, and REALINFO advertise TESTNET_DERIVATION_DRY_RUN_SUPPORTED=1.
- VERSION, POLICYINFO, and REALINFO continue to report TESTNET_DERIVATION_SIGNING_ENABLED=0.
- REALINFO describes future testnet derivation metadata without deriving or exporting keys:
  account path m/84h/1h/0h, receive path template m/84h/1h/0h/0/{index}, change path template m/84h/1h/0h/1/{index}, receive index 0, and change index 0.
- REALINFO reports TESTNET_XPUB_EXPORT_ENABLED=0 and TESTNET_DERIVATION_DEVICE_SIGNATURE=0.
- Added tools/wallet_c8_3_testnet_address_derivation_dry_run_regression.ps1.
- Added C8.3 to the master regression suite and source audit.

Passing proof:

- Firmware clean build passed with 0 errors and 1 warning.
- Firmware flash and verify passed.
- C8_3_REALINFO_DERIVATION_MANIFEST_PASS
- C8_3_VERSION_POLICY_DERIVATION_LABELS_PASS
- C8_3_HOST_TESTNET_DERIVATION_TRANSCRIPT_PASS
- C8_3_HOST_TESTNET_DERIVATION_NO_SIGN_PASS
- C8_3_TESTNET_ADDRESS_DERIVATION_DRY_RUN_REGRESSION_PASS
- C8_3_TESTNET_ADDRESS_DERIVATION_DRY_RUN_SOURCE_AUDIT_PASS
- Full automated master regression passed with ALL_REGRESSIONS_PASS.

Safety notes:

- C8.3 does not enable testnet signing.
- C8.3 does not enable mainnet signing.
- C8.3 does not export an xpub or produce a device address signature.
- TESTNET candidates still reject at CHECK with ERR POLICY -42 before SIGN.
- The C8.3 host proof produced RAW_TX_PRESENT=0, SIGN_SENT=0, and NO_SIGN_SENT.
- TROPIC AUTH_COUNT remained unchanged during C8.3 manifest and rejected testnet derivation checks.

Master log:

logs\master_c8_5_unsigned_tx_psbt_20260621_125844.out.log

Backup:

C:\stm32_backups\HardwarePrototype_C8_3_TESTNET_ADDRESS_DERIVATION_DRY_RUN_ALL_PASS

## C8.4 testnet fee/change policy fixtures - PASS

Date: 2026-06-21

Milestone:

C8_4_TESTNET_FEE_CHANGE_POLICY_FIXTURES_ALL_PASS

What changed:

- Firmware now preserves a C8.4 testnet fee/change policy fixture manifest inside REALINFO.
- VERSION, POLICYINFO, and REALINFO advertise TESTNET_FEE_CHANGE_FIXTURES_SUPPORTED=1.
- VERSION, POLICYINFO, and REALINFO continue to report TESTNET_FEE_CHANGE_SIGNING_ENABLED=0.
- REALINFO records fixture-only fee bounds:
  min fee 546 sats, max fee 20000 sats, min fee rate 1000 sats/kvB, and max fee rate 100000 sats/kvB.
- REALINFO records future change requirements:
  derived change path required, change output required, dust limit 546 sats, derivation metadata only, and dry-run-only change ownership proof.
- Added tools/wallet_c8_4_testnet_fee_change_policy_fixtures_regression.ps1.
- Added C8.4 to the master regression suite and source audit.

Passing proof:

- Firmware clean build passed with 0 errors and 1 warning.
- Firmware flash and verify passed.
- C8_4_REALINFO_FEE_CHANGE_FIXTURES_PASS
- C8_4_VERSION_POLICY_FEE_CHANGE_LABELS_PASS
- C8_4_HOST_TESTNET_FEE_CHANGE_TRANSCRIPT_PASS
- C8_4_HOST_TESTNET_FEE_CHANGE_NO_SIGN_PASS
- C8_4_TESTNET_FEE_CHANGE_POLICY_FIXTURES_REGRESSION_PASS
- C8_4_TESTNET_FEE_CHANGE_POLICY_FIXTURES_SOURCE_AUDIT_PASS
- Full automated master regression passed with ALL_REGRESSIONS_PASS.

Safety notes:

- C8.4 does not enable testnet signing.
- C8.4 does not enable mainnet signing.
- C8.4 fee/change policy data is fixture-only and does not enable network broadcast.
- TESTNET fee/change fixtures still reject at CHECK with ERR POLICY -42 before SIGN.
- The C8.4 host proof produced RAW_TX_PRESENT=0, SIGN_SENT=0, and NO_SIGN_SENT.
- TROPIC AUTH_COUNT remained unchanged during C8.4 manifest and rejected testnet fee/change checks.

Master log:

logs\master_c8_5_unsigned_tx_psbt_20260621_125844.out.log

Backup:

C:\stm32_backups\HardwarePrototype_C8_4_TESTNET_FEE_CHANGE_POLICY_FIXTURES_ALL_PASS

## C8.5 testnet unsigned transaction/PSBT dry-run - PASS

Date: 2026-06-21

Milestone:

C8_5_TESTNET_UNSIGNED_TX_PSBT_DRY_RUN_ALL_PASS

What changed:

- Firmware now reports REAL_BITCOIN_STAGE=C8.5_TESTNET_UNSIGNED_TX_PSBT_DRY_RUN.
- VERSION, POLICYINFO, and REALINFO advertise TESTNET_UNSIGNED_TX_PSBT_DRY_RUN_SUPPORTED=1.
- VERSION, POLICYINFO, and REALINFO continue to report TESTNET_UNSIGNED_TX_SIGNING_ENABLED=0.
- REALINFO describes a future unsigned testnet PSBT-like dry-run format:
  up to two inputs, exactly two outputs, required TESTNET global network, required prevouts, and required derived change metadata.
- REALINFO explicitly reports TESTNET_UNSIGNED_TX_DEVICE_SIGNATURE=0, TESTNET_UNSIGNED_TX_RAW_TX=0, and TESTNET_UNSIGNED_TX_BROADCAST=0.
- REALINFO advances NEXT_SAFE_STAGE to C8.6_TESTNET_ACTIVATION_CHECKLIST.
- Added tools/wallet_c8_5_testnet_unsigned_tx_psbt_dry_run_regression.ps1.
- Added C8.5 to the master regression suite and source audit.

Passing proof:

- Firmware clean build passed with 0 errors and 1 warning.
- Firmware flash and verify passed.
- C8_2_TESTNET_POLICY_FIXTURES_REGRESSION_PASS on C8.5 firmware.
- C8_3_TESTNET_ADDRESS_DERIVATION_DRY_RUN_REGRESSION_PASS
- C8_4_TESTNET_FEE_CHANGE_POLICY_FIXTURES_REGRESSION_PASS
- C8_5_REALINFO_UNSIGNED_TX_PSBT_PASS
- C8_5_VERSION_POLICY_UNSIGNED_TX_LABELS_PASS
- C8_5_HOST_TESTNET_UNSIGNED_TX_TRANSCRIPT_PASS
- C8_5_HOST_TESTNET_UNSIGNED_TX_NO_SIGN_PASS
- C8_5_TESTNET_UNSIGNED_TX_PSBT_DRY_RUN_REGRESSION_PASS
- C8_5_TESTNET_UNSIGNED_TX_PSBT_DRY_RUN_SOURCE_AUDIT_PASS
- Full automated master regression passed with ALL_REGRESSIONS_PASS.

Safety notes:

- C8.5 does not enable testnet signing.
- C8.5 does not enable mainnet signing.
- C8.5 does not produce a testnet RAW_TX and does not broadcast.
- TESTNET unsigned transaction dry-runs still reject at CHECK with ERR POLICY -42 before SIGN.
- The C8.5 host proof produced RAW_TX_PRESENT=0, SIGN_SENT=0, and NO_SIGN_SENT.
- TROPIC AUTH_COUNT remained unchanged during C8.5 manifest and rejected testnet unsigned transaction checks.

Master log:

logs\master_c8_5_unsigned_tx_psbt_20260621_125844.out.log

Backup:

C:\stm32_backups\HardwarePrototype_C8_5_TESTNET_UNSIGNED_TX_PSBT_DRY_RUN_ALL_PASS

## C8.6 testnet activation checklist - PASS

Date: 2026-06-21

Milestone:

C8_6_TESTNET_ACTIVATION_CHECKLIST_ALL_PASS

What changed:

- Firmware now reports REAL_BITCOIN_STAGE=C8.6_TESTNET_ACTIVATION_CHECKLIST.
- VERSION, POLICYINFO, and REALINFO advertise TESTNET_ACTIVATION_CHECKLIST_SUPPORTED=1.
- VERSION, POLICYINFO, and REALINFO continue to report TESTNET_ACTIVATION_SIGNING_ENABLED=0.
- REALINFO now publishes an explicit activation checklist instead of implying testnet readiness:
  TESTNET_ACTIVATION_READY=0, TESTNET_ACTIVATION_STATUS=BLOCKED, and TESTNET_ACTIVATION_MODE=CHECKLIST_ONLY_NO_SIGNING.
- REALINFO records the activation guardrails:
  firmware change required, compile-time flag required, flag state 0, test funds only, user confirmation, physical confirmation, and mainnet lockout.
- REALINFO records checklist items that currently pass:
  regtest regressions, testnet policy fixtures, testnet dry-run PSBT, and mainnet lockout.
- REALINFO records checklist items that still block activation:
  real address derivation, change derivation, real fee policy, secure display, TROPIC secp256k1 signing, testnet signing flag, and testnet signing regression.
- Added tools/wallet_c8_6_testnet_activation_checklist_regression.ps1.
- Added C8.6 to the master regression suite and source audit.
- Forward-hardened the C8.5 unsigned tx/PSBT dry-run regression so it remains valid as the overall real-Bitcoin stage advances.

Passing proof:

- Board connection checked after unplug/replug:
  ST-LINK saw NUCLEO-U575ZI-Q, voltage 3.29V, and ST-LINK VCP on COM3.
- Firmware clean build passed with 0 errors and 1 warning.
- Firmware flash and verify passed.
- C8_5_TESTNET_UNSIGNED_TX_PSBT_DRY_RUN_REGRESSION_PASS on C8.6 firmware.
- C8_6_REALINFO_ACTIVATION_CHECKLIST_PASS
- C8_6_VERSION_POLICY_ACTIVATION_LABELS_PASS
- C8_6_HOST_TESTNET_ACTIVATION_CHECKLIST_TRANSCRIPT_PASS
- C8_6_HOST_TESTNET_ACTIVATION_NO_SIGN_PASS
- C8_6_TESTNET_ACTIVATION_CHECKLIST_REGRESSION_PASS
- C8_6_TESTNET_ACTIVATION_CHECKLIST_SOURCE_AUDIT_PASS
- Full automated master regression passed with ALL_REGRESSIONS_PASS.

Safety notes:

- C8.6 does not enable testnet signing.
- C8.6 does not enable mainnet signing.
- C8.6 does not produce a testnet RAW_TX and does not broadcast.
- TESTNET activation-checklist dry-runs still reject at CHECK with ERR POLICY -42 before SIGN.
- The C8.6 host proof produced RAW_TX_PRESENT=0, SIGN_SENT=0, and NO_SIGN_SENT.
- TROPIC AUTH_COUNT remained unchanged during C8.6 manifest and rejected testnet activation checks.

Master log:

logs\master_c8_6_activation_checklist_20260621_144616.out.log

Backup:

C:\stm32_backups\HardwarePrototype_C8_6_TESTNET_ACTIVATION_CHECKLIST_ALL_PASS

## C8.7 testnet dry-run artifact export - PASS

Date: 2026-06-21

Milestone:

C8_7_TESTNET_DRY_RUN_ARTIFACT_EXPORT_ALL_PASS

What changed:

- Firmware now reports REAL_BITCOIN_STAGE=C8.9_TESTNET_SIGNING_COMPILE_TIME_GUARD while preserving the C8.7 artifact-export manifest.
- VERSION, POLICYINFO, and REALINFO advertise TESTNET_ARTIFACT_EXPORT_SUPPORTED=1.
- REALINFO declares the C8.7 artifact format as PSBT_LIKE_INTENT_TEXT_V1.
- Host regression exports an unsigned testnet intent artifact to logs\c8_7_testnet_intent_artifact.txt.
- The artifact records device identity, TESTNET intent fields, input/output amounts, fee, and explicit no-sign/no-raw-tx/no-broadcast flags.
- Added tools/wallet_c8_7_testnet_dry_run_artifact_export_regression.ps1.
- Added C8.7 to the master regression suite and source audit.

Passing proof:

- Firmware clean build passed with 0 errors and 1 warning.
- Firmware flash and verify passed.
- C8_7_REALINFO_ARTIFACT_EXPORT_PASS
- C8_7_VERSION_POLICY_ARTIFACT_LABELS_PASS
- C8_7_HOST_TESTNET_ARTIFACT_FILE_PASS
- C8_7_HOST_TESTNET_ARTIFACT_NO_SIGN_PASS
- C8_7_TESTNET_DRY_RUN_ARTIFACT_EXPORT_REGRESSION_PASS
- C8_7_TESTNET_DRY_RUN_ARTIFACT_EXPORT_SOURCE_AUDIT_PASS

Safety notes:

- C8.7 does not enable testnet signing.
- C8.7 does not enable mainnet signing.
- C8.7 does not produce a testnet RAW_TX and does not broadcast.
- TESTNET artifact dry-runs reject at CHECK with ERR POLICY -42 before SIGN.
- The C8.7 host proof produced RAW_TX_PRESENT=0, SIGN_SENT=0, and NO_SIGN_SENT.
- TROPIC AUTH_COUNT remained unchanged during manifest and rejected testnet artifact checks.

Artifact:

logs\c8_7_testnet_intent_artifact.txt

## C8.8 testnet derivation model decision - PASS

Date: 2026-06-21

Milestone:

C8_8_TESTNET_DERIVATION_MODEL_DECISION_ALL_PASS

What changed:

- REALINFO now records the selected future testnet derivation model:
  BIP84_TESTNET_P2WPKH_ACCOUNT.
- REALINFO records account, receive, and change paths:
  m/84h/1h/0h, m/84h/1h/0h/0/{index}, and m/84h/1h/0h/1/{index}.
- REALINFO records address format tb1q_P2WPKH.
- REALINFO explicitly blocks xpub export and reports DEVICE_DERIVES_KEYS=0 until key derivation is implemented.
- Added tools/wallet_c8_8_testnet_derivation_model_decision_regression.ps1.
- Added C8.8 to the master regression suite and source audit.

Passing proof:

- C8_8_REALINFO_DERIVATION_DECISION_PASS
- C8_8_VERSION_POLICY_DERIVATION_DECISION_LABELS_PASS
- C8_8_HOST_DERIVATION_DECISION_TRANSCRIPT_PASS
- C8_8_TESTNET_DERIVATION_MODEL_DECISION_REGRESSION_PASS
- C8_8_TESTNET_DERIVATION_MODEL_DECISION_SOURCE_AUDIT_PASS

Safety notes:

- C8.8 is a model decision only.
- No real testnet keys are derived on-device yet.
- No xpub is exported.
- No testnet/mainnet signing is enabled.
- TROPIC AUTH_COUNT remained unchanged during the C8.8 manifest checks.

## C8.9 testnet signing compile-time guard - PASS

Date: 2026-06-21

Milestone:

C8_9_TESTNET_SIGNING_COMPILE_TIME_GUARD_ALL_PASS

What changed:

- Firmware now reports REAL_BITCOIN_STAGE=C8.9_TESTNET_SIGNING_COMPILE_TIME_GUARD.
- REALINFO, VERSION, and POLICYINFO expose TESTNET_SIGNING_COMPILE_TIME_GUARD_SUPPORTED=1.
- Firmware defines WALLET_TESTNET_SIGNING_BUILD_FLAG and WALLET_MAINNET_SIGNING_BUILD_FLAG defaults as 0.
- REALINFO reports TESTNET_SIGNING_BUILD_FLAG=0 and MAINNET_SIGNING_BUILD_FLAG=0.
- REALINFO reports TESTNET_SIGNING_RUNTIME_OVERRIDE_SUPPORTED=0.
- REALINFO reports TESTNET_SIGNING_SOURCE_CHANGE_REQUIRED=1 and TESTNET_SIGNING_REGRESSION_REQUIRED=1.
- REALINFO advances NEXT_SAFE_STAGE=C9.0_TESTNET_SIGNING_MODE_DESIGN.
- Added tools/wallet_c8_9_testnet_signing_compile_time_guard_regression.ps1.
- Added C8.9 to the master regression suite and source audit.
- Hardened wallet_cmd_find_value() so command keys must match exact line-start keys; this prevents PSBT_GLOBAL_NETWORK from being mistaken for legacy NETWORK.

Passing proof:

- Firmware clean build passed with 0 errors and 1 warning.
- Firmware flash and verify passed.
- SIGNING_TRANSCRIPT_REGRESSION_PASS
- STM32_REGTEST_FULL_LOOP_PASS
- C8_9_REALINFO_COMPILE_TIME_GUARD_PASS
- C8_9_VERSION_POLICY_GUARD_LABELS_PASS
- C8_9_HOST_TESTNET_GUARD_NO_SIGN_PASS
- C8_9_TESTNET_SIGNING_COMPILE_TIME_GUARD_REGRESSION_PASS
- C8_9_TESTNET_SIGNING_COMPILE_TIME_GUARD_SOURCE_AUDIT_PASS
- Full automated master regression passed with ALL_REGRESSIONS_PASS.

Safety notes:

- C8.9 does not enable testnet signing.
- C8.9 does not enable mainnet signing.
- TESTNET signing cannot be enabled by UART/runtime override.
- TESTNET attempts still reject at CHECK with ERR POLICY -42 before SIGN.
- The C8.9 host proof produced RAW_TX_PRESENT=0, SIGN_SENT=0, and NO_SIGN_SENT.
- TROPIC AUTH_COUNT remained unchanged during C8.9 manifest and rejected testnet signing-guard checks.
- REGTEST signing still passes with CHECK_ID, confirm-code approval, PIN session, TROPIC auth gate, RAW_TX generation, Bitcoin Core broadcast, mining, and verification.

Master log:

logs\master_c8_9_compile_time_guard_final_20260621_163001.out.log

Backups:

C:\stm32_backups\HardwarePrototype_C8_7_TESTNET_DRY_RUN_ARTIFACT_EXPORT_ALL_PASS

C:\stm32_backups\HardwarePrototype_C8_8_TESTNET_DERIVATION_MODEL_DECISION_ALL_PASS

C:\stm32_backups\HardwarePrototype_C8_9_TESTNET_SIGNING_COMPILE_TIME_GUARD_ALL_PASS

## C9.0 testnet signing mode design - PASS

Date: 2026-06-21

Milestone:

C9_0_TESTNET_SIGNING_MODE_DESIGN_ALL_PASS

What changed:

- Firmware now reports REAL_BITCOIN_STAGE=C9.0_TESTNET_SIGNING_MODE_DESIGN.
- REALINFO, VERSION, and POLICYINFO advertise TESTNET_SIGNING_MODE_DESIGN_SUPPORTED=1.
- REALINFO publishes TESTNET_SIGNING_MODE_VERSION=C9.0_TESTNET_SIGNING_MODE_DESIGN_V1.
- REALINFO defines the future signing mode as DESIGN_ONLY_NOT_ACTIVE and TESTNET_ONLY.
- REALINFO keeps TESTNET_SIGNING_MODE_SIGNING_ENABLED=0, TESTNET_SIGNING_ENABLED=0, and MAINNET_SIGNING_ENABLED=0.
- REALINFO documents required activation gates:
  compile-time flag, test funds, PIN session, CHECK_ID, user confirmation, physical confirmation, TROPIC auth gate, derived testnet keys, derived change, fee policy, and mainnet lockout.
- REALINFO reports no runtime override and no broadcast path:
  TESTNET_SIGNING_MODE_RUNTIME_OVERRIDE_SUPPORTED=0 and TESTNET_SIGNING_MODE_BROADCAST_ENABLED=0.
- REALINFO advances NEXT_SAFE_STAGE=C9.1_TESTNET_SIGNING_DERIVATION_IMPLEMENTATION.
- Added tools/wallet_c9_0_testnet_signing_mode_design_regression.ps1.
- Added C9.0 to the master regression suite and source audit.
- Forward-hardened C8.9 so it remains valid after the real-Bitcoin stage advances to C9.0.
- Hardened tools/wallet_assert_truth_labels.ps1 with a short probe retry loop for long COM-port-heavy master runs.

Passing proof:

- Firmware clean build passed with 0 errors and 1 warning.
- Firmware flash and verify passed.
- C8_9_TESTNET_SIGNING_COMPILE_TIME_GUARD_REGRESSION_PASS on C9.0 firmware.
- C9_0_REALINFO_SIGNING_MODE_DESIGN_PASS
- C9_0_VERSION_POLICY_SIGNING_MODE_LABELS_PASS
- C9_0_SIGNING_MODE_MANIFEST_AUTH_UNCHANGED
- C9_0_HOST_TESTNET_SIGNING_MODE_NO_SIGN_PASS
- C9_0_HOST_TESTNET_SIGNING_MODE_AUTH_UNCHANGED
- C9_0_TESTNET_SIGNING_MODE_DESIGN_REGRESSION_PASS
- C9_0_TESTNET_SIGNING_MODE_DESIGN_SOURCE_AUDIT_PASS
- SIGNING_TRANSCRIPT_REGRESSION_PASS
- STM32_REGTEST_FULL_LOOP_PASS
- TRUTH_LABEL_ASSERT_PASS
- Full automated master regression passed with ALL_REGRESSIONS_PASS.

Safety notes:

- C9.0 does not enable testnet signing.
- C9.0 does not enable mainnet signing.
- TESTNET signing cannot be enabled by UART/runtime override.
- TESTNET attempts still reject at CHECK with ERR POLICY -42 before SIGN.
- The C9.0 host proof produced RAW_TX_PRESENT=0, SIGN_SENT=0, and NO_SIGN_SENT.
- TROPIC AUTH_COUNT remained unchanged during C9.0 manifest and rejected testnet signing-mode checks.
- REGTEST signing still passes with CHECK_ID, confirm-code approval, PIN session, TROPIC auth gate, RAW_TX generation, Bitcoin Core broadcast, mining, and verification.

Master log:

logs\master_c9_0_signing_mode_design_final_20260621_174730.out.log

Backup:

C:\stm32_backups\HardwarePrototype_C9_0_TESTNET_SIGNING_MODE_DESIGN_ALL_PASS

## C9.1-C9.5 testnet pre-activation foundation - PASS

Date: 2026-06-21

Milestone:

C9_1_TO_C9_5_TESTNET_PRE_ACTIVATION_ALL_PASS

What changed:

- Firmware now reports REAL_BITCOIN_STAGE=C9.5_GUARDED_TESTNET_SIGNING_ACTIVATION_DRY_RUN.
- REALINFO, VERSION, and POLICYINFO advertise the C9.1-C9.5 pre-activation labels.
- C9.1 documents the selected testnet derivation foundation:
  BIP84 testnet P2WPKH account m/84h/1h/0h, receive path m/84h/1h/0h/0/{index}, and change path m/84h/1h/0h/1/{index}.
- C9.2 documents testnet change derivation enforcement requirements.
- C9.3 documents the draft real testnet fee policy:
  min output 546 sats, max fee 20000 sats, fee-rate range 1000-100000 sats/kvB.
- C9.4 documents PSBT-like unsigned transaction validation requirements.
- C9.5 documents guarded testnet signing activation dry-run:
  all runtime gates required, signing still disabled, RAW_TX still disabled.
- C9.6 is intentionally blocked in firmware labels:
  TESTNET_SIGNING_ENABLE_BLOCKED=1 and TESTNET_SIGNING_ENABLE_ACTUAL_SIGNING_ENABLED=0.
- Added tools/wallet_c9_1_to_c9_5_testnet_pre_activation_regression.ps1.
- Added the new focused regression to tools/wallet_run_all_regressions.ps1.
- Added C9.1-C9.5/C9.6-blocked checks to tools/wallet_source_audit.ps1.
- Forward-hardened the C9.0 regression so it remains valid after the real-Bitcoin stage advances.

Passing proof:

- Firmware clean build passed with 0 errors and 1 warning.
- Firmware flash and verify passed.
- C9_0_TESTNET_SIGNING_MODE_DESIGN_REGRESSION_PASS on C9.5 firmware.
- C9_1_REALINFO_DERIVATION_IMPLEMENTATION_FOUNDATION_PASS
- C9_2_REALINFO_CHANGE_DERIVATION_ENFORCEMENT_PASS
- C9_3_REALINFO_REAL_FEE_POLICY_PASS
- C9_4_REALINFO_UNSIGNED_TX_VALIDATION_PASS
- C9_5_REALINFO_SIGNING_ACTIVATION_DRY_RUN_PASS
- C9_6_TESTNET_SIGNING_ENABLE_BLOCKED_PASS
- C9_1_TO_C9_5_VERSION_POLICY_LABELS_PASS
- C9_1_TO_C9_5_TESTNET_PRE_ACTIVATION_MANIFEST_AUTH_UNCHANGED
- C9_1_TO_C9_5_HOST_TESTNET_NO_SIGN_PASS
- C9_1_TO_C9_5_HOST_TESTNET_PRE_ACTIVATION_AUTH_UNCHANGED
- C9_1_TO_C9_5_TESTNET_PRE_ACTIVATION_REGRESSION_PASS
- C9_1_TO_C9_5_TESTNET_PRE_ACTIVATION_SOURCE_AUDIT_PASS
- TRUTH_LABEL_ASSERT_PASS

Safety notes:

- C9.1-C9.5 do not enable testnet signing.
- C9.6 actual signing was not enabled in this run.
- Mainnet signing remains disabled.
- TESTNET attempts still reject at CHECK with ERR POLICY -42 before SIGN.
- The C9.1-C9.5 host proof produced RAW_TX_PRESENT=0, SIGN_SENT=0, and NO_SIGN_SENT.
- TROPIC AUTH_COUNT remained unchanged during manifest checks and rejected testnet host checks.
- Real C9.6 signing requires explicit compile-time activation, user-provided test funds, physical confirmation, and mainnet lockout proof.
- A full master run was not repeated for this milestone because the change was limited to firmware reporting labels and focused testnet pre-activation regressions.

Backup:

C:\stm32_backups\HardwarePrototype_C9_1_TO_C9_5_TESTNET_PRE_ACTIVATION_ALL_PASS

## C9.6 testnet signing enable on test funds only - PASS

Date: 2026-06-21

Milestone:

C9_6_TESTNET_SIGNING_ENABLE_ON_TEST_FUNDS_ONLY_PASS

What changed:

- Firmware now reports REAL_BITCOIN_STAGE=C9.6_TESTNET_SIGNING_ENABLE_ON_TEST_FUNDS_ONLY.
- Build config explicitly sets WALLET_TESTNET_SIGNING_BUILD_FLAG=1 and WALLET_MAINNET_SIGNING_BUILD_FLAG=0.
- Firmware policy model now reports REGTEST_TESTNET_P2PKH_ALLOWLIST_V1.
- CHECK, policy recheck, and final SIGN now share one network gate:
  REGTEST is allowed, TESTNET is allowed only when WALLET_TESTNET_SIGNING_BUILD_FLAG=1, and MAINNET remains rejected.
- TESTNET CHECK summaries now bind NETWORK=TESTNET into CHECK_ID instead of collapsing to NON_REGTEST_OR_MISSING.
- TESTNET SIGN uses the existing authorization path:
  CHECK_ID, exact host/device binding, UART confirm-code or USER button confirmation, PIN session, one-shot approval, and TROPIC auth gate.
- C9.6 labels report TESTNET_SIGNING_ENABLED=1, TESTNET_SIGNING_ENABLE_ACTIVE=1, TESTNET_SIGNING_ENABLE_BLOCKED=0, and MAINNET_SIGNING_ENABLED=0.
- Broadcast remains disabled for testnet in firmware labels:
  TESTNET_SIGNING_ENABLE_BROADCAST=0.
- Added tools/wallet_c9_6_testnet_signing_enable_regression.ps1.
- Added C9.6 to tools/wallet_run_all_regressions.ps1 for visibility.
- Updated source audit and truth-label assertions for the C9.6 testnet-on/mainnet-off posture.

Passing proof:

- Firmware clean build passed with 0 errors and 1 warning.
- Firmware flash and verify passed.
- C9_6_REALINFO_TESTNET_SIGNING_ENABLE_PASS
- C9_6_VERSION_POLICY_LABELS_PASS
- C9_6_TESTNET_SIGNING_ENABLE_MANIFEST_AUTH_UNCHANGED
- C9_6_HOST_TESTNET_SIGNING_RAW_TX_PASS
- C9_6_HOST_TESTNET_SIGNING_AUTH_INCREMENTED_ONCE
- C9_6_HOST_MAINNET_NO_SIGN_PASS
- C9_6_HOST_MAINNET_REJECT_AUTH_UNCHANGED
- C9_6_TESTNET_SIGNING_ENABLE_REGRESSION_PASS
- C9_6_TESTNET_SIGNING_ENABLE_SOURCE_AUDIT_PASS
- TRUTH_LABEL_ASSERT_PASS
- STM32_REGTEST_FULL_LOOP_PASS on the same C9.6 firmware.

Safety notes:

- MAINNET remains locked out and rejected before SIGN with ERR POLICY -42.
- HOST PRIVKEY remains disabled.
- CURRENT_DEV_KEY_ENABLED remains 0.
- BITCOIN_DIRECT_TROPIC_SIGNING remains 0.
- TROPIC_CURVE_SECP256K1 remains 0, so TROPIC01 is still an auth gate, not the Bitcoin signer.
- C9.6 signs a TESTNET-format legacy P2PKH raw transaction and does not broadcast it to testnet.
- BIP84/device-derived testnet key signing is still not implemented:
  TESTNET_SIGNING_ENABLE_BIP84_DEVICE_DERIVATION=0.
- The C9.6 positive test used UART confirm-code approval; no physical USER button press was required in this run.
- A full historical master run was not repeated because older C7/C8/C9 disabled-testnet regressions intentionally conflict with C9.6 testnet signing activation. The focused C9.6 regression, source audit, truth labels, and REGTEST full loop passed.

Backup:

C:\stm32_backups\HardwarePrototype_C9_6_TESTNET_SIGNING_ENABLE_ON_TEST_FUNDS_ONLY_PASS

## C9.7 testnet BIP84 identity + C9.8 testnet change derivation enforcement - PASS

Date: 2026-06-21

Milestone:

C9_7_C9_8_TESTNET_BIP84_CHANGE_PASS

What changed:

- Firmware now reports a public C9.7 testnet BIP84 identity surface:
  TESTNET_BIP84_ADDRESS=tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx,
  TESTNET_BIP84_SCRIPT_P2WPKH=0014751e76e8199196d454941c45d1b3a323f1433bd6,
  TESTNET_BIP84_ACCOUNT_PATH=m/84h/1h/0h,
  TESTNET_BIP84_RECEIVE_PATH=m/84h/1h/0h/0/0, and
  TESTNET_BIP84_CHANGE_PATH=m/84h/1h/0h/1/0.
- Firmware truth labels remain explicit that this is public identity/change metadata, not device HD key derivation:
  TESTNET_BIP84_DEVICE_DERIVES_KEYS=0 and TESTNET_BIP84_SIGNING_ENABLED=0.
- TESTNET PSBT-like commands now require PSBT_OUTPUT1_DERIVATION=m/84h/1h/0h/1/0.
- TESTNET CHECK/SIGN now require the change output script to exactly match the C9.7 P2WPKH script.
- REGTEST compatibility is preserved: REGTEST still accepts the existing P2PKH change script and mvp-static-change/0 metadata.
- REALINFO/POLICYINFO now report C9.8_TESTNET_CHANGE_DERIVATION_ENFORCEMENT and BLOCKER_CHANGE_DERIVATION=0 while keeping BLOCKER_BIP84_DEVICE_DERIVED_KEYS=1.
- Added tools/wallet_c9_7_c9_8_testnet_bip84_change_regression.ps1.
- Added C9.7/C9.8 to tools/wallet_run_all_regressions.ps1 for visibility.
- Updated source audit for the new C9.7/C9.8 firmware hooks and regression coverage.

Passing proof:

- Firmware clean build passed with 0 errors and 1 warning.
- Firmware flash and verify passed.
- C9_7_TESTNET_BIP84_IDENTITY_PASS
- C9_8_REALINFO_CHANGE_ENFORCEMENT_PASS
- C9_8_POLICYINFO_CHANGE_ENFORCEMENT_PASS
- C9_7_C9_8_MANIFEST_AUTH_UNCHANGED
- C9_8_TESTNET_BIP84_CHANGE_SIGNING_PASS
- C9_8_TESTNET_BIP84_CHANGE_SIGNING_AUTH_INCREMENTED_ONCE
- C9_8_TESTNET_WRONG_CHANGE_DERIVATION_REJECT_PASS with ERR POLICY -54 and no RAW_TX.
- C9_8_TESTNET_WRONG_CHANGE_SCRIPT_REJECT_PASS with ERR POLICY -39 and no RAW_TX.
- C9_8_TESTNET_NEGATIVE_CHECKS_AUTH_UNCHANGED
- C9_7_C9_8_TESTNET_BIP84_CHANGE_REGRESSION_PASS
- C9_7_C9_8_TESTNET_BIP84_CHANGE_SOURCE_AUDIT_PASS
- DEVICE_CHECK_SUMMARY_REGRESSION_PASS
- STM32_REGTEST_FULL_LOOP_PASS on the same C9.8 firmware.

Safety notes:

- MAINNET remains locked out and rejected before SIGN.
- HOST PRIVKEY remains disabled.
- CURRENT_DEV_KEY_ENABLED remains 0.
- BITCOIN_DIRECT_TROPIC_SIGNING remains 0.
- TROPIC01 remains an auth gate, not a Bitcoin secp256k1 signer.
- C9.8 still signs with the current legacy P2PKH input signing path; it enforces a BIP84/P2WPKH TESTNET change output, but it does not implement native P2WPKH input signing yet.
- TESTNET raw transaction broadcast remains outside firmware scope.
- No physical USER button press was required in this run; the regression used UART confirm-code approval.
- A full historical master run was not repeated because older disabled-testnet regressions intentionally conflict with the C9.6/C9.8 active testnet signing posture. Focused C9.7/C9.8 hardware regression, source audit, CHECK summary regression, and REGTEST full loop passed.

Backup:

C:\stm32_backups\HardwarePrototype_C9_7_C9_8_TESTNET_BIP84_CHANGE_PASS
