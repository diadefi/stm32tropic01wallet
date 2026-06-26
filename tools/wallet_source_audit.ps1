$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================================"
Write-Host " STM32 WALLET SOURCE AUDIT"
Write-Host "============================================================"

$paths = @(
    ".\Core\Src\*.c",
    ".\Core\Inc\*.h"
)

$dangerousPatterns = @(
    "WALLET_DEV_PRIVKEY_BYTES",
    "Private key = 1",
    "private key = 1",
    "Fixed deterministic regtest private key",
    "Fixed secp256k1 private key",
    "0000000000000000000000000000000000000000000000000000000000000001",
    "DEV_KEY_IN_MCU_TROPIC_AUTH_GATE",
    "0.2.0-devkey-guard",
    "Still supports PRIVKEY= in text",
    "mvp-regtest-unlock"
)

$matches = @()

foreach ($pattern in $dangerousPatterns) {
    $found = Select-String -Path $paths -Pattern $pattern -SimpleMatch -Context 1,1 -ErrorAction SilentlyContinue
    if ($found) {
        $matches += $found
    }
}

if ($matches.Count -gt 0) {
    Write-Host ""
    Write-Host "SOURCE_AUDIT_FAIL"
    Write-Host "Dangerous plaintext/dev-key remnants found:"
    Write-Host ""
    $matches | ForEach-Object {
        Write-Host "$($_.Path):$($_.LineNumber): $($_.Line)"
    }
    throw "SOURCE_AUDIT_FAIL"
}

$commandSource = Get-Content -Path ".\Core\Src\wallet_command.c" -Raw
$uartSource = Get-Content -Path ".\Core\Src\wallet_uart.c" -Raw
$keyProviderSource = Get-Content -Path ".\Core\Src\wallet_key_provider.c" -Raw
$coreSource = Get-Content -Path ".\Core\Src\wallet_core.c" -Raw
$policyHeader = Get-Content -Path ".\Core\Inc\wallet_policy.h" -Raw
$masterRegressionSource = Get-Content -Path ".\tools\wallet_run_all_regressions.ps1" -Raw
$hardwareCiSource = Get-Content -Path ".\tools\wallet_hardware_ci.ps1" -Raw
$c43AuthRegressionSource = Get-Content -Path ".\tools\wallet_c4_3_tropic_auth_policy_regression.ps1" -Raw
$c33ButtonRegressionSource = Get-Content -Path ".\tools\wallet_c3_3_physical_button_confirm_regression.ps1" -Raw
$c36ButtonRegressionSource = Get-Content -Path ".\tools\wallet_c3_6_physical_button_fresh_press_regression.ps1" -Raw
$c70RealNetworkRegressionSource = Get-Content -Path ".\tools\wallet_c7_0_real_network_safety_regression.ps1" -Raw
$c80ReadinessRegressionSource = Get-Content -Path ".\tools\wallet_c8_0_real_bitcoin_readiness_regression.ps1" -Raw
$c81TestnetDryRunRegressionSource = Get-Content -Path ".\tools\wallet_c8_1_testnet_watch_only_dry_run_regression.ps1" -Raw
$c82TestnetPolicyFixturesRegressionSource = Get-Content -Path ".\tools\wallet_c8_2_testnet_policy_fixtures_regression.ps1" -Raw
$c83AddressDerivationRegressionSource = Get-Content -Path ".\tools\wallet_c8_3_testnet_address_derivation_dry_run_regression.ps1" -Raw
$c84FeeChangeRegressionSource = Get-Content -Path ".\tools\wallet_c8_4_testnet_fee_change_policy_fixtures_regression.ps1" -Raw
$c85UnsignedTxRegressionSource = Get-Content -Path ".\tools\wallet_c8_5_testnet_unsigned_tx_psbt_dry_run_regression.ps1" -Raw
$c86ActivationChecklistRegressionSource = Get-Content -Path ".\tools\wallet_c8_6_testnet_activation_checklist_regression.ps1" -Raw
$c87ArtifactExportRegressionSource = Get-Content -Path ".\tools\wallet_c8_7_testnet_dry_run_artifact_export_regression.ps1" -Raw
$c88DerivationDecisionRegressionSource = Get-Content -Path ".\tools\wallet_c8_8_testnet_derivation_model_decision_regression.ps1" -Raw
$c89CompileTimeGuardRegressionSource = Get-Content -Path ".\tools\wallet_c8_9_testnet_signing_compile_time_guard_regression.ps1" -Raw
$c90SigningModeDesignRegressionSource = Get-Content -Path ".\tools\wallet_c9_0_testnet_signing_mode_design_regression.ps1" -Raw
$c91ToC95PreActivationRegressionSource = Get-Content -Path ".\tools\wallet_c9_1_to_c9_5_testnet_pre_activation_regression.ps1" -Raw
$c96TestnetSigningEnableRegressionSource = Get-Content -Path ".\tools\wallet_c9_6_testnet_signing_enable_regression.ps1" -Raw
$c97C98Bip84ChangeRegressionSource = Get-Content -Path ".\tools\wallet_c9_7_c9_8_testnet_bip84_change_regression.ps1" -Raw

if ($commandSource -match 'wallet_cmd_parse_hex_fixed\s*\(\s*command_text\s*,\s*"PRIVKEY"') {
    throw "SOURCE_AUDIT_FAIL: active wallet_command.c still parses host PRIVKEY"
}

if ($commandSource -notmatch 'return\s+WALLET_POLICY_ERR_LEGACY_SIGN_DISABLED\s*;') {
    throw "SOURCE_AUDIT_FAIL: legacy wallet_command_sign_text is not permanently disabled"
}

if ($policyHeader -notmatch 'WALLET_POLICY_ERR_LEGACY_SIGN_DISABLED\s+-60') {
    throw "SOURCE_AUDIT_FAIL: missing WALLET_POLICY_ERR_LEGACY_SIGN_DISABLED=-60"
}

if ($uartSource -match 'wallet_command_sign_text\s*\(') {
    throw "SOURCE_AUDIT_FAIL: UART calls legacy wallet_command_sign_text"
}

if ($uartSource -notmatch 'wallet_command_sign_text_with_private_key\s*\(') {
    throw "SOURCE_AUDIT_FAIL: UART is not using the clean key-provider signing API"
}

if ($uartSource -notmatch 'static\s+void\s+wallet_uart_secure_zero\s*\(') {
    throw "SOURCE_AUDIT_FAIL: wallet_uart.c missing volatile secure zero helper"
}

if ($uartSource -notmatch 'static\s+void\s+wallet_uart_clear_command_buffer\s*\(') {
    throw "SOURCE_AUDIT_FAIL: wallet_uart.c missing UART command buffer clear helper"
}

