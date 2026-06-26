param(
    [string]$Port = "COM3",
    [int]$Baud = 115200,
    [int]$TimeoutSeconds = 45,
    [string]$Generator = ".\tools\wallet_generate_tx_command.ps1"
)

$ErrorActionPreference = "Stop"

$TestnetBip84Address = "tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx"
$TestnetBip84Script = "0014751e76e8199196d454941c45d1b3a323f1433bd6"
$TestnetBip84ChangePath = "m/84h/1h/0h/1/0"
$RegtestChangePath = "mvp-static-change/0"

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
    param(
        [string]$Name,
        [string]$ChangeScript,
        [string]$ChangeDerivation,
        [switch]$OmitUnlockPin
    )

    $args = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", $Generator,
        "-Port", $Port,
        "-Network", "TESTNET",
        "-CommandFormat", "PsbtLike",
        "-InputCount", "1",
        "-TxidLe", "39f6ce894fc3f8c5de72f787386039a54eeb2aded45b4087fc0992e40023a632",
        "-Vout", "1",
        "-InputSats", "100000",
        "-PaySats", "60000",
        "-ChangeSats", "30000",
        "-ChangeScript", $ChangeScript,
        "-ChangeDerivation", $ChangeDerivation
    )

    if ($OmitUnlockPin) {
        $args += "-OmitUnlockPin"
    }

    Write-Host ""
    Write-Host "--- $Name ---"
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
    Write-Host " STM32 C9.7/C9.8 TESTNET BIP84 CHANGE REGRESSION"
    Write-Host "============================================================"
    Write-Host "Port: $Port"

    $serial = Open-WalletSerial -Port $Port -Baud $Baud
    $authBefore = Get-AuthCount -Serial $serial

    $identity = Send-CommandLines -Serial $serial -Lines @("IDENTITY") -RequiredPattern "TESTNET_BIP84_IDENTITY_SUPPORTED=1" -TimeoutSeconds $TimeoutSeconds
    Write-Host $identity
    Assert-Contains $identity "TESTNET_BIP84_IDENTITY_VERSION=C9.7_TESTNET_BIP84_IDENTITY_V1"
    Assert-Contains $identity "TESTNET_BIP84_ADDRESS=$TestnetBip84Address"
    Assert-Contains $identity "TESTNET_BIP84_SCRIPT_P2WPKH=$TestnetBip84Script"
    Assert-Contains $identity "TESTNET_BIP84_CHANGE_PATH=$TestnetBip84ChangePath"
    Assert-Contains $identity "TESTNET_BIP84_DEVICE_DERIVES_KEYS=0"
    Assert-Contains $identity "TESTNET_BIP84_SIGNING_ENABLED=0"
    Write-Host "C9_7_TESTNET_BIP84_IDENTITY_PASS"

    $realinfo = Send-CommandLines -Serial $serial -Lines @("REALINFO") -RequiredPattern "TESTNET_CHANGE_DERIVATION_ENFORCEMENT_CURRENT=C9.8_TESTNET_CHANGE_DERIVATION_ENFORCEMENT_V1" -TimeoutSeconds $TimeoutSeconds
    Write-Host $realinfo
    Assert-Contains $realinfo "REAL_BITCOIN_STAGE=C9.8_TESTNET_CHANGE_DERIVATION_ENFORCEMENT"
    Assert-Contains $realinfo "TESTNET_BIP84_ADDRESS=$TestnetBip84Address"
    Assert-Contains $realinfo "TESTNET_CHANGE_DERIVATION_EXACT_REQUIRED=$TestnetBip84ChangePath"
    Assert-Contains $realinfo "TESTNET_CHANGE_SCRIPT_EXACT_REQUIRED=$TestnetBip84Script"
    Assert-Contains $realinfo "TESTNET_CHANGE_DERIVATION_ENFORCEMENT_SIGNING_ENABLED=1"
    Assert-Contains $realinfo "BLOCKER_CHANGE_DERIVATION=0"
    Write-Host "C9_8_REALINFO_CHANGE_ENFORCEMENT_PASS"

    $policy = Send-CommandLines -Serial $serial -Lines @("POLICYINFO") -RequiredPattern "TESTNET_CHANGE_DERIVATION_ENFORCEMENT_VERSION=C9.8_TESTNET_CHANGE_DERIVATION_ENFORCEMENT_V1" -TimeoutSeconds $TimeoutSeconds
    Write-Host $policy
    Assert-Contains $policy "CHANGE_DERIVATION_MODEL=REGTEST_STATIC_OR_TESTNET_BIP84_METADATA"
    Assert-Contains $policy "CHANGE_DERIVATION_ALLOWED=$RegtestChangePath"
    Assert-Contains $policy "TESTNET_CHANGE_DERIVATION_ALLOWED=$TestnetBip84ChangePath"
    Assert-Contains $policy "TESTNET_CHANGE_SCRIPT_P2WPKH=$TestnetBip84Script"
    Write-Host "C9_8_POLICYINFO_CHANGE_ENFORCEMENT_PASS"

    $authAfterManifest = Get-AuthCount -Serial $serial
    Assert-AuthUnchanged -Before $authBefore -After $authAfterManifest -Name "C9_7_C9_8_MANIFEST"
    Close-WalletSerial -Serial $serial
    $serial = $null

    $positive = Invoke-HostGenerator -Name "C9_8_TESTNET_BIP84_CHANGE_POSITIVE" -ChangeScript $TestnetBip84Script -ChangeDerivation $TestnetBip84ChangePath
    if ($positive.Code -ne 0) { throw "C9.8 TESTNET BIP84 change positive failed with exit code $($positive.Code)" }
    Assert-Contains $positive.Text "NETWORK=TESTNET"
    Assert-Contains $positive.Text "CHANGE_TO_SCRIPT=$TestnetBip84Script"
    Assert-Contains $positive.Text "CHANGE_DERIVATION=$TestnetBip84ChangePath"
    Assert-Contains $positive.Text "HOST_TX_GENERATOR_PASS"
    Assert-Contains $positive.Text "POLICY_DECISION=APPROVED_AND_SIGNED"
    Assert-Contains $positive.Text "RAW_TX_PRESENT=1"
    Assert-Contains $positive.Text "RAW_TX="
    Write-Host "C9_8_TESTNET_BIP84_CHANGE_SIGNING_PASS"

    $serial = Open-WalletSerial -Port $Port -Baud $Baud
    $authAfterPositive = Get-AuthCount -Serial $serial
    Assert-AuthIncrementedOnce -Before $authAfterManifest -After $authAfterPositive -Name "C9_8_TESTNET_BIP84_CHANGE_SIGNING"
    $null = Send-CommandLines -Serial $serial -Lines @("LOCK") -RequiredPattern "OK LOCK" -TimeoutSeconds 15
    Close-WalletSerial -Serial $serial
    $serial = $null

    $badDerivation = Invoke-HostGenerator -Name "C9_8_TESTNET_WRONG_CHANGE_DERIVATION" -ChangeScript $TestnetBip84Script -ChangeDerivation $RegtestChangePath -OmitUnlockPin
    if ($badDerivation.Code -eq 0) { throw "C9.8 wrong derivation unexpectedly exited 0" }
    Assert-Contains $badDerivation.Text "ERR POLICY -54"
    Assert-Contains $badDerivation.Text "POLICY_DECISION=REJECTED"
    Assert-Contains $badDerivation.Text "SIGNATURE_PRODUCED=0"
    Assert-NoRawTx $badDerivation.Text "C9_8_TESTNET_WRONG_CHANGE_DERIVATION"
    Write-Host "C9_8_TESTNET_WRONG_CHANGE_DERIVATION_REJECT_PASS"

    $badScript = Invoke-HostGenerator -Name "C9_8_TESTNET_WRONG_CHANGE_SCRIPT" -ChangeScript "76a914751e76e8199196d454941c45d1b3a323f1433bd688ac" -ChangeDerivation $TestnetBip84ChangePath -OmitUnlockPin
    if ($badScript.Code -eq 0) { throw "C9.8 wrong change script unexpectedly exited 0" }
    Assert-Contains $badScript.Text "ERR POLICY -39"
    Assert-Contains $badScript.Text "POLICY_DECISION=REJECTED"
    Assert-Contains $badScript.Text "SIGNATURE_PRODUCED=0"
    Assert-NoRawTx $badScript.Text "C9_8_TESTNET_WRONG_CHANGE_SCRIPT"
    Write-Host "C9_8_TESTNET_WRONG_CHANGE_SCRIPT_REJECT_PASS"

    $serial = Open-WalletSerial -Port $Port -Baud $Baud
    $authAfterNegatives = Get-AuthCount -Serial $serial
    Assert-AuthUnchanged -Before $authAfterPositive -After $authAfterNegatives -Name "C9_8_TESTNET_NEGATIVE_CHECKS"

    Write-Host ""
    Write-Host "C9_7_C9_8_TESTNET_BIP84_CHANGE_REGRESSION_PASS"
    exit 0
}
finally {
    Close-WalletSerial -Serial $serial
}
