param(
    [string]$Port = "COM3",
    [int]$Baud = 115200,
    [int]$TimeoutSeconds = 45,
    [string]$Generator = ".\tools\wallet_generate_tx_command.ps1",
    [string]$ArtifactPath = ".\logs\c8_7_testnet_intent_artifact.txt"
)

$ErrorActionPreference = "Stop"

function Read-Available {
    param([System.IO.Ports.SerialPort]$Serial)
    $s = ""
    try {
        while ($Serial.BytesToRead -gt 0) {
            $s += $Serial.ReadExisting()
            Start-Sleep -Milliseconds 20
        }
    } catch {
    }
    return $s
}

function Drain-Stale {
    param([System.IO.Ports.SerialPort]$Serial)
    Start-Sleep -Milliseconds 250
    $null = Read-Available -Serial $Serial
    $Serial.DiscardInBuffer()
    Start-Sleep -Milliseconds 100
    $null = Read-Available -Serial $Serial
    $Serial.DiscardInBuffer()
}

function Send-CommandLines {
    param([System.IO.Ports.SerialPort]$Serial, [string[]]$Lines, [string]$RequiredPattern, [int]$TimeoutSeconds)
    Drain-Stale -Serial $Serial
    foreach ($line in $Lines) {
        Write-Host ">> $line"
        $Serial.WriteLine($line)
        Start-Sleep -Milliseconds 100
    }
    $buf = ""
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $buf += Read-Available -Serial $Serial
        if (($buf -match $RequiredPattern) -and ($buf -match "(?s)READY.*>\s*$")) {
            return $buf
        }
        Start-Sleep -Milliseconds 50
    }
    Write-Host ""
    Write-Host "--- TIMEOUT BUFFER ---"
    Write-Host $buf
    throw "Timeout waiting for required response pattern: $RequiredPattern"
}

function Assert-Contains {
    param([string]$Text, [string]$Needle)
    if ($Text -notmatch [regex]::Escape($Needle)) {
        Write-Host ""
        Write-Host "--- TEXT THAT FAILED ASSERTION ---"
        Write-Host $Text
        throw "Missing expected text: $Needle"
    }
}

function Assert-NoRawTx {
    param([string]$Text, [string]$Name)
    if ($Text -match "RAW_TX=[0-9a-fA-F]+") {
        throw "$Name unexpectedly produced RAW_TX"
    }
}

function Get-Field {
    param([string]$Text, [string]$Name)
    $m = [regex]::Match($Text, "(?m)^" + [regex]::Escape($Name) + "=(.*)\r?$")
    if (-not $m.Success) { throw "Missing field $Name" }
    return $m.Groups[1].Value.Trim()
}

function Get-AuthCountFromText {
    param([string]$Text)
    $m = [regex]::Match($Text, "(?m)^AUTH_COUNT=(\d+)\s*$")
    if (-not $m.Success) {
        Write-Host ""
        Write-Host "--- TEXT MISSING AUTH_COUNT ---"
        Write-Host $Text
        throw "AUTH_COUNT missing"
    }
    return [uint32]$m.Groups[1].Value
}

function Get-AuthCount {
    param([System.IO.Ports.SerialPort]$Serial)
    $seinfo = Send-CommandLines -Serial $Serial -Lines @("SEINFO") -RequiredPattern "OK SEINFO" -TimeoutSeconds 15
    Write-Host $seinfo
    return Get-AuthCountFromText $seinfo
}

function Assert-AuthUnchanged {
    param([uint32]$Before, [uint32]$After, [string]$Name)
    if ($After -ne $Before) {
        throw "$Name changed AUTH_COUNT: before=$Before after=$After"
    }
    Write-Host "${Name}_AUTH_UNCHANGED before=$Before after=$After"
}

function Open-WalletSerial {
    param([string]$Port, [int]$Baud)
    $s = New-Object System.IO.Ports.SerialPort
    $s.PortName = $Port
    $s.BaudRate = $Baud
    $s.Parity = [System.IO.Ports.Parity]::None
    $s.DataBits = 8
    $s.StopBits = [System.IO.Ports.StopBits]::One
    $s.Handshake = [System.IO.Ports.Handshake]::None
    $s.ReadTimeout = 200
    $s.WriteTimeout = 2000
    $s.NewLine = "`n"
    $s.DtrEnable = $true
    $s.RtsEnable = $true
    $s.Open()
    Start-Sleep -Milliseconds 1500
    Drain-Stale -Serial $s
    return $s
}