if ($uartSource -match 'memset\s*\(\s*wallet_uart_private_key\s*,\s*0') {
    throw "SOURCE_AUDIT_FAIL: UART private-key buffer still uses plain memset"
}

if ($uartSource -notmatch 'wallet_uart_clear_command_buffer\s*\(\s*\)\s*;\s*continue\s*;') {
    throw "SOURCE_AUDIT_FAIL: UART command buffer is not cleared on command exits"
}

if ($keyProviderSource -match 'memset\s*\(\s*out_key\s*,\s*0') {
    throw "SOURCE_AUDIT_FAIL: key-provider out_key still uses plain memset"
}

if ($keyProviderSource -notmatch 'wallet_key_provider_secure_zero\s*\(\s*out_key\s*,\s*out_key_size\s*\)') {
    throw "SOURCE_AUDIT_FAIL: key-provider out_key secure zero path missing"
}

if ($commandSource -notmatch 'static\s+void\s+wallet_command_secure_zero\s*\(') {
    throw "SOURCE_AUDIT_FAIL: wallet_command.c missing command-state secure zero helper"
}

if ($commandSource -notmatch 'wallet_command_secure_zero\s*\(\s*&wallet_command_approved_check\s*,\s*sizeof\s*\(\s*wallet_command_approved_check\s*\)\s*\)') {
    throw "SOURCE_AUDIT_FAIL: approved CHECK state is not securely cleared"
}

if ($coreSource -notmatch 'static\s+void\s+wallet_core_secure_zero\s*\(') {
    throw "SOURCE_AUDIT_FAIL: wallet_core.c missing signing-buffer secure zero helper"
}

if ($coreSource -notmatch 'wallet_core_secure_zero\s*\(\s*sig64\s*,\s*sizeof\s*\(\s*sig64\s*\)\s*\)') {
    throw "SOURCE_AUDIT_FAIL: signing signature buffer is not securely cleared"
}

if ($commandSource -match 'wallet_command_check_unlock_text|WALLET_MVP_UNLOCK_SECRET|UNLOCK_SECRET') {
    throw "SOURCE_AUDIT_FAIL: wallet_command.c still enforces or references legacy UNLOCK_SECRET"
}

if ($keyProviderSource -match 'UNLOCK_SECRET|wallet_key_provider_find_value') {
    throw "SOURCE_AUDIT_FAIL: key-provider still parses host UNLOCK_SECRET"
}

if ($keyProviderSource -notmatch 'wallet_key_provider_session_key') {
    throw "SOURCE_AUDIT_FAIL: key-provider missing C4.2 RAM-only session key"
}

if ($keyProviderSource -notmatch 'wallet_key_provider_unlock_with_pin\s*\(') {
    throw "SOURCE_AUDIT_FAIL: key-provider missing C4.2 PIN unlock API"
}

if ($keyProviderSource -notmatch 'wallet_key_provider_lock_session\s*\(') {
    throw "SOURCE_AUDIT_FAIL: key-provider missing C4.2 session clear API"
}

if ($keyProviderSource -notmatch 'wallet_secure_element_authorize_key_use\s*\(') {
    throw "SOURCE_AUDIT_FAIL: key provider is not routing successful key use through TROPIC auth gate"
}

if ($uartSource -notmatch 'AUTH_COUNT=%lu') {
    throw "SOURCE_AUDIT_FAIL: UART SEINFO does not expose AUTH_COUNT for C4.3 auth policy regression"
}

if ($c43AuthRegressionSource -notmatch 'C4_3_TROPIC_AUTH_POLICY_REGRESSION_PASS' -or
    $c43AuthRegressionSource -notmatch 'C4_3_CHECK_NO_AUTH_PASS' -or
    $c43AuthRegressionSource -notmatch 'C4_3_SUCCESSFUL_SIGN_AUTH_ONCE_PASS') {
    throw "SOURCE_AUDIT_FAIL: C4.3 TROPIC auth policy regression is missing required assertions"
}

if ($masterRegressionSource -notmatch 'wallet_c4_3_tropic_auth_policy_regression\.ps1') {
    throw "SOURCE_AUDIT_FAIL: master regression does not run C4.3 TROPIC auth policy regression"
}

if ($uartSource -notmatch 'ERR_HOST_UNLOCK_SECRET_DISABLED=-24') {
    throw "SOURCE_AUDIT_FAIL: UART does not report legacy UNLOCK_SECRET disablement"
}

if ($uartSource -notmatch 'wallet_key_provider_unlock_with_pin\s*\(') {
    throw "SOURCE_AUDIT_FAIL: UART does not route UNLOCK_PIN through key-provider"
}

if ($uartSource -notmatch 'wallet_uart_poll_button_confirm\s*\(' -or
    $uartSource -notmatch 'BSP_PB_GetState\s*\(\s*BUTTON_USER\s*\)' -or
    $uartSource -notmatch 'CONFIRM_SOURCE=BUTTON_USER' -or
    $uartSource -notmatch 'OK BUTTON_CONFIRM') {
    throw "SOURCE_AUDIT_FAIL: UART missing C3.3 physical USER button confirmation path"
}

if ($c33ButtonRegressionSource -notmatch 'PRESS_AND_RELEASE_USER_BUTTON_NOW' -or
    $c33ButtonRegressionSource -notmatch 'C3_3_PHYSICAL_BUTTON_CONFIRM_REGRESSION_PASS' -or
    $c33ButtonRegressionSource -notmatch 'C3_3_SIGN_TWICE_AFTER_BUTTON_REJECT_PASS') {
    throw "SOURCE_AUDIT_FAIL: C3.3 physical button regression is missing required assertions"
}

if ($uartSource -notmatch 'wallet_uart_button_confirm_armed' -or
    $uartSource -notmatch 'BUTTON_CONFIRM_ARMED=%lu' -or
    $uartSource -notmatch 'wallet_uart_button_confirm_armed\s*=\s*1U' -or
    $uartSource -notmatch 'wallet_uart_button_confirm_armed\s*!=\s*0U') {
    throw "SOURCE_AUDIT_FAIL: UART missing C3.6 fresh physical button press arming"
}

if ($c36ButtonRegressionSource -notmatch 'C3_6_STALE_HELD_BUTTON_IGNORED_PASS' -or
    $c36ButtonRegressionSource -notmatch 'RELEASE_THEN_PRESS_USER_BUTTON_NOW' -or
    $c36ButtonRegressionSource -notmatch 'C3_6_PHYSICAL_BUTTON_FRESH_PRESS_REGRESSION_PASS') {
    throw "SOURCE_AUDIT_FAIL: C3.6 fresh physical button regression is missing required assertions"
}

