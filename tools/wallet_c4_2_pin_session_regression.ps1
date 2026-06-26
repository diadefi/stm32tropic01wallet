param(
    [string]$Port = "COM3",
    [int]$Baud = 115200,
    [string]$Generator = ".\tools\wallet_generate_tx_command.ps1",
    [int]$TimeoutSeconds = 30
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
        Start-Sleep -Milliseconds 80
    }

    $buf = ""
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)

    while ([DateTime]::UtcNow -lt $deadline) {
        $buf += Read-Available -Serial $Serial
        if (($buf -match $RequiredPattern) -and ($buf -match "READY")) {
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

function Get-AuthCount {
    param([string]$Text)
    $m = [regex]::Match($Text, "AUTH_COUNT=(\d+)")
    if (-not $m.Success) {
        throw "AUTH_COUNT missing"
    }
    return [int]$m.Groups[1].Value
}

$legacySecretSign = @(
    "UNLOCK_SECRET=mvp-regtest-unlock",
    "SIGN"
)

$serial = $null
try {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host " STM32 C4.2 PIN SESSION REGRESSION"
    Write-Host "============================================================"
    Write-Host "Port: $Port"

    $serial = New-Object System.IO.Ports.SerialPort
    $serial.PortName = $Port
    $serial.BaudRate = $Baud
    $serial.Parity = [System.IO.Ports.Parity]::None
    $serial.DataBits = 8
    $serial.StopBits = [System.IO.Ports.StopBits]::One
    $serial.Handshake = [System.IO.Ports.Handshake]::None
    $serial.ReadTimeout = 200
    $serial.WriteTimeout = 2000
    $serial.NewLine = "`n"
    $serial.DtrEnable = $true
    $serial.RtsEnable = $true
    $serial.Open()

    Start-Sleep -Milliseconds 1500
    Drain-Stale -Serial $serial

    Write-Host ""
    Write-Host "--- C4.2 POLICYINFO PIN SESSION FIELDS ---"
    $policy = Send-CommandLines -Serial $serial -Lines @("POLICYINFO") -RequiredPattern "UNLOCK_MODEL=PIN_SESSION_C4.2" -TimeoutSeconds $TimeoutSeconds
    Write-Host $policy
    Assert-Contains $policy "ERR_PIN_LOCKED=-61"
    Assert-Contains $policy "ERR_PIN_SESSION_EXPIRED=-62"
    Assert-Contains $policy "ERR_HOST_UNLOCK_SECRET_DISABLED=-24"
    Assert-Contains $policy "PIN_SESSION_TIMEOUT_MS=30000"
    Write-Host "C4_2_POLICYINFO_PIN_SESSION_PASS"

    Write-Host ""
    Write-Host "--- C4.2 INITIAL UNLOCKINFO LOCKED ---"
    $lock = Send-CommandLines -Serial $serial -Lines @("LOCK") -RequiredPattern "OK LOCK" -TimeoutSeconds $TimeoutSeconds
    Write-Host $lock
    $info0 = Send-CommandLines -Serial $serial -Lines @("UNLOCKINFO") -RequiredPattern "OK UNLOCKINFO" -TimeoutSeconds $TimeoutSeconds
    Write-Host $info0
    Assert-Contains $info0 "PIN_SESSION_UNLOCKED=0"
    Write-Host "C4_2_UNLOCKINFO_LOCKED_PASS"

    Write-Host ""
    Write-Host "--- C4.2 WRONG PIN REJECTS WITHOUT TROPIC AUTH ---"
    $before = Send-CommandLines -Serial $serial -Lines @("SEINFO") -RequiredPattern "OK SEINFO" -TimeoutSeconds $TimeoutSeconds
    $authBefore = Get-AuthCount $before
    $wrong = Send-CommandLines -Serial $serial -Lines @("UNLOCK_PIN=000000") -RequiredPattern "ERR KEYPROVIDER -23" -TimeoutSeconds $TimeoutSeconds
    Write-Host $wrong
    Assert-Contains $wrong "ERR KEYPROVIDER -23"
    Assert-NoRawTx $wrong "WRONG_PIN"
    $after = Send-CommandLines -Serial $serial -Lines @("SEINFO") -RequiredPattern "OK SEINFO" -TimeoutSeconds $TimeoutSeconds
    $authAfter = Get-AuthCount $after
    if ($authBefore -ne $authAfter) {
        throw "WRONG_PIN changed AUTH_COUNT"
    }
    Write-Host "C4_2_WRONG_PIN_NO_AUTH_PASS"

    Write-Host ""
    Write-Host "--- C4.2 LEGACY UNLOCK_SECRET REJECTED ---"
    $legacy = Send-CommandLines -Serial $serial -Lines $legacySecretSign -RequiredPattern "ERR KEYPOLICY -24" -TimeoutSeconds $TimeoutSeconds
    Write-Host $legacy
    Assert-Contains $legacy "ERR KEYPOLICY -24"
    Assert-NoRawTx $legacy "LEGACY_UNLOCK_SECRET"
    Write-Host "C4_2_LEGACY_UNLOCK_SECRET_DISABLED_PASS"

    Write-Host ""
    Write-Host "--- C4.2 POSITIVE PIN SESSION SIGN VIA HOST GENERATOR ---"
    if ($serial.IsOpen) { $serial.Close() }
    $generatorOutput = & powershell.exe `
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
    $generatorText = ($generatorOutput | Out-String)
    Write-Host $generatorText

    if ($code -ne 0) {
        throw "C4.2 generator positive flow failed with exit code $code"
    }

    Assert-Contains $generatorText "DEVICE_PIN_SESSION_UNLOCK_PASS"
    Assert-Contains $generatorText "UNLOCK_SECRET_PRESENT=0"
    Assert-Contains $generatorText "HOST_TX_GENERATOR_PASS"
    Write-Host "C4_2_PIN_SESSION_SIGN_PASS"

    Write-Host ""
    Write-Host "C4_2_PIN_SESSION_REGRESSION_PASS"
    $global:LASTEXITCODE = 0
}
finally {
    if ($serial -ne $null) {
        if ($serial.IsOpen) { $serial.Close() }
        $serial.Dispose()
    }
}
