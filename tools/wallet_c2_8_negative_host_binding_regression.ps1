param(
    [string]$Port = "COM3",
    [string]$Generator = ".\tools\wallet_generate_tx_command.ps1"
)

$ErrorActionPreference = "Continue"

function Invoke-HostBindingTamperReject {
    param(
        [string]$Name,
        [string]$Field,
        [string]$TamperValue
    )

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "C2.8 HOST_BINDING_TAMPER_TEST $Name"
    Write-Host "FIELD $Field"
    Write-Host "============================================================"

    $output = & powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $Generator `
        -Port $Port `
        -TxidLe "09f6ce894fc3f8c5de72f787386039a54eeb2aded45b4087fc0992e40023a632" `
        -Vout 1 `
        -InputSats 100000 `
        -PaySats 60000 `
        -ChangeSats 30000 `
        -CheckBindingTamperField $Field `
        -CheckBindingTamperValue $TamperValue `
        -TimeoutSeconds 180 `
        2>&1

    $code = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    $text = ($output | Out-String)

    if ($code -eq 0) {
        throw "$Name failed: generator unexpectedly succeeded"
    }

    $required = @(
        "C2_8_HOST_CHECK_BINDING_TAMPER_BEGIN",
        "TAMPER_FIELD=$Field",
        "HOST_TX_GENERATOR_FAIL",
        "POLICY_DECISION=REJECTED_BY_HOST_CHECK_BINDING",
        "RAW_TX_PRESENT=0",
        "SIGN_SENT=0",
        "NO_SIGN_SENT"
    )

    foreach ($needle in $required) {
        if ($text -notmatch [regex]::Escape($needle)) {
            throw "$Name failed: missing $needle"
        }
    }

    if ($text -match "--- SEND SIGN COMMAND LINE BY LINE ---") {
        throw "$Name failed: SIGN send section was reached"
    }

    if ($text -match "(?m)^>> SIGN\r?$") {
        throw "$Name failed: SIGN command was sent"
    }

    if ($text -match "RAW_TX=[0-9a-fA-F]+") {
        throw "$Name failed: RAW_TX appeared"
    }

    Write-Host ""
    Write-Host "PASS $Name -> REJECTED_BY_HOST_CHECK_BINDING NO_SIGN_SENT"
    $global:LASTEXITCODE = 0
}

Write-Host ""
Write-Host "============================================================"
Write-Host " STM32 C2.8 NEGATIVE HOST-BINDING REGRESSION"
Write-Host "============================================================"
Write-Host "Port: $Port"

Invoke-HostBindingTamperReject -Name "PAY_SATS_MISMATCH" -Field "PAY_SATS" -TamperValue "60001"
Invoke-HostBindingTamperReject -Name "CHANGE_SATS_MISMATCH" -Field "CHANGE_SATS" -TamperValue "30001"
Invoke-HostBindingTamperReject -Name "INPUT_TXID_LE_MISMATCH" -Field "INPUT_TXID_LE" -TamperValue "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
Invoke-HostBindingTamperReject -Name "INPUT_VOUT_MISMATCH" -Field "INPUT_VOUT" -TamperValue "2"
Invoke-HostBindingTamperReject -Name "INPUT_SATS_MISMATCH" -Field "INPUT_SATS" -TamperValue "100001"
Invoke-HostBindingTamperReject -Name "FEE_SATS_MISMATCH" -Field "FEE_SATS" -TamperValue "10001"

Write-Host ""
Write-Host "C2_8_NEGATIVE_HOST_BINDING_REGRESSION_PASS"
$global:LASTEXITCODE = 0