if ($commandSource -notmatch 'PSBT_GLOBAL_NETWORK' -or
    $commandSource -notmatch 'PSBT_INPUT0_TXID_LE' -or
    $commandSource -notmatch 'PSBT_OUTPUT0_SCRIPT' -or
    $commandSource -notmatch 'PSBT_OUTPUT1_SCRIPT') {
    throw "SOURCE_AUDIT_FAIL: wallet_command.c missing C5.0 PSBT-like field aliases"
}

if ($uartSource -notmatch 'COMMAND_FORMAT_PSBT_LIKE=C5\.0_PSBT_LIKE_TEXT_V1') {
    throw "SOURCE_AUDIT_FAIL: UART does not report C5.0 PSBT-like command format"
}

if ($commandSource -notmatch 'PSBT_INPUT1_TXID_LE' -or
    $commandSource -notmatch 'C5\.1_CHECK_ID_MULTI_INPUT_V1' -or
    $coreSource -notmatch 'wallet_sign_p2pkh_multi_2out_tx') {
    throw "SOURCE_AUDIT_FAIL: firmware missing C5.1 two-input parser/check-id/signing support"
}

if ($uartSource -notmatch 'MAX_INPUT_COUNT=2' -or
    $uartSource -notmatch 'TX_TYPE=LEGACY_P2PKH_1OR2IN_2OUT') {
    throw "SOURCE_AUDIT_FAIL: UART does not report C5.1 two-input support"
}

if ($commandSource -notmatch 'PSBT_OUTPUT1_DERIVATION' -or
    $commandSource -notmatch 'mvp-static-change/0' -or
    $uartSource -notmatch 'CHANGE_DERIVATION_MODEL=REGTEST_STATIC_OR_TESTNET_BIP84_METADATA') {
    throw "SOURCE_AUDIT_FAIL: firmware missing C5.3A change derivation metadata gate"
}

if ($uartSource -notmatch 'C6\.0_TEXT_PROTOCOL_V1' -or
    $uartSource -notmatch 'C6\.0_COMMAND_FIELDS_V1' -or
    $uartSource -notmatch 'C6\.0_RESPONSE_FIELDS_V1' -or
    $uartSource -notmatch 'C6\.0_ERROR_FIELDS_V1' -or
    $uartSource -notmatch 'C6\.0_POLICY_LABELS_V1') {
    throw "SOURCE_AUDIT_FAIL: UART missing C6.0 versioned protocol labels"
}

if ($uartSource -notmatch 'C6\.1_TEXT_FRAME_V1' -or
    $uartSource -notmatch 'wallet_uart_crc32_ieee\s*\(' -or
    $uartSource -notmatch 'FRAME_CRC32=' -or
    $uartSource -notmatch 'FRAME_LEN=' -or
    $uartSource -notmatch 'ERR_FRAME_CRC=-72') {
    throw "SOURCE_AUDIT_FAIL: UART missing C6.1 framed text protocol hooks"
}

if ($masterRegressionSource -notmatch 'wallet_c6_0_c6_1_protocol_regression\.ps1') {
    throw "SOURCE_AUDIT_FAIL: master regression does not run C6.0/C6.1 protocol regression"
}

if ($uartSource -notmatch 'REAL_BITCOIN_SIGNING_ENABLED=1' -or
    $uartSource -notmatch 'TESTNET_SIGNING_ENABLED=1' -or
    $uartSource -notmatch 'MAINNET_SIGNING_ENABLED=0' -or
    $uartSource -notmatch 'NETWORK_ALLOWED=REGTEST,TESTNET') {
    throw "SOURCE_AUDIT_FAIL: UART missing C7.0 real-network safety labels"
}

if ($c70RealNetworkRegressionSource -notmatch 'C7_0_REAL_NETWORK_SAFETY_REGRESSION_PASS' -or
    $c70RealNetworkRegressionSource -notmatch 'C7_0_DEVICE_TESTNET_CHECK_REJECT_PASS' -or
    $c70RealNetworkRegressionSource -notmatch 'C7_0_MAINNET_HOST_NO_SIGN_PASS' -or
    $c70RealNetworkRegressionSource -notmatch 'AUTH_UNCHANGED') {
    throw "SOURCE_AUDIT_FAIL: C7.0 real-network safety regression is missing required assertions"
}

if ($masterRegressionSource -notmatch 'wallet_c7_0_real_network_safety_regression\.ps1') {
    throw "SOURCE_AUDIT_FAIL: master regression does not run C7.0 real-network safety regression"
}

if ($uartSource -notmatch 'OK REALINFO' -or
    $uartSource -notmatch 'REAL_BITCOIN_READINESS=TESTNET_ONLY_ACTIVE_MAINNET_LOCKED' -or
    $uartSource -notmatch 'HOST_REAL_NETWORK_OVERRIDE_SUPPORTED=0' -or
    $uartSource -notmatch 'TESTNET_SIGNING_ACTIVATION_REQUIRES_FIRMWARE_CHANGE=0' -or
    $uartSource -notmatch 'MAINNET_SIGNING_ACTIVATION_REQUIRES_FIRMWARE_CHANGE=1' -or
    $uartSource -notmatch 'BLOCKER_TROPIC_SECP256K1=1') {
    throw "SOURCE_AUDIT_FAIL: UART missing C8.0 real-Bitcoin readiness manifest"
}

if ($c80ReadinessRegressionSource -notmatch 'C8_0_REAL_BITCOIN_READINESS_REGRESSION_PASS' -or
    $c80ReadinessRegressionSource -notmatch 'C8_0_REALINFO_MANIFEST_PASS' -or
    $c80ReadinessRegressionSource -notmatch 'C8_0_REAL_NETWORK_STILL_REJECTS_PASS' -or
    $c80ReadinessRegressionSource -notmatch 'AUTH_UNCHANGED') {
    throw "SOURCE_AUDIT_FAIL: C8.0 real-Bitcoin readiness regression is missing required assertions"
}

if ($masterRegressionSource -notmatch 'wallet_c8_0_real_bitcoin_readiness_regression\.ps1') {
    throw "SOURCE_AUDIT_FAIL: master regression does not run C8.0 real-Bitcoin readiness regression"
}

