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

function Assert-Matches {
    param([string]$Text, [string]$Pattern, [string]$Name)
    if ($Text -notmatch $Pattern) {
        Write-Host ""
        Write-Host "--- TEXT THAT FAILED REGEX ASSERTION ---"
        Write-Host $Text
        throw "Missing expected pattern for ${Name}: $Pattern"
    }
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
    "CHECK"
)

function Invoke-InvalidPsbtLikeCheck {
    param(
        [System.IO.Ports.SerialPort]$Serial,
        [string]$Name,
        [string[]]$Lines,
        [int]$TimeoutSeconds
    )

    Write-Host ""
    Write-Host "--- C5.0.1 INVALID PSBT-LIKE CHECK: $Name ---"
    $response = Send-CommandLines -Serial $Serial -Lines $Lines -RequiredPattern "ERR POLICY -51" -TimeoutSeconds $TimeoutSeconds
    Write-Host $response
    Assert-Contains $response "ERR POLICY -51"
    Assert-NoRawTx $response $Name
    Write-Host "C5_0_1_${Name}_REJECT_PASS"
}

function Set-CommandLine {
    param(
        [string[]]$Lines,
        [string]$Prefix,
        [string]$NewLine
    )

    $copy = @($Lines)
    for ($i = 0; $i -lt $copy.Count; $i++) {
        if ($copy[$i] -match ("^" + [regex]::Escape($Prefix))) {
            $copy[$i] = $NewLine
            return $copy
        }
    }

    throw "Line prefix not found: $Prefix"
}

function Invoke-PolicyRejectCheck {
    param(
        [System.IO.Ports.SerialPort]$Serial,
        [string]$Name,
        [string[]]$Lines,
        [string]$ExpectedError,
        [int]$TimeoutSeconds
    )

    Write-Host ""
    Write-Host "--- C5.2 POLICY CHECK: $Name ---"
    $response = Send-CommandLines -Serial $Serial -Lines $Lines -RequiredPattern ([regex]::Escape($ExpectedError)) -TimeoutSeconds $TimeoutSeconds
    Write-Host $response
    Assert-Contains $response $ExpectedError
    Assert-NoRawTx $response $Name
    Write-Host "C5_2_${Name}_PASS"
}

