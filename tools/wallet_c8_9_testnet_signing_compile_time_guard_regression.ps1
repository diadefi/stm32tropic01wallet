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
function Open-WalletSerial {
    param([string]$Port, [int]$Baud)
    $s = New-Object System.IO.Ports.SerialPort
    $s.PortName = $Port; $s.BaudRate = $Baud; $s.Parity = [System.IO.Ports.Parity]::None; $s.DataBits = 8; $s.StopBits = [System.IO.Ports.StopBits]::One; $s.Handshake = [System.IO.Ports.Handshake]::None; $s.ReadTimeout = 200; $s.WriteTimeout = 2000; $s.NewLine = "`n"; $s.DtrEnable = $true; $s.RtsEnable = $true
    $s.Open(); Start-Sleep -Milliseconds 1500; Drain-Stale -Serial $s; return $s
}
function Close-WalletSerial { param([System.IO.Ports.SerialPort]$Serial) if ($Serial -ne $null) { if ($Serial.IsOpen) { $Serial.Close() }; $Serial.Dispose() } }

function Invoke-HostTestnetGuardReject {
    Write-Host ""
    Write-Host "--- C8.9 HOST TESTNET GUARD REFUSES SIGN ---"
    $args = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", $Generator,
        "-Port", $Port,
        "-Network", "TESTNET",
        "-CommandFormat", "PsbtLike",
        "-InputCount", "1",
        "-TxidLe", "09f6ce894fc3f8c5de72f787386039a54eeb2aded45b4087fc0992e40023a632",
        "-Vout", "1",
        "-InputSats", "100000",
        "-PaySats", "60000",
        "-ChangeSats", "30000",
        "-ChangeDerivation", "mvp-static-change/0",
        "-OmitUnlockPin"
    )
    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { $output = & powershell.exe @args 2>&1; $code = $LASTEXITCODE } finally { $ErrorActionPreference = $oldErrorActionPreference }
    $output | ForEach-Object { Write-Host $_ }
    $joined = ($output | Out-String)
    if ($code -eq 0) { throw "C8.9 host guard dry-run unexpectedly exited 0" }
    Assert-Contains $joined "HOST_TX_GENERATOR_FAIL"
    Assert-Contains $joined "DEVICE_ERROR=ERR POLICY -42"
    Assert-Contains $joined "RAW_TX_PRESENT=0"
    Assert-Contains $joined "SIGN_SENT=0"
    Assert-Contains $joined "NO_SIGN_SENT"
    Assert-NoRawTx $joined "C8_9_HOST_TESTNET_GUARD"
    if ($joined -match "--- SEND SIGN COMMAND LINE BY LINE ---" -or $joined -match "(?m)^>> SIGN\r?$") { throw "C8.9 host guard dry-run sent SIGN" }
    Write-Host "C8_9_HOST_TESTNET_GUARD_NO_SIGN_PASS"
    $global:LASTEXITCODE = 0
}

$serial = $null
try {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host " STM32 C8.9 TESTNET SIGNING COMPILE-TIME GUARD REGRESSION"
    Write-Host "============================================================"
    Write-Host "Port: $Port"

    $serial = Open-WalletSerial -Port $Port -Baud $Baud
    $authBefore = Get-AuthCount -Serial $serial

    $realinfo = Send-CommandLines -Serial $serial -Lines @("REALINFO") -RequiredPattern "TESTNET_SIGNING_GUARD_VERSION=C8.9_TESTNET_SIGNING_COMPILE_TIME_GUARD_V1" -TimeoutSeconds $TimeoutSeconds
    Write-Host $realinfo
    Assert-Contains $realinfo "REAL_BITCOIN_STAGE="
    Assert-Contains $realinfo "TESTNET_SIGNING_COMPILE_TIME_GUARD_SUPPORTED=1"
    Assert-Contains $realinfo "TESTNET_SIGNING_BUILD_FLAG_NAME=WALLET_TESTNET_SIGNING_BUILD_FLAG"
    Assert-Contains $realinfo "TESTNET_SIGNING_BUILD_FLAG=0"
    Assert-Contains $realinfo "TESTNET_SIGNING_BUILD_FLAG_REQUIRED_FOR_SIGNING=1"
    Assert-Contains $realinfo "TESTNET_SIGNING_COMPILE_TIME_GUARD=ENFORCED"
    Assert-Contains $realinfo "TESTNET_SIGNING_RUNTIME_OVERRIDE_SUPPORTED=0"
    Assert-Contains $realinfo "TESTNET_SIGNING_SOURCE_CHANGE_REQUIRED=1"
    Assert-Contains $realinfo "TESTNET_SIGNING_REGRESSION_REQUIRED=1"
    Assert-Contains $realinfo "TESTNET_SIGNING_GUARD_SIGNING_ENABLED=0"
    Assert-Contains $realinfo "MAINNET_SIGNING_BUILD_FLAG=0"
    Assert-Contains $realinfo "MAINNET_SIGNING_COMPILE_TIME_GUARD=ENFORCED_OFF"
    Assert-Contains $realinfo "TESTNET_SIGNING_ENABLED=0"
    Assert-Contains $realinfo "MAINNET_SIGNING_ENABLED=0"
    Assert-Contains $realinfo "NEXT_SAFE_STAGE="
    Write-Host "C8_9_REALINFO_COMPILE_TIME_GUARD_PASS"

    $version = Send-CommandLines -Serial $serial -Lines @("VERSION") -RequiredPattern "TESTNET_SIGNING_COMPILE_TIME_GUARD_SUPPORTED=1" -TimeoutSeconds $TimeoutSeconds
    Write-Host $version
    Assert-Contains $version "TESTNET_SIGNING_BUILD_FLAG=0"
    $policy = Send-CommandLines -Serial $serial -Lines @("POLICYINFO") -RequiredPattern "TESTNET_SIGNING_COMPILE_TIME_GUARD_SUPPORTED=1" -TimeoutSeconds $TimeoutSeconds
    Write-Host $policy
    Assert-Contains $policy "TESTNET_SIGNING_BUILD_FLAG=0"
    Write-Host "C8_9_VERSION_POLICY_GUARD_LABELS_PASS"

    $authAfterManifest = Get-AuthCount -Serial $serial
    Assert-AuthUnchanged -Before $authBefore -After $authAfterManifest -Name "C8_9_COMPILE_TIME_GUARD_MANIFEST"

    Close-WalletSerial -Serial $serial
    $serial = $null

    Invoke-HostTestnetGuardReject

    $serial = Open-WalletSerial -Port $Port -Baud $Baud
    $authAfterHost = Get-AuthCount -Serial $serial
    Assert-AuthUnchanged -Before $authAfterManifest -After $authAfterHost -Name "C8_9_HOST_TESTNET_GUARD"

    Write-Host ""
    Write-Host "C8_9_TESTNET_SIGNING_COMPILE_TIME_GUARD_REGRESSION_PASS"
    exit 0
}
finally {
    Close-WalletSerial -Serial $serial
}