if ($uartSource -notmatch 'TESTNET_WATCH_ONLY_DRY_RUN_SUPPORTED=1' -or
    $uartSource -notmatch 'TESTNET_DRY_RUN_SIGNING_ENABLED=0' -or
    $uartSource -notmatch 'TESTNET_DRY_RUN_DEVICE_SIGNATURE=0' -or
    $uartSource -notmatch 'TESTNET_DRY_RUN_BROADCAST=0' -or
    $uartSource -notmatch 'BLOCKER_TESTNET_REGRESSION=0') {
    throw "SOURCE_AUDIT_FAIL: UART missing C8.1 testnet watch-only dry-run manifest"
}

if ($c81TestnetDryRunRegressionSource -notmatch 'C8_1_TESTNET_WATCH_ONLY_DRY_RUN_REGRESSION_PASS' -or
    $c81TestnetDryRunRegressionSource -notmatch 'C8_1_REALINFO_WATCH_ONLY_PASS' -or
    $c81TestnetDryRunRegressionSource -notmatch 'C8_1_HOST_TESTNET_NO_SIGN_PASS' -or
    $c81TestnetDryRunRegressionSource -notmatch 'TESTNET_DRY_RUN_BEGIN' -or
    $c81TestnetDryRunRegressionSource -notmatch 'DEVICE_SIGNATURE_ALLOWED=0' -or
    $c81TestnetDryRunRegressionSource -notmatch 'AUTH_UNCHANGED') {
    throw "SOURCE_AUDIT_FAIL: C8.1 testnet watch-only dry-run regression is missing required assertions"
}

if ($masterRegressionSource -notmatch 'wallet_c8_1_testnet_watch_only_dry_run_regression\.ps1') {
    throw "SOURCE_AUDIT_FAIL: master regression does not run C8.1 testnet watch-only dry-run regression"
}

if ($uartSource -notmatch 'C8\.2_TESTNET_POLICY_FIXTURES' -or
    $uartSource -notmatch 'TESTNET_POLICY_FIXTURES_SUPPORTED=1' -or
    $uartSource -notmatch 'TESTNET_POLICY_VERSION=C8\.2_TESTNET_POLICY_FIXTURES_V1' -or
    $uartSource -notmatch 'TESTNET_POLICY_SIGNING_ENABLED=0' -or
    $uartSource -notmatch 'TESTNET_POLICY_REQUIRES_USER_CONFIRMATION=1' -or
    $uartSource -notmatch 'TESTNET_POLICY_REQUIRES_TROPIC_AUTH_GATE=1') {
    throw "SOURCE_AUDIT_FAIL: UART missing C8.2 testnet policy fixture manifest"
}

if ($c82TestnetPolicyFixturesRegressionSource -notmatch 'C8_2_TESTNET_POLICY_FIXTURES_REGRESSION_PASS' -or
    $c82TestnetPolicyFixturesRegressionSource -notmatch 'C8_2_REALINFO_POLICY_FIXTURES_PASS' -or
    $c82TestnetPolicyFixturesRegressionSource -notmatch 'C8_2_HOST_TWO_INPUT_TESTNET_NO_SIGN_PASS' -or
    $c82TestnetPolicyFixturesRegressionSource -notmatch 'TESTNET_POLICY_FIXTURE_BEGIN' -or
    $c82TestnetPolicyFixturesRegressionSource -notmatch 'SIGNING_ENABLED=0' -or
    $c82TestnetPolicyFixturesRegressionSource -notmatch 'AUTH_UNCHANGED') {
    throw "SOURCE_AUDIT_FAIL: C8.2 testnet policy fixtures regression is missing required assertions"
}

if ($masterRegressionSource -notmatch 'wallet_c8_2_testnet_policy_fixtures_regression\.ps1') {
    throw "SOURCE_AUDIT_FAIL: master regression does not run C8.2 testnet policy fixtures regression"
}

if ($uartSource -notmatch 'C8\.3_TESTNET_ADDRESS_DERIVATION_DRY_RUN_V1' -or
    $uartSource -notmatch 'TESTNET_DERIVATION_DRY_RUN_SUPPORTED=1' -or
    $uartSource -notmatch 'TESTNET_DERIVATION_SIGNING_ENABLED=0' -or
    $uartSource -notmatch 'TESTNET_DERIVATION_DEVICE_SIGNATURE=0' -or
    $uartSource -notmatch 'TESTNET_XPUB_EXPORT_ENABLED=0') {
    throw "SOURCE_AUDIT_FAIL: UART missing C8.3 testnet address derivation dry-run manifest"
}

if ($c83AddressDerivationRegressionSource -notmatch 'C8_3_TESTNET_ADDRESS_DERIVATION_DRY_RUN_REGRESSION_PASS' -or
    $c83AddressDerivationRegressionSource -notmatch 'C8_3_REALINFO_DERIVATION_MANIFEST_PASS' -or
    $c83AddressDerivationRegressionSource -notmatch 'C8_3_HOST_TESTNET_DERIVATION_NO_SIGN_PASS' -or
    $c83AddressDerivationRegressionSource -notmatch 'TESTNET_DERIVATION_DRY_RUN_BEGIN' -or
    $c83AddressDerivationRegressionSource -notmatch 'ADDRESS_SIGNATURE_ALLOWED=0' -or
    $c83AddressDerivationRegressionSource -notmatch 'AUTH_UNCHANGED') {
    throw "SOURCE_AUDIT_FAIL: C8.3 testnet address derivation dry-run regression is missing required assertions"
}

if ($masterRegressionSource -notmatch 'wallet_c8_3_testnet_address_derivation_dry_run_regression\.ps1') {
    throw "SOURCE_AUDIT_FAIL: master regression does not run C8.3 testnet address derivation dry-run regression"
}

if ($uartSource -notmatch 'C8\.4_TESTNET_FEE_CHANGE_POLICY_FIXTURES_V1' -or
    $uartSource -notmatch 'TESTNET_FEE_CHANGE_FIXTURES_SUPPORTED=1' -or
    $uartSource -notmatch 'TESTNET_FEE_CHANGE_SIGNING_ENABLED=0' -or
    $uartSource -notmatch 'TESTNET_CHANGE_OWNERSHIP_PROOF=DERIVATION_PATH_AND_SCRIPT_MATCH' -or
    $uartSource -notmatch 'TESTNET_FEE_MAX_SATS=20000') {
    throw "SOURCE_AUDIT_FAIL: UART missing C8.4 testnet fee/change policy fixture manifest"
}

