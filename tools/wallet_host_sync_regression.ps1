param(
    [string]$Port = "COM3",
    [string]$Generator = ".\tools\wallet_generate_tx_command.ps1"
)

$ErrorActionPreference = "Stop"

function Invoke-GeneratorPass {
    param(
        [string]$Name
    )

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "HOST_SYNC_TEST $Name"
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
        -TimeoutSeconds 180 `
        2>&1

    $code = $LASTEXITCODE

    $output | ForEach-Object { Write-Host $_ }

    if ($code -ne 0) {
        throw "$Name failed with generator exit code $code"
    }

    $joined = ($output | Out-String)

    if ($joined -notmatch "HOST_TX_GENERATOR_PASS") {
        throw "$Name did not report HOST_TX_GENERATOR_PASS"
    }

    if ($joined -notmatch "RAW_TX=[0-9a-fA-F]+") {
        throw "$Name did not include RAW_TX"
    }

    Write-Host ""
    Write-Host "PASS $Name"
}

Write-Host ""
Write-Host "============================================================"
Write-Host " STM32 HOST-SYNC REGRESSION"
Write-Host "============================================================"
Write-Host "Port: $Port"

Invoke-GeneratorPass -Name "FIRST_SIGN"
Invoke-GeneratorPass -Name "SECOND_SIGN_IMMEDIATE"

Write-Host ""
Write-Host "HOST_SYNC_REGRESSION_PASS"
$global:LASTEXITCODE = 0
