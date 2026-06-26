param(
    [string]$Port = "COM3",
    [int]$Baud = 115200,
    [int]$TimeoutSeconds = 45,
    [string]$Generator = ".\tools\wallet_generate_tx_command.ps1"
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
    param(
        [System.IO.Ports.SerialPort]$Serial,
        [string[]]$Lines,
        [string]$RequiredPattern,
        [int]$TimeoutSeconds
    )

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
    param(
        [string]$Text,
        [string]$Name
    )

    $m = [regex]::Match($Text, "(?m)^" + [regex]::Escape($Name) + "=(.*)\r?$")
    if (-not $m.Success) {
        throw "Missing field $Name"
    }
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
    param(
        [uint32]$Before,
        [uint32]$After,
        [string]$Name
    )

    if ($After -ne $Before) {
        throw "$Name changed AUTH_COUNT: before=$Before after=$After"
    }

    Write-Host "${Name}_AUTH_UNCHANGED before=$Before after=$After"
}

function Open-WalletSerial {
    param(
        [string]$Port,
        [int]$Baud
    )

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
        if ($Serial.IsOpen) {
            $Serial.Close()
        }
        $Serial.Dispose()
    }
}

function Invoke-HostTestnetDryRunReject {
    Write-Host ""
    Write-Host "--- C8.1 HOST TESTNET DRY-RUN REFUSES SIGN ---"

    $baseArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $Generator,
        "-Port", $Port,
        "-Network", "TESTNET",
        "-TxidLe", "09f6ce894fc3f8c5de72f787386039a54eeb2aded45b4087fc0992e40023a632",
        "-Vout", "1",
        "-InputSats", "100000",
        "-PaySats", "60000",
        "-ChangeSats", "30000",
        "-CommandFormat", "PsbtLike",
        "-ChangeDerivation", "mvp-static-change/0",
        "-OmitUnlockPin"
    )

    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & powershell.exe @baseArgs 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }

    $output | ForEach-Object { Write-Host $_ }
    $joined = ($output | Out-String)

    if ($code -eq 0) {
        throw "C8.1 host dry-run failed: generator unexpectedly exited 0"
    }

    Assert-Contains $joined "HOST_TX_GENERATOR_FAIL"
    Assert-Contains $joined "POLICY_DECISION=REJECTED_BY_DEVICE_CHECK"
    Assert-Contains $joined "DEVICE_ERROR=ERR POLICY -42"
    Assert-Contains $joined "RAW_TX_PRESENT=0"
    Assert-Contains $joined "SIGN_SENT=0"
    Assert-Contains $joined "NO_SIGN_SENT"
    Assert-NoRawTx $joined "C8_1_HOST_TESTNET_DRY_RUN"

    if ($joined -match "--- SEND SIGN COMMAND LINE BY LINE ---" -or
        $joined -match "(?m)^>> SIGN\r?$") {
        throw "C8.1 host dry-run failed: SIGN command was sent"
    }

    Write-Host "C8_1_HOST_TESTNET_NO_SIGN_PASS"
    $global:LASTEXITCODE = 0
}