if ($c84FeeChangeRegressionSource -notmatch 'C8_4_TESTNET_FEE_CHANGE_POLICY_FIXTURES_REGRESSION_PASS' -or
    $c84FeeChangeRegressionSource -notmatch 'C8_4_REALINFO_FEE_CHANGE_FIXTURES_PASS' -or
    $c84FeeChangeRegressionSource -notmatch 'C8_4_HOST_TESTNET_FEE_CHANGE_NO_SIGN_PASS' -or
    $c84FeeChangeRegressionSource -notmatch 'TESTNET_FEE_CHANGE_FIXTURE_BEGIN' -or
    $c84FeeChangeRegressionSource -notmatch 'SIGNING_ENABLED=0' -or
    $c84FeeChangeRegressionSource -notmatch 'AUTH_UNCHANGED') {
    throw "SOURCE_AUDIT_FAIL: C8.4 testnet fee/change policy fixtures regression is missing required assertions"
}

if ($masterRegressionSource -notmatch 'wallet_c8_4_testnet_fee_change_policy_fixtures_regression\.ps1') {
    throw "SOURCE_AUDIT_FAIL: master regression does not run C8.4 testnet fee/change policy fixtures regression"
}

if ($uartSource -notmatch 'C8\.5_TESTNET_UNSIGNED_TX_PSBT_DRY_RUN' -or
    $uartSource -notmatch 'TESTNET_UNSIGNED_TX_PSBT_DRY_RUN_SUPPORTED=1' -or
    $uartSource -notmatch 'TESTNET_UNSIGNED_TX_SIGNING_ENABLED=0' -or
    $uartSource -notmatch 'TESTNET_UNSIGNED_TX_DEVICE_SIGNATURE=0' -or
    $uartSource -notmatch 'TESTNET_UNSIGNED_TX_RAW_TX=0' -or
    $uartSource -notmatch 'TESTNET_UNSIGNED_TX_BROADCAST=0') {
    throw "SOURCE_AUDIT_FAIL: UART missing C8.5 testnet unsigned tx/PSBT dry-run manifest"
}

if ($c85UnsignedTxRegressionSource -notmatch 'C8_5_TESTNET_UNSIGNED_TX_PSBT_DRY_RUN_REGRESSION_PASS' -or
    $c85UnsignedTxRegressionSource -notmatch 'C8_5_REALINFO_UNSIGNED_TX_PSBT_PASS' -or
    $c85UnsignedTxRegressionSource -notmatch 'C8_5_HOST_TESTNET_UNSIGNED_TX_NO_SIGN_PASS' -or
    $c85UnsignedTxRegressionSource -notmatch 'TESTNET_UNSIGNED_TX_PSBT_DRY_RUN_BEGIN' -or
    $c85UnsignedTxRegressionSource -notmatch 'DEVICE_SIGNATURE_ALLOWED=0' -or
    $c85UnsignedTxRegressionSource -notmatch 'AUTH_UNCHANGED') {
    throw "SOURCE_AUDIT_FAIL: C8.5 testnet unsigned tx/PSBT dry-run regression is missing required assertions"
}

if ($masterRegressionSource -notmatch 'wallet_c8_5_testnet_unsigned_tx_psbt_dry_run_regression\.ps1') {
    throw "SOURCE_AUDIT_FAIL: master regression does not run C8.5 testnet unsigned tx/PSBT dry-run regression"
}

if ($uartSource -notmatch 'C8\.6_TESTNET_ACTIVATION_CHECKLIST' -or
    $uartSource -notmatch 'TESTNET_ACTIVATION_CHECKLIST_SUPPORTED=1' -or
    $uartSource -notmatch 'TESTNET_ACTIVATION_SIGNING_ENABLED=0' -or
    $uartSource -notmatch 'TESTNET_ACTIVATION_READY=0' -or
    $uartSource -notmatch 'TESTNET_ACTIVATION_REQUIRES_COMPILE_TIME_FLAG=1' -or
    $uartSource -notmatch 'TESTNET_ACTIVATION_FLAG_STATE=0' -or
    $uartSource -notmatch 'TESTNET_CHECKLIST_ITEM_TESTNET_SIGNING_FLAG=BLOCKED') {
    throw "SOURCE_AUDIT_FAIL: UART missing C8.6 testnet activation checklist manifest"
}

if ($c86ActivationChecklistRegressionSource -notmatch 'C8_6_TESTNET_ACTIVATION_CHECKLIST_REGRESSION_PASS' -or
    $c86ActivationChecklistRegressionSource -notmatch 'C8_6_REALINFO_ACTIVATION_CHECKLIST_PASS' -or
    $c86ActivationChecklistRegressionSource -notmatch 'C8_6_HOST_TESTNET_ACTIVATION_NO_SIGN_PASS' -or
    $c86ActivationChecklistRegressionSource -notmatch 'TESTNET_ACTIVATION_CHECKLIST_BEGIN' -or
    $c86ActivationChecklistRegressionSource -notmatch 'TESTNET_ACTIVATION_READY=0' -or
    $c86ActivationChecklistRegressionSource -notmatch 'AUTH_UNCHANGED') {
    throw "SOURCE_AUDIT_FAIL: C8.6 testnet activation checklist regression is missing required assertions"
}

if ($masterRegressionSource -notmatch 'wallet_c8_6_testnet_activation_checklist_regression\.ps1') {
    throw "SOURCE_AUDIT_FAIL: master regression does not run C8.6 testnet activation checklist regression"
}

if ($uartSource -notmatch 'C8\.7_TESTNET_DRY_RUN_ARTIFACT_EXPORT_V1' -or
    $uartSource -notmatch 'TESTNET_ARTIFACT_EXPORT_SUPPORTED=1' -or
    $uartSource -notmatch 'TESTNET_ARTIFACT_SIGNING_ENABLED=0' -or
    $uartSource -notmatch 'TESTNET_ARTIFACT_DEVICE_SIGNATURE=0' -or
    $uartSource -notmatch 'TESTNET_ARTIFACT_RAW_TX=0' -or
    $uartSource -notmatch 'TESTNET_ARTIFACT_BROADCAST=0') {
    throw "SOURCE_AUDIT_FAIL: UART missing C8.7 testnet dry-run artifact export manifest"
}

if ($c87ArtifactExportRegressionSource -notmatch 'C8_7_TESTNET_DRY_RUN_ARTIFACT_EXPORT_REGRESSION_PASS' -or
    $c87ArtifactExportRegressionSource -notmatch 'C8_7_REALINFO_ARTIFACT_EXPORT_PASS' -or
    $c87ArtifactExportRegressionSource -notmatch 'C8_7_HOST_TESTNET_ARTIFACT_FILE_PASS' -or
    $c87ArtifactExportRegressionSource -notmatch 'C8_7_HOST_TESTNET_ARTIFACT_NO_SIGN_PASS' -or
    $c87ArtifactExportRegressionSource -notmatch 'DEVICE_SIGNATURE=0' -or
    $c87ArtifactExportRegressionSource -notmatch 'AUTH_UNCHANGED') {
    throw "SOURCE_AUDIT_FAIL: C8.7 testnet dry-run artifact export regression is missing required assertions"
}

