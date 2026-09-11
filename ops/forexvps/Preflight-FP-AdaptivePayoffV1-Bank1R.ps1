[CmdletBinding()]param()
$ErrorActionPreference='Stop'
$share='\\tsclient\SolTrade';$root='C:\SolTrade'
$common=Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
function ParseErrors([string]$path) {
    $tokens=$null;$errors=$null
    [Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors) | Out-Null
    return @($errors | ForEach-Object {$_.Message})
}
function Runtime([string]$name) {
    Get-Content -LiteralPath (Join-Path $common "$name\runtime.csv") -TotalCount 2 |
        ConvertFrom-Csv | Select-Object -First 1
}
function Processes([string]$terminalHome) {
    @(Get-Process -Name terminal64 -ErrorAction SilentlyContinue | Where-Object {$_.Path -eq (Join-Path $terminalHome 'terminal64.exe')})
}
$fp=Runtime 'SolTradeFastMultiMarketV2'
$f10=Runtime 'SolTradeFastMultiMarketV2F10'
$f100=Runtime 'SolTradeFastMultiMarketV2F100'
$deployErrors=ParseErrors (Join-Path $share 'Deploy-FP-AdaptivePayoffV1-Bank1R.ps1')
$scoreErrors=ParseErrors (Join-Path $share 'Publish-FP-AdaptivePayoffV1-Bank1R-Scoreboard.ps1')
$result=[ordered]@{
    captured_utc=[DateTime]::UtcNow.ToString('o')
    deploy_parse_errors=$deployErrors
    scoreboard_parse_errors=$scoreErrors
    fp_runtime=$fp
    fp_process_count=@(Processes (Join-Path $root 'MT5-FP-DEMO')).Count
    fp_flat=([int]$fp.positions -eq 0 -and [int]$fp.orders -eq 0)
    fxify_10k_runtime=$f10
    fxify_100k_runtime=$f100
    fxify_10k_paused=($f10.entry_permission -eq 'DISABLED_DRY_RUN' -and $f10.autonomous_entry -eq 'false' -and [int]$f10.positions -eq 0 -and [int]$f10.orders -eq 0)
    fxify_100k_paused=($f100.entry_permission -eq 'DISABLED_DRY_RUN' -and $f100.autonomous_entry -eq 'false' -and [int]$f100.positions -eq 0 -and [int]$f100.orders -eq 0)
    orders_sent=$false
}
$result | ConvertTo-Json -Depth 7 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $share 'remote-output\fp-adaptive-payoff-v1-bank1r-preflight.json')
if($deployErrors.Count -or $scoreErrors.Count -or -not $result.fp_flat -or $result.fp_process_count -ne 1 -or
   -not $result.fxify_10k_paused -or -not $result.fxify_100k_paused){exit 1}
