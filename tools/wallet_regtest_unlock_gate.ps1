param(
    [string]$Port = "COM3",
    [string]$Generator = ".\tools\wallet_generate_tx_command.ps1"
)

$ErrorActionPreference = "Continue"

function Invoke-WalletGeneratorExpectError {
    param(
        [string]$Name,
        [string]$ExpectedError,
        [string[]]$ExtraArgs
    )

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "TEST $Name"
    Write-Host "EXPECT $ExpectedError"
    Write-Host "============================================================"

    $args = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $Generator,
        "-Port", $Port,
        "-TxidLe", "09f6ce894fc3f8c5de72f787386039a54eeb2aded45b4087fc0992e40023a632",
        "-Vout", "1",
        "-InputSats", "100000",
        "-PaySats", "60000",
        "-ChangeSats", "30000"
    ) + $ExtraArgs

    $output = & powershell.exe @args 2>&1
    $code = $LASTEXITCODE
    $text = ($output | Out-String)

    Write-Host $text

    if ($text -notmatch [regex]::Escape($ExpectedError)) {
        throw "$Name failed. Expected $ExpectedError"
    }

    if ($code -eq 0) {
        throw "$Name failed. Generator unexpectedly exited 0"
    }

    # Clear stale native exit code from the expected generator failure.
    # The generator should fail for this test, but this regression test passed.
    $global:LASTEXITCODE = 0

    Write-Host ""
    Write-Host "PASS $Name -> $ExpectedError"
}

Write-Host ""
Write-Host "============================================================"
Write-Host " STM32 UNLOCK-GATE REGRESSION"
Write-Host "============================================================"
Write-Host "Port: $Port"

Invoke-WalletGeneratorExpectError `
    -Name "MISSING_PIN_SESSION_REJECTED" `
    -ExpectedError "ERR KEYPROVIDER -22" `
    -ExtraArgs @("-OmitUnlockPin")

Invoke-WalletGeneratorExpectError `
    -Name "WRONG_PIN_REJECTED" `
    -ExpectedError "ERR KEYPROVIDER -23" `
    -ExtraArgs @("-UnlockPin", "000000")

Write-Host ""
Write-Host "UNLOCK_GATE_REGRESSION_PASS"
$global:LASTEXITCODE = 0