if ($masterRegressionSource -notmatch 'wallet_c8_7_testnet_dry_run_artifact_export_regression\.ps1') {
    throw "SOURCE_AUDIT_FAIL: master regression does not run C8.7 testnet dry-run artifact export regression"
}

if ($uartSource -notmatch 'C8\.8_TESTNET_DERIVATION_MODEL_DECISION_V1' -or
    $uartSource -notmatch 'TESTNET_DERIVATION_DECISION_SUPPORTED=1' -or
    $uartSource -notmatch 'TESTNET_DERIVATION_DECISION_SIGNING_ENABLED=0' -or
    $uartSource -notmatch 'TESTNET_DERIVATION_DECISION_MODEL=BIP84_TESTNET_P2WPKH_ACCOUNT' -or
    $uartSource -notmatch 'TESTNET_DERIVATION_DECISION_DEVICE_DERIVES_KEYS=0' -or
    $uartSource -notmatch 'TESTNET_DERIVATION_DECISION_ACTIVATION_BLOCKED=1') {
    throw "SOURCE_AUDIT_FAIL: UART missing C8.8 testnet derivation model decision manifest"
}

if ($c88DerivationDecisionRegressionSource -notmatch 'C8_8_TESTNET_DERIVATION_MODEL_DECISION_REGRESSION_PASS' -or
    $c88DerivationDecisionRegressionSource -notmatch 'C8_8_REALINFO_DERIVATION_DECISION_PASS' -or
    $c88DerivationDecisionRegressionSource -notmatch 'C8_8_HOST_DERIVATION_DECISION_TRANSCRIPT_PASS' -or
    $c88DerivationDecisionRegressionSource -notmatch 'DEVICE_DERIVES_KEYS=0' -or
    $c88DerivationDecisionRegressionSource -notmatch 'SIGNING_ENABLED=0' -or
    $c88DerivationDecisionRegressionSource -notmatch 'AUTH_UNCHANGED') {
    throw "SOURCE_AUDIT_FAIL: C8.8 testnet derivation model decision regression is missing required assertions"
}

if ($masterRegressionSource -notmatch 'wallet_c8_8_testnet_derivation_model_decision_regression\.ps1') {
    throw "SOURCE_AUDIT_FAIL: master regression does not run C8.8 testnet derivation model decision regression"
}

if ($uartSource -notmatch 'C8\.9_TESTNET_SIGNING_COMPILE_TIME_GUARD' -or
    $uartSource -notmatch 'WALLET_TESTNET_SIGNING_BUILD_FLAG 0' -or
    $uartSource -notmatch 'WALLET_MAINNET_SIGNING_BUILD_FLAG 0' -or
    $uartSource -notmatch 'TESTNET_SIGNING_COMPILE_TIME_GUARD_SUPPORTED=1' -or
    $uartSource -notmatch 'TESTNET_SIGNING_BUILD_FLAG=0' -or
    $uartSource -notmatch 'TESTNET_SIGNING_RUNTIME_OVERRIDE_SUPPORTED=0' -or
    $uartSource -notmatch 'MAINNET_SIGNING_BUILD_FLAG=0') {
    throw "SOURCE_AUDIT_FAIL: UART missing C8.9 testnet signing compile-time guard manifest"
}

if ($c89CompileTimeGuardRegressionSource -notmatch 'C8_9_TESTNET_SIGNING_COMPILE_TIME_GUARD_REGRESSION_PASS' -or
    $c89CompileTimeGuardRegressionSource -notmatch 'C8_9_REALINFO_COMPILE_TIME_GUARD_PASS' -or
    $c89CompileTimeGuardRegressionSource -notmatch 'C8_9_HOST_TESTNET_GUARD_NO_SIGN_PASS' -or
    $c89CompileTimeGuardRegressionSource -notmatch 'TESTNET_SIGNING_BUILD_FLAG=0' -or
    $c89CompileTimeGuardRegressionSource -notmatch 'MAINNET_SIGNING_BUILD_FLAG=0' -or
    $c89CompileTimeGuardRegressionSource -notmatch 'AUTH_UNCHANGED') {
    throw "SOURCE_AUDIT_FAIL: C8.9 testnet signing compile-time guard regression is missing required assertions"
}

if ($masterRegressionSource -notmatch 'wallet_c8_9_testnet_signing_compile_time_guard_regression\.ps1') {
    throw "SOURCE_AUDIT_FAIL: master regression does not run C8.9 testnet signing compile-time guard regression"
}

if ($uartSource -notmatch 'C9\.0_TESTNET_SIGNING_MODE_DESIGN' -or
    $uartSource -notmatch 'TESTNET_SIGNING_MODE_DESIGN_SUPPORTED=1' -or
    $uartSource -notmatch 'TESTNET_SIGNING_MODE_VERSION=C9\.0_TESTNET_SIGNING_MODE_DESIGN_V1' -or
    $uartSource -notmatch 'TESTNET_SIGNING_MODE=ACTIVE_TESTNET_ONLY' -or
    $uartSource -notmatch 'TESTNET_SIGNING_MODE_SIGNING_ENABLED=1' -or
    $uartSource -notmatch 'TESTNET_SIGNING_MODE_BUILD_FLAG_STATE=1' -or
    $uartSource -notmatch 'TESTNET_SIGNING_MODE_REQUIRES_PHYSICAL_CONFIRM=1' -or
    $uartSource -notmatch 'TESTNET_SIGNING_MODE_MAINNET_LOCKOUT=1' -or
    $uartSource -notmatch 'TESTNET_SIGNING_MODE_RUNTIME_OVERRIDE_SUPPORTED=0') {
    throw "SOURCE_AUDIT_FAIL: UART missing C9.0 testnet signing mode design manifest"
}

if ($c90SigningModeDesignRegressionSource -notmatch 'C9_0_TESTNET_SIGNING_MODE_DESIGN_REGRESSION_PASS' -or
    $c90SigningModeDesignRegressionSource -notmatch 'C9_0_REALINFO_SIGNING_MODE_DESIGN_PASS' -or
    $c90SigningModeDesignRegressionSource -notmatch 'C9_0_HOST_TESTNET_SIGNING_MODE_NO_SIGN_PASS' -or
    $c90SigningModeDesignRegressionSource -notmatch 'TESTNET_SIGNING_MODE_SIGNING_ENABLED=0' -or
    $c90SigningModeDesignRegressionSource -notmatch 'TESTNET_SIGNING_MODE_REQUIRES_PHYSICAL_CONFIRM=1' -or
    $c90SigningModeDesignRegressionSource -notmatch 'TESTNET_SIGNING_MODE_MAINNET_LOCKOUT=1' -or
    $c90SigningModeDesignRegressionSource -notmatch 'AUTH_UNCHANGED') {
    throw "SOURCE_AUDIT_FAIL: C9.0 testnet signing mode design regression is missing required assertions"
}