function Close-WalletSerial {
    param([System.IO.Ports.SerialPort]$Serial)
    if ($Serial -ne $null) {
        if ($Serial.IsOpen) { $Serial.Close() }
        $Serial.Dispose()
    }
}

function Invoke-HostTestnetArtifactReject {
    Write-Host ""
    Write-Host "--- C8.7 HOST TESTNET ARTIFACT EXPORT REFUSES SIGN ---"
    $args = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", $Generator,
        "-Port", $Port,
        "-Network", "TESTNET",
        "-CommandFormat", "PsbtLike",
        "-InputCount", "2",
        "-TxidLe", "09f6ce894fc3f8c5de72f787386039a54eeb2aded45b4087fc0992e40023a632",
        "-Vout", "1",
        "-InputSats", "100000",
        "-TxidLe1", "19f6ce894fc3f8c5de72f787386039a54eeb2aded45b4087fc0992e40023a633",
        "-Vout1", "0",
        "-InputSats1", "50000",
        "-PaySats", "70000",
        "-ChangeSats", "60000",
        "-ChangeDerivation", "mvp-static-change/0",
        "-OmitUnlockPin"
    )

    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & powershell.exe @args 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }

    $output | ForEach-Object { Write-Host $_ }
    $joined = ($output | Out-String)
    if ($code -eq 0) { throw "C8.7 host artifact dry-run unexpectedly exited 0" }
    Assert-Contains $joined "HOST_TX_GENERATOR_FAIL"
    Assert-Contains $joined "POLICY_DECISION=REJECTED_BY_DEVICE_CHECK"
    Assert-Contains $joined "DEVICE_ERROR=ERR POLICY -42"
    Assert-Contains $joined "RAW_TX_PRESENT=0"
    Assert-Contains $joined "SIGN_SENT=0"
    Assert-Contains $joined "NO_SIGN_SENT"
    Assert-NoRawTx $joined "C8_7_HOST_TESTNET_ARTIFACT"
    if ($joined -match "--- SEND SIGN COMMAND LINE BY LINE ---" -or $joined -match "(?m)^>> SIGN\r?$") {
        throw "C8.7 host artifact dry-run sent SIGN"
    }
    Write-Host "C8_7_HOST_TESTNET_ARTIFACT_NO_SIGN_PASS"
    $global:LASTEXITCODE = 0
}

