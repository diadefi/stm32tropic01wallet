param(
    [string]$Port = "COM3",
    [int]$Baud = 115200,
    [int]$TimeoutSeconds = 45
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

$serial = $null
try {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host " STM32 C8.8 TESTNET DERIVATION MODEL DECISION REGRESSION"
    Write-Host "============================================================"
    Write-Host "Port: $Port"

    $serial = Open-WalletSerial -Port $Port -Baud $Baud
    $authBefore = Get-AuthCount -Serial $serial

    $realinfo = Send-CommandLines -Serial $serial -Lines @("REALINFO") -RequiredPattern "TESTNET_DERIVATION_DECISION_VERSION=C8.8_TESTNET_DERIVATION_MODEL_DECISION_V1" -TimeoutSeconds $TimeoutSeconds
    Write-Host $realinfo
    Assert-Contains $realinfo "TESTNET_DERIVATION_DECISION_SUPPORTED=1"
    Assert-Contains $realinfo "TESTNET_DERIVATION_DECISION_SIGNING_ENABLED=0"
    Assert-Contains $realinfo "TESTNET_DERIVATION_DECISION_MODEL=BIP84_TESTNET_P2WPKH_ACCOUNT"
    Assert-Contains $realinfo "TESTNET_DERIVATION_DECISION_ACCOUNT_PATH=m/84h/1h/0h"
    Assert-Contains $realinfo "TESTNET_DERIVATION_DECISION_RECEIVE_PATH=m/84h/1h/0h/0/{index}"
    Assert-Contains $realinfo "TESTNET_DERIVATION_DECISION_CHANGE_PATH=m/84h/1h/0h/1/{index}"
    Assert-Contains $realinfo "TESTNET_DERIVATION_DECISION_ADDRESS_FORMAT=tb1q_P2WPKH"
    Assert-Contains $realinfo "TESTNET_DERIVATION_DECISION_XPUB_EXPORT=BLOCKED"
    Assert-Contains $realinfo "TESTNET_DERIVATION_DECISION_DEVICE_DERIVES_KEYS=0"
    Assert-Contains $realinfo "TESTNET_DERIVATION_DECISION_ACTIVATION_BLOCKED=1"
    Assert-Contains $realinfo "TESTNET_DERIVATION_DECISION_OUTPUT=MODEL_SELECTED_IMPLEMENTATION_BLOCKED"
    Assert-Contains $realinfo "TESTNET_SIGNING_ENABLED=0"
    Write-Host "C8_8_REALINFO_DERIVATION_DECISION_PASS"

    $version = Send-CommandLines -Serial $serial -Lines @("VERSION") -RequiredPattern "TESTNET_DERIVATION_DECISION_SUPPORTED=1" -TimeoutSeconds $TimeoutSeconds
    Write-Host $version
    Assert-Contains $version "TESTNET_DERIVATION_DECISION_SIGNING_ENABLED=0"
    $policy = Send-CommandLines -Serial $serial -Lines @("POLICYINFO") -RequiredPattern "TESTNET_DERIVATION_DECISION_SUPPORTED=1" -TimeoutSeconds $TimeoutSeconds
    Write-Host $policy
    Assert-Contains $policy "TESTNET_DERIVATION_DECISION_SIGNING_ENABLED=0"
    Write-Host "C8_8_VERSION_POLICY_DERIVATION_DECISION_LABELS_PASS"

    Write-Host "TESTNET_DERIVATION_DECISION_BEGIN"
    Write-Host "TESTNET_DERIVATION_DECISION_VERSION=C8.8_TESTNET_DERIVATION_MODEL_DECISION_V1"
    Write-Host "MODEL=BIP84_TESTNET_P2WPKH_ACCOUNT"
    Write-Host "ACCOUNT_PATH=m/84h/1h/0h"
    Write-Host "RECEIVE_PATH=m/84h/1h/0h/0/{index}"
    Write-Host "CHANGE_PATH=m/84h/1h/0h/1/{index}"
    Write-Host "DEVICE_DERIVES_KEYS=0"
    Write-Host "SIGNING_ENABLED=0"
    Write-Host "TESTNET_DERIVATION_DECISION_END"
    Write-Host "C8_8_HOST_DERIVATION_DECISION_TRANSCRIPT_PASS"

    $authAfter = Get-AuthCount -Serial $serial
    Assert-AuthUnchanged -Before $authBefore -After $authAfter -Name "C8_8_DERIVATION_DECISION"

    Write-Host ""
    Write-Host "C8_8_TESTNET_DERIVATION_MODEL_DECISION_REGRESSION_PASS"
    exit 0
}
finally {
    Close-WalletSerial -Serial $serial
}
