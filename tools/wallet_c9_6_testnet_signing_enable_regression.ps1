param(
    [string]$Port = "COM3",
    [int]$Baud = 115200,
    [int]$TimeoutSeconds = 45,
    [string]$Generator = ".\tools\wallet_generate_tx_command.ps1"
)

$ErrorActionPreference = "Stop"

function Read-Available { param([System.IO.Ports.SerialPort]$Serial) $s = ""; try { while ($Serial.BytesToRead -gt 0) { $s += $Serial.ReadExisting(); Start-Sleep -Milliseconds 20 } } catch {}; return $s }
function Drain-Stale { param([System.IO.Ports.SerialPort]$Serial) Start-Sleep -Milliseconds 250; $null = Read-Available -Serial $Serial; $Serial.DiscardInBuffer(); Start-Sleep -Milliseconds 100; $null = Read-Available -Serial $Serial; $Serial.DiscardInBuffer() }
function Send-CommandLines {
    param([System.IO.Ports.SerialPort]$Serial, [string[]]$Lines, [string]$RequiredPattern, [int]$TimeoutSeconds)
    Drain-Stale -Serial $Serial
    foreach ($line in $Lines) { Write-Host ">> $line"; $Serial.WriteLine($line); Start-Sleep -Milliseconds 100 }
    $buf = ""; $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) { $buf += Read-Available -Serial $Serial; if (($buf -match $RequiredPattern) -and ($buf -match "(?s)READY.*>\s*$")) { return $buf }; Start-Sleep -Milliseconds 50 }
    Write-Host ""; Write-Host "--- TIMEOUT BUFFER ---"; Write-Host $buf; throw "Timeout waiting for required response pattern: $RequiredPattern"
}
function Assert-Contains { param([string]$Text, [string]$Needle) if ($Text -notmatch [regex]::Escape($Needle)) { Write-Host ""; Write-Host "--- TEXT THAT FAILED ASSERTION ---"; Write-Host $Text; throw "Missing expected text: $Needle" } }
function Assert-NoRawTx { param([string]$Text, [string]$Name) if ($Text -match "RAW_TX=[0-9a-fA-F]+") { throw "$Name unexpectedly produced RAW_TX" } }
function Get-AuthCountFromText { param([string]$Text) $m = [regex]::Match($Text, "(?m)^AUTH_COUNT=(\d+)\s*$"); if (-not $m.Success) { Write-Host $Text; throw "AUTH_COUNT missing" }; return [uint32]$m.Groups[1].Value }
function Get-AuthCount { param([System.IO.Ports.SerialPort]$Serial) $seinfo = Send-CommandLines -Serial $Serial -Lines @("SEINFO") -RequiredPattern "OK SEINFO" -TimeoutSeconds 15; Write-Host $seinfo; return Get-AuthCountFromText $seinfo }
function Assert-AuthUnchanged { param([uint32]$Before, [uint32]$After, [string]$Name) if ($After -ne $Before) { throw "$Name changed AUTH_COUNT: before=$Before after=$After" }; Write-Host "${Name}_AUTH_UNCHANGED before=$Before after=$After" }
function Assert-AuthIncrementedOnce { param([uint32]$Before, [uint32]$After, [string]$Name) if ($After -ne ($Before + 1)) { throw "$Name expected AUTH_COUNT +1: before=$Before after=$After" }; Write-Host "${Name}_AUTH_INCREMENTED_ONCE before=$Before after=$After" }
function Open-WalletSerial {
    param([string]$Port, [int]$Baud)
    $s = New-Object System.IO.Ports.SerialPort
    $s.PortName = $Port; $s.BaudRate = $Baud; $s.Parity = [System.IO.Ports.Parity]::None; $s.DataBits = 8; $s.StopBits = [System.IO.Ports.StopBits]::One; $s.Handshake = [System.IO.Ports.Handshake]::None; $s.ReadTimeout = 200; $s.WriteTimeout = 2000; $s.NewLine = "`n"; $s.DtrEnable = $true; $s.RtsEnable = $true
    $s.Open(); Start-Sleep -Milliseconds 1500; Drain-Stale -Serial $s; return $s
}
function Close-WalletSerial { param([System.IO.Ports.SerialPort]$Serial) if ($Serial -ne $null) { if ($Serial.IsOpen) { $Serial.Close() }; $Serial.Dispose() } }

