param(
    [string]$Port = "COM3",
    [string]$BitcoinCli = "C:\Program Files\Bitcoin\daemon\bitcoin-cli.exe",
    [string]$Wallet = "stm32-host-live",
    [string]$CubeIdeCli = "C:\ST\STM32CubeIDE_2.1.1\STM32CubeIDE\stm32cubeidec.exe",
    [string]$CubeWorkspace = "C:\Users\mando\OneDrive\Desktop\newstm32",
    [string]$ProjectRoot = "C:\Users\mando\OneDrive\Desktop\newstm32\HardwarePrototype",
    [string]$ProgrammerCli = "C:\ST\STM32CubeIDE_2.1.1\STM32CubeIDE\plugins\com.st.stm32cube.ide.mcu.externaltools.cubeprogrammer.win32_2.2.400.202601091506\tools\bin\STM32_Programmer_CLI.exe",
    [string]$BackupRoot = "C:\stm32_backups",
    [int]$MasterRetries = 1,
    [switch]$SkipBuild,
    [switch]$SkipFlash,
    [switch]$SkipBackup,
    [switch]$AppendStatus
)

$ErrorActionPreference = "Stop"

function New-CiTimestamp {
    return (Get-Date).ToString("yyyyMMdd_HHmmss")
}

function Write-LogLine {
    param(
        [string]$Text,
        [string]$LogPath
    )

    Write-Host $Text
    Add-Content -Path $LogPath -Value $Text
}

function Invoke-LoggedExternal {
    param(
        [string]$Name,
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$LogPath
    )

    Write-LogLine "" $LogPath
    Write-LogLine "============================================================" $LogPath
    Write-LogLine "RUN $Name" $LogPath
    Write-LogLine "============================================================" $LogPath
    Write-LogLine "COMMAND=$FilePath $($Arguments -join ' ')" $LogPath

    & $FilePath @Arguments 2>&1 | Tee-Object -FilePath $LogPath -Append
    $code = $LASTEXITCODE

    if ($code -ne 0) {
        throw "$Name failed with exit code $code"
    }

    Write-LogLine "" $LogPath
    Write-LogLine "PASS $Name" $LogPath
}

function Invoke-LoggedPowerShellScript {
    param(
        [string]$Name,
        [string]$ScriptPath,
        [string[]]$Arguments,
        [string]$LogPath
    )

    if (-not (Test-Path -Path $ScriptPath)) {
        throw "$Name script not found: $ScriptPath"
    }

    Invoke-LoggedExternal `
        -Name $Name `
        -FilePath "powershell.exe" `
        -Arguments (@("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $ScriptPath) + $Arguments) `
        -LogPath $LogPath
}

function Invoke-BoardReset {
    param(
        [string]$Name,
        [string]$ProgrammerCli,
        [string]$LogPath
    )

    if (-not (Test-Path -Path $ProgrammerCli)) {
        throw "STM32_Programmer_CLI not found for reset: $ProgrammerCli"
    }

    Invoke-LoggedExternal `
        -Name $Name `
        -FilePath $ProgrammerCli `
        -Arguments @("-c", "port=SWD", "mode=UR", "reset=HWrst", "-rst") `
        -LogPath $LogPath

    Start-Sleep -Seconds 2
}