if ($masterRegressionSource -notmatch 'wallet_c9_0_testnet_signing_mode_design_regression\.ps1') {
    throw "SOURCE_AUDIT_FAIL: master regression does not run C9.0 testnet signing mode design regression"
}

if ($uartSource -notmatch 'C9\.8_TESTNET_CHANGE_DERIVATION_ENFORCEMENT' -or
    $uartSource -notmatch 'TESTNET_DERIVATION_IMPLEMENTATION_FOUNDATION_SUPPORTED=1' -or
    $uartSource -notmatch 'TESTNET_DERIVATION_IMPLEMENTATION_VERSION=C9\.1_TESTNET_DERIVATION_IMPLEMENTATION_FOUNDATION_V1' -or
    $uartSource -notmatch 'TESTNET_DERIVATION_IMPLEMENTATION_MODEL=BIP84_TESTNET_P2WPKH_ACCOUNT' -or
    $uartSource -notmatch 'TESTNET_DERIVATION_IMPLEMENTATION_DEVICE_DERIVES_KEYS=0' -or
    $uartSource -notmatch 'TESTNET_CHANGE_DERIVATION_ENFORCEMENT_VERSION=C9\.8_TESTNET_CHANGE_DERIVATION_ENFORCEMENT_V1' -or
    $uartSource -notmatch 'TESTNET_CHANGE_DERIVATION_ENFORCEMENT_PATH=' -or
    $uartSource -notmatch 'm/84h/1h/0h/1/0' -or
    $uartSource -notmatch 'TESTNET_REAL_FEE_POLICY_VERSION=C9\.3_TESTNET_REAL_FEE_POLICY_V1' -or
    $uartSource -notmatch 'TESTNET_REAL_FEE_POLICY_MAX_SATS_PER_KVB=100000' -or
    $uartSource -notmatch 'TESTNET_UNSIGNED_TX_VALIDATION_VERSION=C9\.4_TESTNET_UNSIGNED_TX_VALIDATION_V1' -or
    $uartSource -notmatch 'TESTNET_UNSIGNED_TX_VALIDATION_FORMAT=PSBT_LIKE_TEXT_V1' -or
    $uartSource -notmatch 'TESTNET_SIGNING_ACTIVATION_DRY_RUN_VERSION=C9\.5_GUARDED_TESTNET_SIGNING_ACTIVATION_DRY_RUN_V1' -or
    $uartSource -notmatch 'TESTNET_SIGNING_ACTIVATION_DRY_RUN_STATUS=SUPERSEDED_BY_C9\.6_ACTIVE_TESTNET_ONLY' -or
    $uartSource -notmatch 'TESTNET_SIGNING_ENABLE_VERSION=C9\.6_TESTNET_SIGNING_ENABLE_ON_TEST_FUNDS_ONLY_V1' -or
    $uartSource -notmatch 'TESTNET_SIGNING_ENABLE_ACTUAL_SIGNING_ENABLED=1' -or
    $uartSource -notmatch 'TESTNET_SIGNING_ENABLE_BROADCAST=0' -or
    $uartSource -notmatch 'TESTNET_SIGNING_ENABLE_BIP84_DEVICE_DERIVATION=0') {
    throw "SOURCE_AUDIT_FAIL: UART missing C9.1-C9.6 testnet signing activation manifest"
}

if ($c91ToC95PreActivationRegressionSource -notmatch 'C9_1_TO_C9_5_TESTNET_PRE_ACTIVATION_REGRESSION_PASS' -or
    $c91ToC95PreActivationRegressionSource -notmatch 'C9_1_REALINFO_DERIVATION_IMPLEMENTATION_FOUNDATION_PASS' -or
    $c91ToC95PreActivationRegressionSource -notmatch 'C9_2_REALINFO_CHANGE_DERIVATION_ENFORCEMENT_PASS' -or
    $c91ToC95PreActivationRegressionSource -notmatch 'C9_3_REALINFO_REAL_FEE_POLICY_PASS' -or
    $c91ToC95PreActivationRegressionSource -notmatch 'C9_4_REALINFO_UNSIGNED_TX_VALIDATION_PASS' -or
    $c91ToC95PreActivationRegressionSource -notmatch 'C9_5_REALINFO_SIGNING_ACTIVATION_DRY_RUN_PASS' -or
    $c91ToC95PreActivationRegressionSource -notmatch 'C9_6_TESTNET_SIGNING_ENABLE_BLOCKED_PASS' -or
    $c91ToC95PreActivationRegressionSource -notmatch 'C9_1_TO_C9_5_HOST_TESTNET_NO_SIGN_PASS' -or
    $c91ToC95PreActivationRegressionSource -notmatch 'AUTH_UNCHANGED') {
    throw "SOURCE_AUDIT_FAIL: C9.1-C9.5 testnet pre-activation regression is missing required assertions"
}

if ($masterRegressionSource -notmatch 'wallet_c9_1_to_c9_5_testnet_pre_activation_regression\.ps1') {
    throw "SOURCE_AUDIT_FAIL: master regression does not run C9.1-C9.5 testnet pre-activation regression"
}

if ($c96TestnetSigningEnableRegressionSource -notmatch 'C9_6_TESTNET_SIGNING_ENABLE_REGRESSION_PASS' -or
    $c96TestnetSigningEnableRegressionSource -notmatch 'C9_6_REALINFO_TESTNET_SIGNING_ENABLE_PASS' -or
    $c96TestnetSigningEnableRegressionSource -notmatch 'C9_6_VERSION_POLICY_LABELS_PASS' -or
    $c96TestnetSigningEnableRegressionSource -notmatch 'C9_6_HOST_TESTNET_SIGNING_RAW_TX_PASS' -or
    $c96TestnetSigningEnableRegressionSource -notmatch 'C9_6_HOST_MAINNET_NO_SIGN_PASS' -or
    $c96TestnetSigningEnableRegressionSource -notmatch 'AUTH_INCREMENTED_ONCE' -or
    $c96TestnetSigningEnableRegressionSource -notmatch 'AUTH_UNCHANGED') {
    throw "SOURCE_AUDIT_FAIL: C9.6 testnet signing enable regression is missing required assertions"
}

