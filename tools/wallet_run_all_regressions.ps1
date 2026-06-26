param(
    [string]$Port = "COM3",
    [string]$BitcoinCli = "C:\Program Files\Bitcoin\daemon\bitcoin-cli.exe",
    [string]$Wallet = "stm32-host-live"
)

$ErrorActionPreference = "Stop"

function Invoke-Step {
    param(
        [string]$Name,
        [string]$ScriptPath,
        [string[]]$ArgsList = @()
    )

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "RUN $Name"
    Write-Host "============================================================"

    if (-not (Test-Path $ScriptPath)) {
        throw "$Name script not found: $ScriptPath"
    }

    & powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $ScriptPath `
        @ArgsList

    $code = $LASTEXITCODE

    if ($code -ne 0) {
        throw "$Name failed with exit code $code"
    }

    Write-Host ""
    Write-Host "PASS $Name"
}

Write-Host ""
Write-Host "MASTER_REGRESSION_START"
Write-Host "PORT=$Port"
Write-Host "BITCOIN_CLI=$BitcoinCli"
Write-Host "WALLET=$Wallet"

Invoke-Step `
    -Name "UART_PROBE" `
    -ScriptPath ".\tools\wallet_probe_info.ps1" `
    -ArgsList @("-Port", $Port)


Invoke-Step `
    -Name "IDENTITY_PROBE" `
    -ScriptPath ".\tools\wallet_probe_identity.ps1" `
    -ArgsList @("-Port", $Port)
Invoke-Step `
    -Name "HOST_SYNC" `
    -ScriptPath ".\tools\wallet_host_sync_regression.ps1" `
    -ArgsList @("-Port", $Port)



Invoke-Step `
    -Name "DEVICE_CHECK_SUMMARY" `
    -ScriptPath ".\tools\wallet_device_check_summary_regression.ps1" `
    -ArgsList @("-Port", $Port)

Invoke-Step `
    -Name "C3_0_FIRMWARE_CHECK_BEFORE_SIGN" `
    -ScriptPath ".\tools\wallet_c3_0_firmware_check_before_sign_regression.ps1" `
    -ArgsList @("-Port", $Port)

Invoke-Step `
    -Name "C3_1_CHECK_ID_COMMITMENT" `
    -ScriptPath ".\tools\wallet_c3_1_check_id_commitment_regression.ps1" `
    -ArgsList @("-Port", $Port)

Invoke-Step `
    -Name "C3_2_UART_CONFIRM_GATE" `
    -ScriptPath ".\tools\wallet_c3_2_uart_confirm_gate_regression.ps1" `
    -ArgsList @("-Port", $Port)

Invoke-Step `
    -Name "C3_4_APPROVAL_TIMEOUT" `
    -ScriptPath ".\tools\wallet_c3_4_approval_timeout_regression.ps1" `
    -ArgsList @("-Port", $Port)

Invoke-Step `
    -Name "C3_5_CONFIRM_CODE" `
    -ScriptPath ".\tools\wallet_c3_5_confirm_code_regression.ps1" `
    -ArgsList @("-Port", $Port)

Invoke-Step `
    -Name "SIGNING_TRANSCRIPT" `
    -ScriptPath ".\tools\wallet_signing_transcript_regression.ps1" `
    -ArgsList @("-Port", $Port)

Invoke-Step `
    -Name "C2_7_TRANSCRIPT_CHECK_SIGN_CONSISTENCY" `
    -ScriptPath ".\tools\wallet_c2_7_transcript_check_sign_consistency_regression.ps1" `
    -ArgsList @("-Port", $Port)

Invoke-Step `
    -Name "C2_8_NEGATIVE_HOST_BINDING" `
    -ScriptPath ".\tools\wallet_c2_8_negative_host_binding_regression.ps1" `
    -ArgsList @("-Port", $Port)

Invoke-Step `
    -Name "POSITIVE_FULL_LOOP" `
    -ScriptPath ".\tools\wallet_regtest_full_loop.ps1" `
    -ArgsList @("-Port", $Port, "-BitcoinCli", $BitcoinCli, "-Wallet", $Wallet)

Invoke-Step `
    -Name "NEGATIVE_POLICY" `
    -ScriptPath ".\tools\wallet_regtest_live_negative_policy.ps1" `
    -ArgsList @("-Port", $Port, "-BitcoinCli", $BitcoinCli, "-Wallet", $Wallet)

Invoke-Step `
    -Name "C4_0_LEGACY_SIGN_DISABLED" `
    -ScriptPath ".\tools\wallet_c4_0_legacy_sign_disabled_regression.ps1" `
    -ArgsList @("-Port", $Port)

Invoke-Step `
    -Name "C4_1_SECRET_ZEROIZATION_AUDIT" `
    -ScriptPath ".\tools\wallet_c4_1_secret_zeroization_audit.ps1"

Invoke-Step `
    -Name "C4_2_PIN_SESSION" `
    -ScriptPath ".\tools\wallet_c4_2_pin_session_regression.ps1" `
    -ArgsList @("-Port", $Port)

Invoke-Step `
    -Name "C4_3_TROPIC_AUTH_POLICY" `
    -ScriptPath ".\tools\wallet_c4_3_tropic_auth_policy_regression.ps1" `
    -ArgsList @("-Port", $Port)

Invoke-Step `
    -Name "C5_0_PSBT_LIKE_FORMAT" `
    -ScriptPath ".\tools\wallet_c5_0_psbt_like_format_regression.ps1" `
    -ArgsList @("-Port", $Port)

Invoke-Step `
    -Name "C6_0_C6_1_PROTOCOL" `
    -ScriptPath ".\tools\wallet_c6_0_c6_1_protocol_regression.ps1" `
    -ArgsList @("-Port", $Port)

Invoke-Step `
    -Name "C7_0_REAL_NETWORK_SAFETY" `
    -ScriptPath ".\tools\wallet_c7_0_real_network_safety_regression.ps1" `
    -ArgsList @("-Port", $Port)

Invoke-Step `
    -Name "C8_0_REAL_BITCOIN_READINESS" `
    -ScriptPath ".\tools\wallet_c8_0_real_bitcoin_readiness_regression.ps1" `
    -ArgsList @("-Port", $Port)

Invoke-Step `
    -Name "C8_1_TESTNET_WATCH_ONLY_DRY_RUN" `
    -ScriptPath ".\tools\wallet_c8_1_testnet_watch_only_dry_run_regression.ps1" `
    -ArgsList @("-Port", $Port)

Invoke-Step `
    -Name "C8_2_TESTNET_POLICY_FIXTURES" `
    -ScriptPath ".\tools\wallet_c8_2_testnet_policy_fixtures_regression.ps1" `
    -ArgsList @("-Port", $Port)

Invoke-Step `
    -Name "C8_3_TESTNET_ADDRESS_DERIVATION_DRY_RUN" `
    -ScriptPath ".\tools\wallet_c8_3_testnet_address_derivation_dry_run_regression.ps1" `
    -ArgsList @("-Port", $Port)

Invoke-Step `
    -Name "C8_4_TESTNET_FEE_CHANGE_POLICY_FIXTURES" `
    -ScriptPath ".\tools\wallet_c8_4_testnet_fee_change_policy_fixtures_regression.ps1" `
    -ArgsList @("-Port", $Port)

Invoke-Step `
    -Name "C8_5_TESTNET_UNSIGNED_TX_PSBT_DRY_RUN" `
    -ScriptPath ".\tools\wallet_c8_5_testnet_unsigned_tx_psbt_dry_run_regression.ps1" `
    -ArgsList @("-Port", $Port)

Invoke-Step `
    -Name "C8_6_TESTNET_ACTIVATION_CHECKLIST" `
    -ScriptPath ".\tools\wallet_c8_6_testnet_activation_checklist_regression.ps1" `
    -ArgsList @("-Port", $Port)

Invoke-Step `
    -Name "C8_7_TESTNET_DRY_RUN_ARTIFACT_EXPORT" `
    -ScriptPath ".\tools\wallet_c8_7_testnet_dry_run_artifact_export_regression.ps1" `
    -ArgsList @("-Port", $Port)

Invoke-Step `
    -Name "C8_8_TESTNET_DERIVATION_MODEL_DECISION" `
    -ScriptPath ".\tools\wallet_c8_8_testnet_derivation_model_decision_regression.ps1" `
    -ArgsList @("-Port", $Port)

Invoke-Step `
    -Name "C8_9_TESTNET_SIGNING_COMPILE_TIME_GUARD" `
    -ScriptPath ".\tools\wallet_c8_9_testnet_signing_compile_time_guard_regression.ps1" `
    -ArgsList @("-Port", $Port)

Invoke-Step `
    -Name "C9_0_TESTNET_SIGNING_MODE_DESIGN" `
    -ScriptPath ".\tools\wallet_c9_0_testnet_signing_mode_design_regression.ps1" `
    -ArgsList @("-Port", $Port)

Invoke-Step `
    -Name "C9_1_TO_C9_5_TESTNET_PRE_ACTIVATION" `
    -ScriptPath ".\tools\wallet_c9_1_to_c9_5_testnet_pre_activation_regression.ps1" `
    -ArgsList @("-Port", $Port)

Invoke-Step `
    -Name "C9_6_TESTNET_SIGNING_ENABLE" `
    -ScriptPath ".\tools\wallet_c9_6_testnet_signing_enable_regression.ps1" `
    -ArgsList @("-Port", $Port)

Invoke-Step `
    -Name "C9_7_C9_8_TESTNET_BIP84_CHANGE" `
    -ScriptPath ".\tools\wallet_c9_7_c9_8_testnet_bip84_change_regression.ps1" `
    -ArgsList @("-Port", $Port)

Invoke-Step `
    -Name "SOURCE_AUDIT" `
    -ScriptPath ".\tools\wallet_source_audit.ps1"

Invoke-Step `
    -Name "TRUTH_LABEL_ASSERTIONS" `
    -ScriptPath ".\tools\wallet_assert_truth_labels.ps1" `
    -ArgsList @("-Port", $Port)

Invoke-Step `
    -Name "UNLOCK_GATE" `
    -ScriptPath ".\tools\wallet_regtest_unlock_gate.ps1" `
    -ArgsList @("-Port", $Port)

Write-Host ""
Write-Host "ALL_REGRESSIONS_PASS"



