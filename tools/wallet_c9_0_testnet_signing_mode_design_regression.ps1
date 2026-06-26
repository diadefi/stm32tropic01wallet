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

function Invoke-HostTestnetModeReject {
    Write-Host ""
    Write-Host "--- C9.0 HOST TESTNET SIGNING MODE STILL REFUSES SIGN ---"
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
    if ($code -eq 0) { throw "C9.0 host testnet mode dry-run unexpectedly exited 0" }
    Assert-Contains $joined "HOST_TX_GENERATOR_FAIL"
    Assert-Contains $joined "DEVICE_ERROR=ERR POLICY -42"
    Assert-Contains $joined "RAW_TX_PRESENT=0"
    Assert-Contains $joined "SIGN_SENT=0"
    Assert-Contains $joined "NO_SIGN_SENT"
    Assert-NoRawTx $joined "C9_0_HOST_TESTNET_SIGNING_MODE"
    if ($joined -match "--- SEND SIGN COMMAND LINE BY LINE ---" -or $joined -match "(?m)^>> SIGN\r?$") { throw "C9.0 host testnet mode dry-run sent SIGN" }
    Write-Host "C9_0_HOST_TESTNET_SIGNING_MODE_NO_SIGN_PASS"
    $global:LASTEXITCODE = 0
}

$serial = $null
try {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host " STM32 C9.0 TESTNET SIGNING MODE DESIGN REGRESSION"
    Write-Host "============================================================"
    Write-Host "Port: $Port"

    $serial = Open-WalletSerial -Port $Port -Baud $Baud
    $authBefore = Get-AuthCount -Serial $serial

    $realinfo = Send-CommandLines -Serial $serial -Lines @("REALINFO") -RequiredPattern "TESTNET_SIGNING_MODE_VERSION=C9.0_TESTNET_SIGNING_MODE_DESIGN_V1" -TimeoutSeconds $TimeoutSeconds
    Write-Host $realinfo
    Assert-Contains $realinfo "REAL_BITCOIN_STAGE="
    Assert-Contains $realinfo "TESTNET_SIGNING_MODE_DESIGN_SUPPORTED=1"
    Assert-Contains $realinfo "TESTNET_SIGNING_MODE=DESIGN_ONLY_NOT_ACTIVE"
    Assert-Contains $realinfo "TESTNET_SIGNING_MODE_NETWORK=TESTNET_ONLY"
    Assert-Contains $realinfo "TESTNET_SIGNING_MODE_SIGNING_ENABLED=0"
    Assert-Contains $realinfo "TESTNET_SIGNING_MODE_REQUIRES_BUILD_FLAG=1"
    Assert-Contains $realinfo "TESTNET_SIGNING_MODE_BUILD_FLAG=WALLET_TESTNET_SIGNING_BUILD_FLAG"
    Assert-Contains $realinfo "TESTNET_SIGNING_MODE_BUILD_FLAG_STATE=0"
    Assert-Contains $realinfo "TESTNET_SIGNING_MODE_REQUIRES_TEST_FUNDS=1"
    Assert-Contains $realinfo "TESTNET_SIGNING_MODE_REQUIRES_PIN_SESSION=1"
    Assert-Contains $realinfo "TESTNET_SIGNING_MODE_REQUIRES_CHECK_ID=1"
    Assert-Contains $realinfo "TESTNET_SIGNING_MODE_REQUIRES_USER_CONFIRMATION=1"
    Assert-Contains $realinfo "TESTNET_SIGNING_MODE_REQUIRES_PHYSICAL_CONFIRM=1"
    Assert-Contains $realinfo "TESTNET_SIGNING_MODE_REQUIRES_TROPIC_AUTH_GATE=1"
    Assert-Contains $realinfo "TESTNET_SIGNING_MODE_REQUIRES_DERIVED_TESTNET_KEYS=1"
    Assert-Contains $realinfo "TESTNET_SIGNING_MODE_REQUIRES_DERIVED_CHANGE=1"
    Assert-Contains $realinfo "TESTNET_SIGNING_MODE_REQUIRES_FEE_POLICY=1"
    Assert-Contains $realinfo "TESTNET_SIGNING_MODE_BROADCAST_ENABLED=0"
    Assert-Contains $realinfo "TESTNET_SIGNING_MODE_MAINNET_LOCKOUT=1"
    Assert-Contains $realinfo "TESTNET_SIGNING_MODE_RUNTIME_OVERRIDE_SUPPORTED=0"
    Assert-Contains $realinfo "TESTNET_SIGNING_MODE_OUTPUT=DESIGN_ONLY_NO_DEVICE_SIGNATURE"
    Assert-Contains $realinfo "TESTNET_SIGNING_ENABLED=0"
    Assert-Contains $realinfo "MAINNET_SIGNING_ENABLED=0"
    Assert-Contains $realinfo "NEXT_SAFE_STAGE="
    Write-Host "C9_0_REALINFO_SIGNING_MODE_DESIGN_PASS"

    $version = Send-CommandLines -Serial $serial -Lines @("VERSION") -RequiredPattern "TESTNET_SIGNING_MODE_DESIGN_SUPPORTED=1" -TimeoutSeconds $TimeoutSeconds
    Write-Host $version
    Assert-Contains $version "REAL_BITCOIN_STAGE="
    Assert-Contains $version "TESTNET_SIGNING_MODE_SIGNING_ENABLED=0"
    $policy = Send-CommandLines -Serial $serial -Lines @("POLICYINFO") -RequiredPattern "TESTNET_SIGNING_MODE_DESIGN_SUPPORTED=1" -TimeoutSeconds $TimeoutSeconds
    Write-Host $policy
    Assert-Contains $policy "REAL_BITCOIN_STAGE="
    Assert-Contains $policy "TESTNET_SIGNING_MODE_SIGNING_ENABLED=0"
    Write-Host "C9_0_VERSION_POLICY_SIGNING_MODE_LABELS_PASS"

    $authAfterManifest = Get-AuthCount -Serial $serial
    Assert-AuthUnchanged -Before $authBefore -After $authAfterManifest -Name "C9_0_SIGNING_MODE_MANIFEST"

    Close-WalletSerial -Serial $serial
    $serial = $null

    Invoke-HostTestnetModeReject

    $serial = Open-WalletSerial -Port $Port -Baud $Baud
    $authAfterHost = Get-AuthCount -Serial $serial
    Assert-AuthUnchanged -Before $authAfterManifest -After $authAfterHost -Name "C9_0_HOST_TESTNET_SIGNING_MODE"

    Write-Host ""
    Write-Host "C9_0_TESTNET_SIGNING_MODE_DESIGN_REGRESSION_PASS"
    exit 0
}
finally {
    Close-WalletSerial -Serial $serial
}