if ($masterRegressionSource -notmatch 'wallet_c9_6_testnet_signing_enable_regression\.ps1') {
    throw "SOURCE_AUDIT_FAIL: master regression does not run C9.6 testnet signing enable regression"
}

if ($uartSource -notmatch 'WALLET_C9_7_BIP84_IDENTITY_VERSION' -or
    $uartSource -notmatch 'C9\.7_TESTNET_BIP84_IDENTITY_V1' -or
    $uartSource -notmatch 'TESTNET_BIP84_ADDRESS=' -or
    $uartSource -notmatch 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx' -or
    $uartSource -notmatch '0014751e76e8199196d454941c45d1b3a323f1433bd6' -or
    $uartSource -notmatch 'TESTNET_BIP84_DEVICE_DERIVES_KEYS=0' -or
    $uartSource -notmatch 'TESTNET_BIP84_SIGNING_ENABLED=0' -or
    $commandSource -notmatch 'WALLET_COMMAND_C9_8_TESTNET_CHANGE_DERIVATION' -or
    $commandSource -notmatch 'wallet_command_check_change_script_for_network') {
    throw "SOURCE_AUDIT_FAIL: firmware missing C9.7/C9.8 BIP84 change enforcement hooks"
}

if ($c97C98Bip84ChangeRegressionSource -notmatch 'C9_7_C9_8_TESTNET_BIP84_CHANGE_REGRESSION_PASS' -or
    $c97C98Bip84ChangeRegressionSource -notmatch 'C9_7_TESTNET_BIP84_IDENTITY_PASS' -or
    $c97C98Bip84ChangeRegressionSource -notmatch 'C9_8_TESTNET_BIP84_CHANGE_SIGNING_PASS' -or
    $c97C98Bip84ChangeRegressionSource -notmatch 'C9_8_TESTNET_WRONG_CHANGE_DERIVATION_REJECT_PASS' -or
    $c97C98Bip84ChangeRegressionSource -notmatch 'C9_8_TESTNET_WRONG_CHANGE_SCRIPT_REJECT_PASS' -or
    $c97C98Bip84ChangeRegressionSource -notmatch 'AUTH_INCREMENTED_ONCE' -or
    $c97C98Bip84ChangeRegressionSource -notmatch 'AUTH_UNCHANGED') {
    throw "SOURCE_AUDIT_FAIL: C9.7/C9.8 testnet BIP84 change regression is missing required assertions"
}

if ($masterRegressionSource -notmatch 'wallet_c9_7_c9_8_testnet_bip84_change_regression\.ps1') {
    throw "SOURCE_AUDIT_FAIL: master regression does not run C9.7/C9.8 testnet BIP84 change regression"
}

if ($hardwareCiSource -notmatch 'stm32cubeidec\.exe' -or
    $hardwareCiSource -notmatch 'STM32_Programmer_CLI\.exe' -or
    $hardwareCiSource -notmatch 'wallet_c6_0_c6_1_protocol_regression\.ps1' -or
    $hardwareCiSource -notmatch 'wallet_run_all_regressions\.ps1' -or
    $hardwareCiSource -notmatch 'WALLET_HARDWARE_CI_PASS') {
    throw "SOURCE_AUDIT_FAIL: C6.2 hardware CI harness is missing required build/flash/regression hooks"
}

Write-Host "No dangerous plaintext/dev-key remnants found."
Write-Host "C4_0_LEGACY_SIGN_DISABLED_SOURCE_AUDIT_PASS"
Write-Host "C4_1_SECRET_ZEROIZATION_SOURCE_AUDIT_PASS"
Write-Host "C4_2_PIN_SESSION_SOURCE_AUDIT_PASS"
Write-Host "C4_3_TROPIC_AUTH_POLICY_SOURCE_AUDIT_PASS"
Write-Host "C3_3_PHYSICAL_BUTTON_CONFIRM_SOURCE_AUDIT_PASS"
Write-Host "C3_6_PHYSICAL_BUTTON_FRESH_PRESS_SOURCE_AUDIT_PASS"
Write-Host "C5_0_PSBT_LIKE_FORMAT_SOURCE_AUDIT_PASS"
Write-Host "C5_1_TWO_INPUT_SOURCE_AUDIT_PASS"
Write-Host "C5_3_CHANGE_DERIVATION_METADATA_SOURCE_AUDIT_PASS"
Write-Host "C6_0_VERSIONED_PROTOCOL_SOURCE_AUDIT_PASS"
Write-Host "C6_1_FRAMED_TEXT_SOURCE_AUDIT_PASS"
Write-Host "C6_2_HARDWARE_CI_SOURCE_AUDIT_PASS"
Write-Host "C7_0_REAL_NETWORK_SAFETY_SOURCE_AUDIT_PASS"
Write-Host "C8_0_REAL_BITCOIN_READINESS_SOURCE_AUDIT_PASS"
Write-Host "C8_1_TESTNET_WATCH_ONLY_DRY_RUN_SOURCE_AUDIT_PASS"
Write-Host "C8_2_TESTNET_POLICY_FIXTURES_SOURCE_AUDIT_PASS"
Write-Host "C8_3_TESTNET_ADDRESS_DERIVATION_DRY_RUN_SOURCE_AUDIT_PASS"
Write-Host "C8_4_TESTNET_FEE_CHANGE_POLICY_FIXTURES_SOURCE_AUDIT_PASS"
Write-Host "C8_5_TESTNET_UNSIGNED_TX_PSBT_DRY_RUN_SOURCE_AUDIT_PASS"
Write-Host "C8_6_TESTNET_ACTIVATION_CHECKLIST_SOURCE_AUDIT_PASS"
Write-Host "C8_7_TESTNET_DRY_RUN_ARTIFACT_EXPORT_SOURCE_AUDIT_PASS"
Write-Host "C8_8_TESTNET_DERIVATION_MODEL_DECISION_SOURCE_AUDIT_PASS"
Write-Host "C8_9_TESTNET_SIGNING_COMPILE_TIME_GUARD_SOURCE_AUDIT_PASS"
Write-Host "C9_0_TESTNET_SIGNING_MODE_DESIGN_SOURCE_AUDIT_PASS"
Write-Host "C9_1_TO_C9_5_TESTNET_PRE_ACTIVATION_SOURCE_AUDIT_PASS"
Write-Host "C9_6_TESTNET_SIGNING_ENABLE_SOURCE_AUDIT_PASS"
Write-Host "C9_7_C9_8_TESTNET_BIP84_CHANGE_SOURCE_AUDIT_PASS"
Write-Host ""
Write-Host "SOURCE_AUDIT_PASS"
