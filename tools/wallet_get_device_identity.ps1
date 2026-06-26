param(
    [string]$Port = "COM3",
    [int]$Baud = 115200,
    [int]$TimeoutSeconds = 15
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

function Send-Command {
    param(
        [System.IO.Ports.SerialPort]$Serial,
        [string]$Command,
        [int]$TimeoutSeconds
    )

    $Serial.DiscardInBuffer()
    $Serial.WriteLine($Command)

    $buf = ""
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)

    while ([DateTime]::UtcNow -lt $deadline) {
        $buf += Read-Available -Serial $Serial

        if ($buf -match "READY") {
            return $buf
        }

        Start-Sleep -Milliseconds 50
    }

    throw "Timeout waiting for READY after $Command. Buffer: $buf"
}

function Get-Field {
    param(
        [string]$Text,
        [string]$Name
    )

    $m = [regex]::Match($Text, "(?m)^" + [regex]::Escape($Name) + "=(.+?)\s*$")
    if (-not $m.Success) {
        throw "Missing identity field: $Name"
    }

    return $m.Groups[1].Value.Trim()
}

$serial = $null

try {
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
    Start-Sleep -Milliseconds 1000

    $null = Read-Available -Serial $serial

    # Sync first. The app VERSION string is cosmetic, so do not validate it here.
    $null = Send-Command -Serial $serial -Command "VERSION" -TimeoutSeconds $TimeoutSeconds

    $identity = Send-Command -Serial $serial -Command "IDENTITY" -TimeoutSeconds $TimeoutSeconds

    if ($identity -notmatch "OK IDENTITY") {
        throw "Missing OK IDENTITY"
    }

    $identityVersion = Get-Field -Text $identity -Name "IDENTITY_VERSION"
    $network         = Get-Field -Text $identity -Name "NETWORK"
    $address         = Get-Field -Text $identity -Name "ADDRESS"
    $pubkey          = Get-Field -Text $identity -Name "PUBKEY_COMPRESSED"
    $script          = Get-Field -Text $identity -Name "SCRIPT_P2PKH"
    $keyModel        = Get-Field -Text $identity -Name "CURRENT_BITCOIN_KEY_MODEL"
    $devKey          = Get-Field -Text $identity -Name "CURRENT_DEV_KEY_ENABLED"

    if ($identityVersion -ne "C2.0_DEVICE_IDENTITY_REPORTING") {
        throw "Unexpected IDENTITY_VERSION=$identityVersion"
    }

    if ($network -ne "REGTEST") {
        throw "Unexpected NETWORK=$network"
    }

    if ($devKey -ne "0") {
        throw "Unexpected CURRENT_DEV_KEY_ENABLED=$devKey"
    }

    Write-Host "DEVICE_IDENTITY_VERSION=$identityVersion"
    Write-Host "DEVICE_NETWORK=$network"
    Write-Host "DEVICE_ADDRESS=$address"
    Write-Host "DEVICE_PUBKEY_COMPRESSED=$pubkey"
    Write-Host "DEVICE_SCRIPT_P2PKH=$script"
    Write-Host "DEVICE_KEY_MODEL=$keyModel"
    Write-Host "DEVICE_DEV_KEY_ENABLED=$devKey"
    Write-Host "DEVICE_IDENTITY_GET_PASS"
}
finally {
    if ($serial -ne $null) {
        if ($serial.IsOpen) {
            $serial.Close()
        }
        $serial.Dispose()
    }
}