function Invoke-MasterRegressionWithRetry {
    param(
        [string]$ScriptPath,
        [string[]]$Arguments,
        [string]$ProgrammerCli,
        [int]$Retries,
        [string]$LogPath
    )

    $attempt = 0

    while ($true) {
        try {
            Invoke-LoggedPowerShellScript `
                -Name "MASTER_REGRESSION_ATTEMPT_$($attempt + 1)" `
                -ScriptPath $ScriptPath `
                -Arguments $Arguments `
                -LogPath $LogPath
            return
        }
        catch {
            if ($attempt -ge $Retries) {
                throw
            }

            Write-LogLine "MASTER_REGRESSION_RETRY_AFTER_FAILURE=$($_.Exception.Message)" $LogPath
            Invoke-BoardReset `
                -Name "RESET_BEFORE_MASTER_RETRY_$($attempt + 1)" `
                -ProgrammerCli $ProgrammerCli `
                -LogPath $LogPath
            $attempt++
        }
    }
}

function Copy-ProjectBackup {
    param(
        [string]$Source,
        [string]$Destination,
        [string]$LogPath
    )

    if (Test-Path -LiteralPath $Destination) {
        throw "Backup already exists: $Destination"
    }

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Copy-Item -Path (Join-Path $Source "*") -Destination $Destination -Recurse -Force

    if (-not (Test-Path -LiteralPath (Join-Path $Destination "PROJECT_STATUS.md"))) {
        throw "Backup verification failed: missing PROJECT_STATUS.md"
    }

    Write-LogLine "BACKUP_CREATED=$Destination" $LogPath
}

function Add-StatusNote {
    param(
        [string]$StatusPath,
        [string]$BackupPath,
        [string]$LogPath
    )

    $note = @"

## C6.2 one-command hardware CI harness - PASS

Date: $(Get-Date -Format yyyy-MM-dd)

Milestone:

C6_2_HARDWARE_CI_ALL_PASS

What changed:

- Added tools/wallet_hardware_ci.ps1 as the one-command hardware loop.
- The harness can clean/build firmware with STM32CubeIDE headless, flash with STM32_Programmer_CLI, probe UART, run focused C6.0/C6.1 protocol checks, run the full master regression suite, save a timestamped log, and create a milestone backup.
- The harness supports SkipBuild, SkipFlash, SkipBackup, and AppendStatus options for repeated hardware runs.

Passing proof:

- WALLET_HARDWARE_CI_PASS
- Full automated master regression passed with ALL_REGRESSIONS_PASS.

Log:

$LogPath

Backup:

$BackupPath
"@

    Add-Content -Path $StatusPath -Value $note
    Write-LogLine "PROJECT_STATUS_APPENDED=$StatusPath" $LogPath
}

$timestamp = New-CiTimestamp
$logDir = Join-Path $ProjectRoot "logs"
$logPath = Join-Path $logDir "wallet_hardware_ci_$timestamp.log"
$backupPath = Join-Path $BackupRoot "HardwarePrototype_C6_2_HARDWARE_CI_ALL_PASS"
$elfPath = Join-Path $ProjectRoot "Debug\HardwarePrototype.elf"

New-Item -ItemType Directory -Path $logDir -Force | Out-Null
Set-Content -Path $logPath -Value ""

Set-Location $ProjectRoot

Write-LogLine "WALLET_HARDWARE_CI_START" $logPath
Write-LogLine "TIMESTAMP=$timestamp" $logPath
Write-LogLine "PROJECT_ROOT=$ProjectRoot" $logPath
Write-LogLine "PORT=$Port" $logPath
Write-LogLine "BITCOIN_CLI=$BitcoinCli" $logPath
Write-LogLine "WALLET=$Wallet" $logPath
Write-LogLine "MASTER_RETRIES=$MasterRetries" $logPath

if (-not (Test-Path -Path $ProjectRoot)) {
    throw "Project root not found: $ProjectRoot"
}

if (-not $SkipBuild) {
    if (-not (Test-Path -Path $CubeIdeCli)) {
        throw "STM32CubeIDE CLI not found: $CubeIdeCli"
    }

    Invoke-LoggedExternal `
        -Name "CLEAN_BUILD_FIRMWARE" `
        -FilePath $CubeIdeCli `
        -Arguments @(
            "-nosplash",
            "-application", "org.eclipse.cdt.managedbuilder.core.headlessbuild",
            "-data", $CubeWorkspace,
            "-import", $ProjectRoot,
            "-cleanBuild", "HardwarePrototype/Debug"
        ) `
        -LogPath $logPath
}
else {
    Write-LogLine "SKIP_BUILD=1" $logPath
}

if (-not (Test-Path -Path $elfPath)) {
    throw "Firmware ELF not found after build/skip-build: $elfPath"
}

if (-not $SkipFlash) {
    if (-not (Test-Path -Path $ProgrammerCli)) {
        throw "STM32_Programmer_CLI not found: $ProgrammerCli"
    }

    Invoke-LoggedExternal `
        -Name "FLASH_FIRMWARE" `
        -FilePath $ProgrammerCli `
        -Arguments @(
            "-c", "port=SWD", "mode=UR", "reset=HWrst",
            "-w", $elfPath,
            "-v",
            "-rst"
        ) `
        -LogPath $logPath
}
else {
    Write-LogLine "SKIP_FLASH=1" $logPath
}

Start-Sleep -Seconds 2

Invoke-LoggedPowerShellScript `
    -Name "UART_PROBE" `
    -ScriptPath ".\tools\wallet_probe_info.ps1" `
    -Arguments @("-Port", $Port) `
    -LogPath $logPath

Invoke-LoggedPowerShellScript `
    -Name "C6_0_C6_1_PROTOCOL" `
    -ScriptPath ".\tools\wallet_c6_0_c6_1_protocol_regression.ps1" `
    -Arguments @("-Port", $Port) `
    -LogPath $logPath

Invoke-BoardReset `
    -Name "RESET_BEFORE_MASTER_REGRESSION" `
    -ProgrammerCli $ProgrammerCli `
    -LogPath $logPath

Invoke-MasterRegressionWithRetry `
    -ScriptPath ".\tools\wallet_run_all_regressions.ps1" `
    -Arguments @("-Port", $Port, "-BitcoinCli", $BitcoinCli, "-Wallet", $Wallet) `
    -ProgrammerCli $ProgrammerCli `
    -Retries $MasterRetries `
    -LogPath $logPath

if (-not $SkipBackup) {
    Copy-ProjectBackup -Source $ProjectRoot -Destination $backupPath -LogPath $logPath
}
else {
    Write-LogLine "SKIP_BACKUP=1" $logPath
}

if ($AppendStatus) {
    Add-StatusNote `
        -StatusPath (Join-Path $ProjectRoot "PROJECT_STATUS.md") `
        -BackupPath ($(if ($SkipBackup) { "SKIPPED" } else { $backupPath })) `
        -LogPath $logPath
}

Write-LogLine "" $logPath
Write-LogLine "WALLET_HARDWARE_CI_PASS" $logPath
Write-LogLine "LOG_PATH=$logPath" $logPath
