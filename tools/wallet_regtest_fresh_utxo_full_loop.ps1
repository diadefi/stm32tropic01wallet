param(
    [string]$BitcoinCli = "C:\Program Files\Bitcoin\daemon\bitcoin-cli.exe",
    [string]$Wallet = "regtest-host"
)

$ErrorActionPreference = "Stop"

$stm32Addr = "mrCDrCybB6J1vRfbwM5hemdJz73FwDBC8r"
$ownScript = "76a914751e76e8199196d454941c45d1b3a323f1433bd688ac"

function Invoke-Btc {
    param([string[]]$ArgsList)

    $out = & $BitcoinCli @ArgsList 2>&1
    $code = $LASTEXITCODE

    if ($code -ne 0) {
        Write-Host ""
        Write-Host "BITCOIN_CLI_FAILED:"
        Write-Host ("bitcoin-cli " + ($ArgsList -join " "))
        Write-Host $out
        throw "bitcoin-cli failed with exit code $code"
    }

    return $out
}

function Convert-TxidToLittleEndianHex {
    param([string]$Txid)

    if ($Txid.Length -ne 64) {
        throw "TXID must be 64 hex chars"
    }

    $pairs = @()

    for ($i = 0; $i -lt $Txid.Length; $i += 2) {
        $pairs += $Txid.Substring($i, 2)
    }

    [array]::Reverse($pairs)
    return ($pairs -join "")
}

Write-Host ""
Write-Host "--- CHECK REGTEST NODE ---"
$info = Invoke-Btc -ArgsList @("-regtest", "getblockchaininfo")
$info | Write-Host

Write-Host ""
Write-Host "--- CREATE OR LOAD WALLET ---"

$loadedWallets = Invoke-Btc -ArgsList @("-regtest", "listwallets") | ConvertFrom-Json

if ($loadedWallets -contains $Wallet) {
    Write-Host "Wallet already loaded: $Wallet"
} else {
    $walletDir = Invoke-Btc -ArgsList @("-regtest", "listwalletdir") | ConvertFrom-Json
    $walletExists = $false

    foreach ($w in $walletDir.wallets) {
        if ($w.name -eq $Wallet) {
            $walletExists = $true
        }
    }

    if ($walletExists) {
        Write-Host "Loading wallet: $Wallet"
        Invoke-Btc -ArgsList @("-regtest", "loadwallet", $Wallet) | Write-Host
    } else {
        Write-Host "Creating wallet: $Wallet"
        Invoke-Btc -ArgsList @("-regtest", "createwallet", $Wallet) | Write-Host
    }
}

Write-Host ""
Write-Host "--- ENSURE SPENDABLE FUNDS ---"

$balanceText = Invoke-Btc -ArgsList @("-regtest", "-rpcwallet=$Wallet", "getbalance")
$balance = [decimal](($balanceText | Out-String).Trim())

Write-Host "BALANCE=$balance"

if ($balance -lt 1.0) {
    Write-Host "Mining 101 blocks for mature regtest funds..."
    $mineAddr = Invoke-Btc -ArgsList @("-regtest", "-rpcwallet=$Wallet", "getnewaddress", "initial-mining", "bech32")
    $mineAddr = ($mineAddr | Out-String).Trim()

    Invoke-Btc -ArgsList @("-regtest", "generatetoaddress", "101", $mineAddr) | Write-Host
}

Write-Host ""
Write-Host "--- FUND STM32 ADDRESS ---"

$fundTxid = Invoke-Btc -ArgsList @("-regtest", "-rpcwallet=$Wallet", "sendtoaddress", $stm32Addr, "0.001")
$fundTxid = ($fundTxid | Out-String).Trim()

if ($fundTxid.Length -ne 64) {
    throw "Funding txid invalid: $fundTxid"
}

Write-Host "FUND_TXID=$fundTxid"

$fundInfo = Invoke-Btc -ArgsList @("-regtest", "-rpcwallet=$Wallet", "gettransaction", $fundTxid, "true") | ConvertFrom-Json
$fundHex = $fundInfo.hex

if ($null -eq $fundHex -or $fundHex.Length -eq 0) {
    throw "Could not get funding transaction hex"
}

$fundDecoded = Invoke-Btc -ArgsList @("-regtest", "decoderawtransaction", $fundHex) | ConvertFrom-Json

$freshOut = $fundDecoded.vout | Where-Object {
    $_.scriptPubKey.hex -eq $ownScript
} | Select-Object -First 1

if ($null -eq $freshOut) {
    throw "Could not find STM32 output in funding transaction"
}

$freshVout = [uint32]$freshOut.n
$freshInputSats = [uint64]([decimal]$freshOut.value * 100000000)
$freshTxidLe = Convert-TxidToLittleEndianHex $fundTxid

Write-Host ""
Write-Host "--- FRESH STM32 UTXO ---"
Write-Host "FRESH_TXID=$fundTxid"
Write-Host "FRESH_TXID_LE=$freshTxidLe"
Write-Host "FRESH_VOUT=$freshVout"
Write-Host "FRESH_INPUT_SATS=$freshInputSats"

if ($freshInputSats -ne 100000) {
    throw "Expected 100000 sats, got $freshInputSats"
}

Write-Host ""
Write-Host "--- MINE FUNDING TX ---"

$mineAddr2 = Invoke-Btc -ArgsList @("-regtest", "-rpcwallet=$Wallet", "getnewaddress", "confirm-funding", "bech32")
$mineAddr2 = ($mineAddr2 | Out-String).Trim()

Invoke-Btc -ArgsList @("-regtest", "generatetoaddress", "1", $mineAddr2) | Write-Host

Write-Host ""
Write-Host "--- ASK STM32 TO SIGN FRESH UTXO ---"

.\tools\wallet_generate_tx_command.ps1 `
    -TxidLe $freshTxidLe `
    -Vout $freshVout `
    -InputSats $freshInputSats `
    -PaySats 60000 `
    -ChangeSats 30000 `
    -RawTxOutFile ".\tools\last_raw_tx.txt"

if ($LASTEXITCODE -ne 0) {
    throw "STM32 host transaction generator failed"
}

Write-Host ""
Write-Host "--- BROADCAST STM32 RAW TX ---"

$raw = (Get-Content ".\tools\last_raw_tx.txt" -Raw).Trim()
$stm32Txid = Invoke-Btc -ArgsList @("-regtest", "sendrawtransaction", $raw)
$stm32Txid = ($stm32Txid | Out-String).Trim()

Write-Host ""
Write-Host "STM32_BROADCAST_TXID=$stm32Txid"

Write-Host ""
Write-Host "--- MINE STM32 TX ---"

$mineAddr3 = Invoke-Btc -ArgsList @("-regtest", "-rpcwallet=$Wallet", "getnewaddress", "mine-stm32-spend", "bech32")
$mineAddr3 = ($mineAddr3 | Out-String).Trim()

Invoke-Btc -ArgsList @("-regtest", "generatetoaddress", "1", $mineAddr3) | Write-Host

Write-Host ""
Write-Host "--- CHECK STM32 TX OUTPUTS ---"

Invoke-Btc -ArgsList @("-regtest", "gettxout", $stm32Txid, "0") | Write-Host
Invoke-Btc -ArgsList @("-regtest", "gettxout", $stm32Txid, "1") | Write-Host

Write-Host ""
Write-Host "STM32_REGTEST_FULL_LOOP_PASS"