$serial = $null
try {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host " STM32 C8.7 TESTNET DRY-RUN ARTIFACT EXPORT REGRESSION"
    Write-Host "============================================================"
    Write-Host "Port: $Port"

    if (-not (Test-Path ".\logs")) {
        New-Item -ItemType Directory -Path ".\logs" | Out-Null
    }

    $serial = Open-WalletSerial -Port $Port -Baud $Baud
    $authBefore = Get-AuthCount -Serial $serial

    Write-Host ""
    Write-Host "--- C8.7 REALINFO ARTIFACT EXPORT MANIFEST ---"
    $realinfo = Send-CommandLines -Serial $serial -Lines @("REALINFO") -RequiredPattern "TESTNET_ARTIFACT_VERSION=C8.7_TESTNET_DRY_RUN_ARTIFACT_EXPORT_V1" -TimeoutSeconds $TimeoutSeconds
    Write-Host $realinfo
    Assert-Contains $realinfo "TESTNET_ARTIFACT_EXPORT_SUPPORTED=1"
    Assert-Contains $realinfo "TESTNET_ARTIFACT_SIGNING_ENABLED=0"
    Assert-Contains $realinfo "TESTNET_ARTIFACT_FORMAT=PSBT_LIKE_INTENT_TEXT_V1"
    Assert-Contains $realinfo "TESTNET_ARTIFACT_UNSIGNED_ONLY=1"
    Assert-Contains $realinfo "TESTNET_ARTIFACT_DEVICE_SIGNATURE=0"
    Assert-Contains $realinfo "TESTNET_ARTIFACT_RAW_TX=0"
    Assert-Contains $realinfo "TESTNET_ARTIFACT_BROADCAST=0"
    Assert-Contains $realinfo "TESTNET_ARTIFACT_OUTPUT=HOST_FILE_ONLY_NO_DEVICE_SIGNATURE"
    Assert-Contains $realinfo "TESTNET_SIGNING_ENABLED=0"
    Write-Host "C8_7_REALINFO_ARTIFACT_EXPORT_PASS"

    Write-Host ""
    Write-Host "--- C8.7 VERSION/POLICY ARTIFACT LABELS ---"
    $version = Send-CommandLines -Serial $serial -Lines @("VERSION") -RequiredPattern "TESTNET_ARTIFACT_EXPORT_SUPPORTED=1" -TimeoutSeconds $TimeoutSeconds
    Write-Host $version
    Assert-Contains $version "TESTNET_ARTIFACT_SIGNING_ENABLED=0"
    $policy = Send-CommandLines -Serial $serial -Lines @("POLICYINFO") -RequiredPattern "TESTNET_ARTIFACT_EXPORT_SUPPORTED=1" -TimeoutSeconds $TimeoutSeconds
    Write-Host $policy
    Assert-Contains $policy "TESTNET_ARTIFACT_SIGNING_ENABLED=0"
    Write-Host "C8_7_VERSION_POLICY_ARTIFACT_LABELS_PASS"

    $identity = Send-CommandLines -Serial $serial -Lines @("IDENTITY") -RequiredPattern "OK IDENTITY" -TimeoutSeconds $TimeoutSeconds
    Write-Host $identity
    $pubkey = Get-Field -Text $identity -Name "PUBKEY_COMPRESSED"
    $address = Get-Field -Text $identity -Name "ADDRESS"

    $artifactLines = @(
        "TESTNET_DRY_RUN_ARTIFACT_BEGIN",
        "ARTIFACT_VERSION=C8.7_TESTNET_DRY_RUN_ARTIFACT_EXPORT_V1",
        "NETWORK=TESTNET",
        "COMMAND_FORMAT=PSBT_LIKE_TEXT_V1_DRY_RUN",
        "INPUT_COUNT=2",
        "INPUT0_TXID_LE=09f6ce894fc3f8c5de72f787386039a54eeb2aded45b4087fc0992e40023a632",
        "INPUT0_VOUT=1",
        "INPUT0_SATS=100000",
        "INPUT1_TXID_LE=19f6ce894fc3f8c5de72f787386039a54eeb2aded45b4087fc0992e40023a633",
        "INPUT1_VOUT=0",
        "INPUT1_SATS=50000",
        "PAY_SCRIPT=76a914f2124d94cabdb95d49479627cbbe5d7be609f73888ac",
        "PAY_SATS=70000",
        "CHANGE_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
        "CHANGE_SATS=60000",
        "CHANGE_DERIVATION=mvp-static-change/0",
        "FEE_SATS=20000",
        "DEVICE_ADDRESS=$address",
        "DEVICE_PUBKEY_COMPRESSED=$pubkey",
        "REALINFO_STAGE=" + (Get-Field -Text $realinfo -Name "REAL_BITCOIN_STAGE"),
        "TESTNET_ACTIVATION_READY=0",
        "DEVICE_SIGNATURE=0",
        "RAW_TX=0",
        "BROADCAST=0",
        "TESTNET_DRY_RUN_ARTIFACT_END"
    )

    Set-Content -Path $ArtifactPath -Value $artifactLines -Encoding ascii
    $artifact = Get-Content -Path $ArtifactPath -Raw
    Write-Host "TESTNET_ARTIFACT_FILE=$ArtifactPath"
    Write-Host $artifact
    Assert-Contains $artifact "TESTNET_DRY_RUN_ARTIFACT_BEGIN"
    Assert-Contains $artifact "ARTIFACT_VERSION=C8.7_TESTNET_DRY_RUN_ARTIFACT_EXPORT_V1"
    Assert-Contains $artifact "DEVICE_SIGNATURE=0"
    Assert-Contains $artifact "RAW_TX=0"
    Assert-Contains $artifact "BROADCAST=0"
    Assert-Contains $artifact "TESTNET_ACTIVATION_READY=0"
    Write-Host "C8_7_HOST_TESTNET_ARTIFACT_FILE_PASS"

    $authAfterManifest = Get-AuthCount -Serial $serial
    Assert-AuthUnchanged -Before $authBefore -After $authAfterManifest -Name "C8_7_ARTIFACT_MANIFEST"

    Close-WalletSerial -Serial $serial
    $serial = $null

    Invoke-HostTestnetArtifactReject

    $serial = Open-WalletSerial -Port $Port -Baud $Baud
    $authAfterHost = Get-AuthCount -Serial $serial
    Assert-AuthUnchanged -Before $authAfterManifest -After $authAfterHost -Name "C8_7_HOST_TESTNET_ARTIFACT"

    Write-Host ""
    Write-Host "C8_7_TESTNET_DRY_RUN_ARTIFACT_EXPORT_REGRESSION_PASS"
    exit 0
}
finally {
    Close-WalletSerial -Serial $serial
}