function Invoke-HostGenerator {
    param([string]$Network, [switch]$OmitUnlockPin, [string]$Name)

    $args = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", $Generator,
        "-Port", $Port,
        "-Network", $Network,
        "-CommandFormat", "PsbtLike",
        "-InputCount", "1",
        "-TxidLe", "29f6ce894fc3f8c5de72f787386039a54eeb2aded45b4087fc0992e40023a632",
        "-Vout", "1",
        "-InputSats", "100000",
        "-PaySats", "60000",
        "-ChangeSats", "30000",
        "-ChangeDerivation", "mvp-static-change/0"
    )

    if ($OmitUnlockPin) {
        $args += "-OmitUnlockPin"
    }

    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { $output = & powershell.exe @args 2>&1; $code = $LASTEXITCODE } finally { $ErrorActionPreference = $oldErrorActionPreference }
    $output | ForEach-Object { Write-Host $_ }
    return @{ Code = $code; Text = ($output | Out-String); Name = $Name }
}

$serial = $null
try {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host " STM32 C9.6 TESTNET SIGNING ENABLE REGRESSION"
    Write-Host "============================================================"
    Write-Host "Port: $Port"

    $serial = Open-WalletSerial -Port $Port -Baud $Baud
    $authBefore = Get-AuthCount -Serial $serial

    $realinfo = Send-CommandLines -Serial $serial -Lines @("REALINFO") -RequiredPattern "TESTNET_SIGNING_ENABLE_VERSION=C9.6_TESTNET_SIGNING_ENABLE_ON_TEST_FUNDS_ONLY_V1" -TimeoutSeconds $TimeoutSeconds
    Write-Host $realinfo
    Assert-Contains $realinfo "REAL_BITCOIN_STAGE=C9.6_TESTNET_SIGNING_ENABLE_ON_TEST_FUNDS_ONLY"
    Assert-Contains $realinfo "REAL_BITCOIN_READINESS=TESTNET_ONLY_ACTIVE_MAINNET_LOCKED"
    Assert-Contains $realinfo "NETWORK_ALLOWED=REGTEST,TESTNET"
    Assert-Contains $realinfo "REAL_BITCOIN_SIGNING_ENABLED=1"
    Assert-Contains $realinfo "TESTNET_SIGNING_ENABLED=1"
    Assert-Contains $realinfo "MAINNET_SIGNING_ENABLED=0"
    Assert-Contains $realinfo "TESTNET_SIGNING_BUILD_FLAG=1"
    Assert-Contains $realinfo "MAINNET_SIGNING_BUILD_FLAG=0"
    Assert-Contains $realinfo "TESTNET_SIGNING_ENABLE_BLOCKED=0"
    Assert-Contains $realinfo "TESTNET_SIGNING_ENABLE_ACTIVE=1"
    Assert-Contains $realinfo "TESTNET_SIGNING_ENABLE_ACTUAL_SIGNING_ENABLED=1"
    Assert-Contains $realinfo "TESTNET_SIGNING_ENABLE_BROADCAST=0"
    Assert-Contains $realinfo "TESTNET_SIGNING_ENABLE_MAINNET_LOCKOUT=1"
    Assert-Contains $realinfo "TESTNET_SIGNING_ENABLE_CONFIRMATION=UART_CONFIRM_CODE_OR_BUTTON_USER"
    Assert-Contains $realinfo "TESTNET_SIGNING_ENABLE_TROPIC_AUTH_GATE=1"
    Assert-Contains $realinfo "TESTNET_SIGNING_ENABLE_BIP84_DEVICE_DERIVATION=0"
    Write-Host "C9_6_REALINFO_TESTNET_SIGNING_ENABLE_PASS"

    $version = Send-CommandLines -Serial $serial -Lines @("VERSION") -RequiredPattern "TESTNET_SIGNING_ENABLE_ACTIVE=1" -TimeoutSeconds $TimeoutSeconds
    Write-Host $version
    $policy = Send-CommandLines -Serial $serial -Lines @("POLICYINFO") -RequiredPattern "TESTNET_SIGNING_ENABLE_ACTIVE=1" -TimeoutSeconds $TimeoutSeconds
    Write-Host $policy
    foreach ($text in @($version, $policy)) {
        Assert-Contains $text "REAL_BITCOIN_STAGE=C9.6_TESTNET_SIGNING_ENABLE_ON_TEST_FUNDS_ONLY"
        Assert-Contains $text "NETWORK_ALLOWED=REGTEST,TESTNET"
        Assert-Contains $text "TESTNET_SIGNING_ENABLED=1"
        Assert-Contains $text "MAINNET_SIGNING_ENABLED=0"
        Assert-Contains $text "TESTNET_SIGNING_BUILD_FLAG=1"
        Assert-Contains $text "TESTNET_SIGNING_ENABLE_BLOCKED=0"
        Assert-Contains $text "TESTNET_SIGNING_ENABLE_ACTIVE=1"
    }
    Write-Host "C9_6_VERSION_POLICY_LABELS_PASS"

    $authAfterManifest = Get-AuthCount -Serial $serial
    Assert-AuthUnchanged -Before $authBefore -After $authAfterManifest -Name "C9_6_TESTNET_SIGNING_ENABLE_MANIFEST"

    Close-WalletSerial -Serial $serial
    $serial = $null

    Write-Host ""
    Write-Host "--- C9.6 HOST TESTNET SIGNING ENABLE POSITIVE ---"
    $positive = Invoke-HostGenerator -Network "TESTNET" -Name "C9_6_TESTNET_POSITIVE"
    if ($positive.Code -ne 0) { throw "C9.6 TESTNET positive signing failed with exit code $($positive.Code)" }
    Assert-Contains $positive.Text "NETWORK=TESTNET"
    Assert-Contains $positive.Text "HOST_TX_GENERATOR_PASS"
    Assert-Contains $positive.Text "POLICY_DECISION=APPROVED_AND_SIGNED"
    Assert-Contains $positive.Text "RAW_TX_PRESENT=1"
    Assert-Contains $positive.Text "RAW_TX="
    Write-Host "C9_6_HOST_TESTNET_SIGNING_RAW_TX_PASS"

    $serial = Open-WalletSerial -Port $Port -Baud $Baud
    $authAfterPositive = Get-AuthCount -Serial $serial
    Assert-AuthIncrementedOnce -Before $authAfterManifest -After $authAfterPositive -Name "C9_6_HOST_TESTNET_SIGNING"
    $null = Send-CommandLines -Serial $serial -Lines @("LOCK") -RequiredPattern "OK LOCK" -TimeoutSeconds 15
    Close-WalletSerial -Serial $serial
    $serial = $null

    Write-Host ""
    Write-Host "--- C9.6 HOST MAINNET STILL REFUSES SIGN ---"
    $mainnet = Invoke-HostGenerator -Network "MAINNET" -OmitUnlockPin -Name "C9_6_MAINNET_NEGATIVE"
    if ($mainnet.Code -eq 0) { throw "C9.6 MAINNET negative unexpectedly exited 0" }
    Assert-Contains $mainnet.Text "HOST_TX_GENERATOR_FAIL"
    Assert-Contains $mainnet.Text "DEVICE_ERROR=ERR POLICY -42"
    Assert-Contains $mainnet.Text "RAW_TX_PRESENT=0"
    Assert-Contains $mainnet.Text "SIGN_SENT=0"
    Assert-Contains $mainnet.Text "NO_SIGN_SENT"
    Assert-NoRawTx $mainnet.Text "C9_6_MAINNET_NEGATIVE"
    Write-Host "C9_6_HOST_MAINNET_NO_SIGN_PASS"

    $serial = Open-WalletSerial -Port $Port -Baud $Baud
    $authAfterMainnet = Get-AuthCount -Serial $serial
    Assert-AuthUnchanged -Before $authAfterPositive -After $authAfterMainnet -Name "C9_6_HOST_MAINNET_REJECT"

    Write-Host ""
    Write-Host "C9_6_TESTNET_SIGNING_ENABLE_REGRESSION_PASS"
    exit 0
}
finally {
    Close-WalletSerial -Serial $serial
}