$serial = $null
try {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host " STM32 C5.0 PSBT-LIKE COMMAND FORMAT REGRESSION"
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
    Write-Host "--- C5.0 POLICYINFO COMMAND FORMAT FIELDS ---"
    $policy = Send-CommandLines -Serial $serial -Lines @("POLICYINFO") -RequiredPattern "COMMAND_FORMAT_PSBT_LIKE=C5.0_PSBT_LIKE_TEXT_V1" -TimeoutSeconds $TimeoutSeconds
    Write-Host $policy
    Assert-Contains $policy "COMMAND_FORMAT_LEGACY=LEGACY_TEXT_V1"
    Assert-Contains $policy "COMMAND_FORMAT_PSBT_LIKE=C5.0_PSBT_LIKE_TEXT_V1"
    Assert-Contains $policy "ERR_FORMAT_INVALID=-51"
    Assert-Contains $policy "DUST_LIMIT_SATS=546"
    Assert-Contains $policy "MAX_FEE_RATE_SATS_PER_KVB=100000"
    Assert-Contains $policy "ERR_DUST_OUTPUT=-52"
    Assert-Contains $policy "MAX_INPUT_COUNT=2"
    Assert-Contains $policy "FEE_RATE_ESTIMATE_2IN_2OUT_VBYTES=340"
    Assert-Contains $policy "ERR_INPUT_COUNT_UNSUPPORTED=-53"
    Assert-Contains $policy "ERR_CHANGE_DERIVATION_INVALID=-54"
    Assert-Contains $policy "CHANGE_DERIVATION_MODEL=FIXED_MVP_SCRIPT_METADATA"
    Assert-Contains $policy "CHANGE_DERIVATION_ALLOWED=mvp-static-change/0"
    Write-Host "C5_0_POLICYINFO_FORMAT_PASS"

    Invoke-InvalidPsbtLikeCheck `
        -Serial $serial `
        -Name "MISSING_FORMAT" `
        -Lines ($validPsbtLikeCheck | Where-Object { $_ -notmatch "^WALLET_CMD_FORMAT=" }) `
        -TimeoutSeconds $TimeoutSeconds

    $wrongInputCount = @($validPsbtLikeCheck)
    $wrongInputCount[2] = "PSBT_INPUT_COUNT=2"
    Invoke-InvalidPsbtLikeCheck `
        -Serial $serial `
        -Name "WRONG_INPUT_COUNT" `
        -Lines $wrongInputCount `
        -TimeoutSeconds $TimeoutSeconds

    $wrongRole = @($validPsbtLikeCheck)
    $wrongRole[8] = "PSBT_OUTPUT0_ROLE=CHANGE"
    Invoke-InvalidPsbtLikeCheck `
        -Serial $serial `
        -Name "WRONG_OUTPUT_ROLE" `
        -Lines $wrongRole `
        -TimeoutSeconds $TimeoutSeconds

    $mixedFields = @("NETWORK=REGTEST") + $validPsbtLikeCheck
    Invoke-InvalidPsbtLikeCheck `
        -Serial $serial `
        -Name "MIXED_LEGACY_FIELDS" `
        -Lines $mixedFields `
        -TimeoutSeconds $TimeoutSeconds

    Write-Host "C5_0_1_STRICT_FORMAT_VALIDATION_PASS"

    $badDerivation = @($validPsbtLikeCheck)
    $badDerivation = $badDerivation[0..($badDerivation.Count - 2)] + @("PSBT_OUTPUT1_DERIVATION=wrong-change-path", "CHECK")
    Write-Host ""
    Write-Host "--- C5.3A CHANGE DERIVATION METADATA REJECT ---"
    $badDerivationResponse = Send-CommandLines -Serial $serial -Lines $badDerivation -RequiredPattern "ERR POLICY -54" -TimeoutSeconds $TimeoutSeconds
    Write-Host $badDerivationResponse
    Assert-Contains $badDerivationResponse "ERR POLICY -54"
    Assert-NoRawTx $badDerivationResponse "CHANGE_DERIVATION_INVALID_REJECT"
    Write-Host "C5_3_CHANGE_DERIVATION_INVALID_REJECT_PASS"

    $dustPay = Set-CommandLine -Lines $validPsbtLikeCheck -Prefix "PSBT_OUTPUT0_SATS=" -NewLine "PSBT_OUTPUT0_SATS=500"
    Invoke-PolicyRejectCheck `
        -Serial $serial `
        -Name "PAYMENT_DUST_REJECT" `
        -Lines $dustPay `
        -ExpectedError "ERR POLICY -52" `
        -TimeoutSeconds $TimeoutSeconds

    $dustChange = Set-CommandLine -Lines $validPsbtLikeCheck -Prefix "PSBT_OUTPUT1_SATS=" -NewLine "PSBT_OUTPUT1_SATS=500"
    Invoke-PolicyRejectCheck `
        -Serial $serial `
        -Name "CHANGE_DUST_REJECT" `
        -Lines $dustChange `
        -ExpectedError "ERR POLICY -52" `
        -TimeoutSeconds $TimeoutSeconds

    $feeRate = Set-CommandLine -Lines $validPsbtLikeCheck -Prefix "PSBT_OUTPUT1_SATS=" -NewLine "PSBT_OUTPUT1_SATS=20000"
    Invoke-PolicyRejectCheck `
        -Serial $serial `
        -Name "FEE_RATE_REJECT" `
        -Lines $feeRate `
        -ExpectedError "ERR POLICY -35" `
        -TimeoutSeconds $TimeoutSeconds

    Write-Host "C5_2_OUTPUT_POLICY_EXPANSION_PASS"

    if ($serial.IsOpen) { $serial.Close() }

    Write-Host ""
    Write-Host "--- C5.0 POSITIVE PSBT-LIKE SIGN VIA HOST GENERATOR ---"
    $generatorOutput = & powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $Generator `
        -Port $Port `
        -CommandFormat PsbtLike `
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
        throw "C5.0 PSBT-like generator flow failed with exit code $code"
    }

    Assert-Contains $generatorText "COMMAND_FORMAT=PsbtLike"
    Assert-Contains $generatorText "WALLET_CMD_FORMAT=C5.0_PSBT_LIKE_TEXT_V1"
    Assert-Contains $generatorText "PSBT_INPUT_COUNT=1"
    Assert-Contains $generatorText "PSBT_OUTPUT_COUNT=2"
    Assert-Contains $generatorText "DEVICE_CHECK_BEFORE_SIGN_PASS"
    Assert-Contains $generatorText "DEVICE_CONFIRM_BEFORE_SIGN_PASS"
    Assert-Contains $generatorText "HOST_TX_GENERATOR_PASS"
    Assert-Contains $generatorText "RAW_TX_PRESENT=1"
    Write-Host "C5_0_PSBT_LIKE_SIGN_PASS"

    Write-Host ""
    Write-Host "--- C5.1 POSITIVE TWO-INPUT PSBT-LIKE SIGN VIA HOST GENERATOR ---"
    $twoInputOutput = & powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $Generator `
        -Port $Port `
        -CommandFormat PsbtLike `
        -InputCount 2 `
        -TxidLe "09f6ce894fc3f8c5de72f787386039a54eeb2aded45b4087fc0992e40023a632" `
        -Vout 1 `
        -InputSats 100000 `
        -TxidLe1 "19f6ce894fc3f8c5de72f787386039a54eeb2aded45b4087fc0992e40023a633" `
        -Vout1 0 `
        -InputSats1 50000 `
        -PaySats 60000 `
        -ChangeSats 80000 `
        -ChangeDerivation "mvp-static-change/0" `
        -TimeoutSeconds 180 `
        2>&1

    $twoInputCode = $LASTEXITCODE
    $twoInputText = ($twoInputOutput | Out-String)
    Write-Host $twoInputText

    if ($twoInputCode -ne 0) {
        throw "C5.1 two-input PSBT-like generator flow failed with exit code $twoInputCode"
    }

    Assert-Contains $twoInputText "INPUT_COUNT=2"
    Assert-Contains $twoInputText "INPUT1_SATS=50000"
    Assert-Contains $twoInputText "TOTAL_INPUT_SATS=150000"
    Assert-Contains $twoInputText "CHANGE_DERIVATION=mvp-static-change/0"
    Assert-Contains $twoInputText "DEVICE_CHECK_BEFORE_SIGN_PASS"
    Assert-Contains $twoInputText "DEVICE_CONFIRM_BEFORE_SIGN_PASS"
    Assert-Contains $twoInputText "HOST_TX_GENERATOR_PASS"
    Assert-Contains $twoInputText "RAW_TX_PRESENT=1"
    Assert-Matches $twoInputText "(?m)^RAW_TX=0100000002[0-9a-fA-F]+" "two-input RAW_TX input count"
    Write-Host "C5_1_TWO_INPUT_PSBT_LIKE_SIGN_PASS"
    Write-Host "C5_3_CHANGE_DERIVATION_METADATA_PASS"

    Write-Host ""
    Write-Host "C5_0_PSBT_LIKE_FORMAT_REGRESSION_PASS"
    $global:LASTEXITCODE = 0
}
finally {
    if ($serial -ne $null) {
        if ($serial.IsOpen) { $serial.Close() }
        $serial.Dispose()
    }
}
