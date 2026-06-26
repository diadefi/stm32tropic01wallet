param(
    [string]$Port = "COM3"
)

$ErrorActionPreference = "Stop"

function Read-SerialForSeconds {
    param(
        [System.IO.Ports.SerialPort]$Serial,
        [int]$Seconds = 3
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    $text = ""

    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 100
        $chunk = $Serial.ReadExisting()
        if ($chunk.Length -gt 0) {
            $text += $chunk
        }
    }

    return $text
}

function Send-ProbeCommand {
    param(
        [System.IO.Ports.SerialPort]$Serial,
        [string]$Command,
        [string]$Expected
    )

    Write-Host ""
    Write-Host "--- UART $Command ---"

    $Serial.Write("$Command`r`n")
    $out = Read-SerialForSeconds -Serial $Serial -Seconds 3

    Write-Host $out

    if ($out -notmatch [regex]::Escape($Expected)) {
        throw "$Command probe failed. Expected $Expected"
    }
}

$sp = New-Object System.IO.Ports.SerialPort $Port, 115200, None, 8, One
$sp.DtrEnable = $false
$sp.RtsEnable = $false
$sp.ReadTimeout = 500
$sp.WriteTimeout = 2000

try {
    Write-Host "--- OPEN SERIAL $Port ---"
    $sp.Open()

    Start-Sleep -Seconds 2
    $startup = $sp.ReadExisting()

    Write-Host ""
    Write-Host "--- UART STARTUP ---"
    Write-Host $startup

    Send-ProbeCommand -Serial $sp -Command "VERSION"    -Expected "OK VERSION"
    Send-ProbeCommand -Serial $sp -Command "POLICYINFO" -Expected "OK POLICYINFO"
    Send-ProbeCommand -Serial $sp -Command "SEINFO"     -Expected "OK SEINFO"
    Send-ProbeCommand -Serial $sp -Command "SEKEYINFO"  -Expected "OK SEKEYINFO"

    Write-Host ""
    Write-Host "UART_PROBE_PASS"
}
finally {
    if ($sp.IsOpen) {
        $sp.Close()
    }
}

