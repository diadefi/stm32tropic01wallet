param(
    [string]$Port = "COM3",
    [int]$Baud = 115200,
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

function Get-Crc32Hex {
    param([string]$Text)

    $crc = [uint32]::MaxValue
    $poly = [uint32]::Parse("EDB88320", [System.Globalization.NumberStyles]::HexNumber)
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($Text)

    foreach ($b in $bytes) {
        $crc = [uint32]($crc -bxor [uint32]$b)
        for ($i = 0; $i -lt 8; $i++) {
            if (($crc -band 1) -ne 0) {
                $crc = [uint32](($crc -shr 1) -bxor $poly)
            } else {
                $crc = [uint32]($crc -shr 1)
            }
        }
    }

    $crc = [uint32]($crc -bxor [uint32]::MaxValue)
    return "{0:x8}" -f $crc
}

function New-TextFrame {
    param(
        [string[]]$PayloadLines,
        [string]$Version = "C6.1_TEXT_FRAME_V1",
        [Nullable[int]]$LenOverride = $null,
        [string]$CrcOverride = $null
    )

    $payload = ($PayloadLines -join "`n") + "`n"
    $payloadLen = [System.Text.Encoding]::ASCII.GetByteCount($payload)
    $crc = Get-Crc32Hex -Text $payload

    if ($LenOverride -ne $null) {
        $payloadLen = [int]$LenOverride
    }

    if ($CrcOverride) {
        $crc = $CrcOverride
    }

    return @(
        "FRAME_BEGIN",
        "FRAME_VERSION=$Version",
        "FRAME_LEN=$payloadLen",
        "FRAME_CRC32=$crc",
        "FRAME_PAYLOAD_BEGIN"
    ) + $PayloadLines + @(
        "FRAME_PAYLOAD_END",
        "FRAME_END"
    )
}

$validPsbtLikeCheck = @(
    "WALLET_CMD_FORMAT=C5.0_PSBT_LIKE_TEXT_V1",
    "PSBT_GLOBAL_NETWORK=REGTEST",
    "PSBT_INPUT_COUNT=1",
    "PSBT_INPUT0_TXID_LE=09f6ce894fc3f8c5de72f787386039a54eeb2aded45b4087fc0992e40023a632",
    "PSBT_INPUT0_VOUT=1",
    "PSBT_INPUT0_SATS=100000",
    "PSBT_INPUT0_PREV_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
    "PSBT_OUTPUT_COUNT=2",
    "PSBT_OUTPUT0_ROLE=PAYMENT",
    "PSBT_OUTPUT0_SCRIPT=76a914f2124d94cabdb95d49479627cbbe5d7be609f73888ac",
    "PSBT_OUTPUT0_SATS=60000",
    "PSBT_OUTPUT1_ROLE=CHANGE",
    "PSBT_OUTPUT1_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
    "PSBT_OUTPUT1_SATS=30000",
    "PSBT_OUTPUT1_DERIVATION=mvp-static-change/0",
    "CHECK"
)

$badPayCheck = @($validPsbtLikeCheck)
$badPayCheck[9] = "PSBT_OUTPUT0_SCRIPT=76a914111111111111111111111111111111111111111188ac"

$serial = $null
try {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host " STM32 C6.0/C6.1 VERSIONED FRAMED PROTOCOL REGRESSION"
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
    Write-Host "--- C6.0 VERSION FIELDS ---"
    $version = Send-CommandLines -Serial $serial -Lines @("VERSION") -RequiredPattern "PROTOCOL_VERSION=C6\.0_TEXT_PROTOCOL_V1" -TimeoutSeconds $TimeoutSeconds
    Write-Host $version
    Assert-Contains $version "COMMAND_VERSION=C6.0_COMMAND_FIELDS_V1"
    Assert-Contains $version "RESPONSE_VERSION=C6.0_RESPONSE_FIELDS_V1"
    Assert-Contains $version "ERROR_VERSION=C6.0_ERROR_FIELDS_V1"
    Assert-Contains $version "POLICY_VERSION=C6.0_POLICY_LABELS_V1"
    Assert-Contains $version "FRAME_VERSION=C6.1_TEXT_FRAME_V1"
    Write-Host "C6_0_VERSIONED_PROTOCOL_FIELDS_PASS"

    Write-Host ""
    Write-Host "--- C6.1 FRAMEINFO ---"
    $frameInfo = Send-CommandLines -Serial $serial -Lines @("FRAMEINFO") -RequiredPattern "OK FRAMEINFO" -TimeoutSeconds $TimeoutSeconds
    Write-Host $frameInfo
    Assert-Contains $frameInfo "FRAME_VERSION=C6.1_TEXT_FRAME_V1"
    Assert-Contains $frameInfo "FRAME_CRC=CRC32_IEEE"
    Assert-Contains $frameInfo "FRAME_MAX_PAYLOAD=1200"
    Assert-Contains $frameInfo "ERR_FRAME_LEN=-71"
    Assert-Contains $frameInfo "ERR_FRAME_CRC=-72"
    Write-Host "C6_1_FRAMEINFO_PASS"

    Write-Host ""
    Write-Host "--- C6.1 FRAMED POLICYINFO ---"
    $policyFrame = New-TextFrame -PayloadLines @("POLICYINFO")
    $policy = Send-CommandLines -Serial $serial -Lines $policyFrame -RequiredPattern "OK POLICYINFO" -TimeoutSeconds $TimeoutSeconds
    Write-Host $policy
    Assert-Contains $policy "COMMAND_FORMAT_FRAMED_TEXT=C6.1_TEXT_FRAME_V1"
    Assert-Contains $policy "ERR_FRAME_INVALID=-70"
    Assert-Contains $policy "ERR_FRAME_UNSUPPORTED=-73"
    Write-Host "C6_1_FRAMED_POLICYINFO_PASS"

    Write-Host ""
    Write-Host "--- C6.1 INVALID FRAME LENGTH REJECT ---"
    $badLenFrame = New-TextFrame -PayloadLines @("POLICYINFO") -LenOverride 999
    $badLen = Send-CommandLines -Serial $serial -Lines $badLenFrame -RequiredPattern "ERR FRAME -71" -TimeoutSeconds $TimeoutSeconds
    Write-Host $badLen
    Assert-Contains $badLen "ERROR_VERSION=C6.0_ERROR_FIELDS_V1"
    Write-Host "C6_1_FRAME_LEN_REJECT_PASS"

    Write-Host ""
    Write-Host "--- C6.1 INVALID FRAME CRC REJECT ---"
    $badCrcFrame = New-TextFrame -PayloadLines @("POLICYINFO") -CrcOverride "deadbeef"
    $badCrc = Send-CommandLines -Serial $serial -Lines $badCrcFrame -RequiredPattern "ERR FRAME -72" -TimeoutSeconds $TimeoutSeconds
    Write-Host $badCrc
    Assert-Contains $badCrc "ERROR_VERSION=C6.0_ERROR_FIELDS_V1"
    Write-Host "C6_1_FRAME_CRC_REJECT_PASS"

    Write-Host ""
    Write-Host "--- C6.1 UNSUPPORTED FRAME VERSION REJECT ---"
    $badVersionFrame = New-TextFrame -PayloadLines @("POLICYINFO") -Version "C6.1_UNKNOWN_FRAME_V1"
    $badVersion = Send-CommandLines -Serial $serial -Lines $badVersionFrame -RequiredPattern "ERR FRAME -73" -TimeoutSeconds $TimeoutSeconds
    Write-Host $badVersion
    Assert-Contains $badVersion "ERROR_VERSION=C6.0_ERROR_FIELDS_V1"
    Write-Host "C6_1_FRAME_UNSUPPORTED_REJECT_PASS"

    Write-Host ""
    Write-Host "--- C6.1 FRAMED PSBT-LIKE CHECK ---"
    $checkFrame = New-TextFrame -PayloadLines $validPsbtLikeCheck
    $check = Send-CommandLines -Serial $serial -Lines $checkFrame -RequiredPattern "POLICY_DECISION=APPROVED" -TimeoutSeconds $TimeoutSeconds
    Write-Host $check
    Assert-Contains $check "SUMMARY_BEGIN"
    Assert-Contains $check "RESPONSE_VERSION=C6.0_RESPONSE_FIELDS_V1"
    Assert-Contains $check "CHECK_ID="
    Assert-Contains $check "SIGNATURE_PRODUCED=0"
    Assert-NoRawTx $check "FRAMED_CHECK"
    Write-Host "C6_1_FRAMED_CHECK_PASS"

    Write-Host ""
    Write-Host "--- C6.1 FAILED CHECK CLEARS PENDING APPROVAL ---"
    $badCheckFrame = New-TextFrame -PayloadLines $badPayCheck
    $badCheck = Send-CommandLines -Serial $serial -Lines $badCheckFrame -RequiredPattern "ERR POLICY -38" -TimeoutSeconds $TimeoutSeconds
    Write-Host $badCheck
    Assert-Contains $badCheck "POLICY_DECISION=REJECTED"
    Assert-NoRawTx $badCheck "FRAMED_BAD_CHECK"
    Write-Host "C6_1_FRAMED_FAILED_CHECK_CLEARS_PENDING_PASS"

    Write-Host ""
    Write-Host "C6_0_C6_1_PROTOCOL_REGRESSION_PASS"
}
finally {
    if ($serial -ne $null) {
        if ($serial.IsOpen) {
            $serial.Close()
        }
        $serial.Dispose()
    }
}