$serial = $null
try {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host " STM32 C8.1 TESTNET WATCH-ONLY DRY-RUN REGRESSION"
    Write-Host "============================================================"
    Write-Host "Port: $Port"

    $serial = Open-WalletSerial -Port $Port -Baud $Baud

    $authBefore = Get-AuthCount -Serial $serial

    Write-Host ""
    Write-Host "--- C8.1 REALINFO WATCH-ONLY MANIFEST ---"
    $realinfo = Send-CommandLines -Serial $serial -Lines @("REALINFO") -RequiredPattern "TESTNET_WATCH_ONLY_DRY_RUN_SUPPORTED=1" -TimeoutSeconds $TimeoutSeconds
    Write-Host $realinfo
    Assert-Contains $realinfo "REAL_BITCOIN_READINESS_VERSION="
    Assert-Contains $realinfo "REAL_BITCOIN_STAGE="
    Assert-Contains $realinfo "REAL_BITCOIN_READINESS=NOT_READY"
    Assert-Contains $realinfo "NETWORK_ALLOWED=REGTEST"
    Assert-Contains $realinfo "REAL_BITCOIN_SIGNING_ENABLED=0"
    Assert-Contains $realinfo "TESTNET_SIGNING_ENABLED=0"
    Assert-Contains $realinfo "MAINNET_SIGNING_ENABLED=0"
    Assert-Contains $realinfo "TESTNET_WATCH_ONLY_DRY_RUN_SUPPORTED=1"
    Assert-Contains $realinfo "TESTNET_DRY_RUN_SIGNING_ENABLED=0"
    Assert-Contains $realinfo "TESTNET_DRY_RUN_NETWORK=TESTNET"
    Assert-Contains $realinfo "TESTNET_DRY_RUN_WATCH_ONLY=1"
    Assert-Contains $realinfo "TESTNET_DRY_RUN_USES_DEVICE_PUBKEY=1"
    Assert-Contains $realinfo "TESTNET_DRY_RUN_DEVICE_SIGNATURE=0"
    Assert-Contains $realinfo "TESTNET_DRY_RUN_BROADCAST=0"
    Assert-Contains $realinfo "TESTNET_DRY_RUN_OUTPUT=HOST_INTENT_ONLY_NO_DEVICE_SIGNATURE"
    Assert-Contains $realinfo "BLOCKER_TESTNET_REGRESSION=0"
    Assert-Contains $realinfo "NEXT_SAFE_STAGE="
    Write-Host "C8_1_REALINFO_WATCH_ONLY_PASS"

    Write-Host ""
    Write-Host "--- C8.1 VERSION/POLICY WATCH-ONLY LABELS ---"
    $version = Send-CommandLines -Serial $serial -Lines @("VERSION") -RequiredPattern "TESTNET_WATCH_ONLY_DRY_RUN_SUPPORTED=1" -TimeoutSeconds $TimeoutSeconds
    Write-Host $version
    Assert-Contains $version "REAL_BITCOIN_STAGE="
    Assert-Contains $version "REAL_BITCOIN_SIGNING_ENABLED=0"
    Assert-Contains $version "TESTNET_SIGNING_ENABLED=0"
    Assert-Contains $version "TESTNET_DRY_RUN_SIGNING_ENABLED=0"

    $policy = Send-CommandLines -Serial $serial -Lines @("POLICYINFO") -RequiredPattern "TESTNET_WATCH_ONLY_DRY_RUN_SUPPORTED=1" -TimeoutSeconds $TimeoutSeconds
    Write-Host $policy
    Assert-Contains $policy "REAL_BITCOIN_STAGE="
    Assert-Contains $policy "NETWORK_ALLOWED=REGTEST"
    Assert-Contains $policy "REAL_BITCOIN_SIGNING_ENABLED=0"
    Assert-Contains $policy "TESTNET_SIGNING_ENABLED=0"
    Assert-Contains $policy "TESTNET_DRY_RUN_SIGNING_ENABLED=0"
    Write-Host "C8_1_VERSION_POLICY_WATCH_ONLY_PASS"

    Write-Host ""
    Write-Host "--- C8.1 DEVICE IDENTITY FOR WATCH-ONLY HOST INTENT ---"
    $identity = Send-CommandLines -Serial $serial -Lines @("IDENTITY") -RequiredPattern "OK IDENTITY" -TimeoutSeconds $TimeoutSeconds
    Write-Host $identity
    $pubkey = Get-Field -Text $identity -Name "PUBKEY_COMPRESSED"
    $script = Get-Field -Text $identity -Name "SCRIPT_P2PKH"
    $keyModel = Get-Field -Text $identity -Name "CURRENT_BITCOIN_KEY_MODEL"

    Write-Host ""
    Write-Host "TESTNET_DRY_RUN_BEGIN"
    Write-Host "TESTNET_DRY_RUN_VERSION=C8.1_TESTNET_WATCH_ONLY_DRY_RUN_V1"
    Write-Host "NETWORK=TESTNET"
    Write-Host "WATCH_ONLY=1"
    Write-Host "DEVICE_SIGNATURE_ALLOWED=0"
    Write-Host "BROADCAST_ALLOWED=0"
    Write-Host "DEVICE_PUBKEY_COMPRESSED=$pubkey"
    Write-Host "DEVICE_SCRIPT_P2PKH=$script"
    Write-Host "DEVICE_KEY_MODEL=$keyModel"
    Write-Host "TESTNET_DRY_RUN_END"
    Write-Host "C8_1_HOST_TESTNET_WATCH_ONLY_TRANSCRIPT_PASS"

    $authAfterManifest = Get-AuthCount -Serial $serial
    Assert-AuthUnchanged -Before $authBefore -After $authAfterManifest -Name "C8_1_MANIFEST_AND_IDENTITY"

    Close-WalletSerial -Serial $serial
    $serial = $null

    Invoke-HostTestnetDryRunReject

    $serial = Open-WalletSerial -Port $Port -Baud $Baud
    $authAfterHost = Get-AuthCount -Serial $serial
    Assert-AuthUnchanged -Before $authAfterManifest -After $authAfterHost -Name "C8_1_HOST_TESTNET_DRY_RUN"

    Write-Host ""
    Write-Host "C8_1_TESTNET_WATCH_ONLY_DRY_RUN_REGRESSION_PASS"
    exit 0
}
finally {
    Close-WalletSerial -Serial $serial
}
