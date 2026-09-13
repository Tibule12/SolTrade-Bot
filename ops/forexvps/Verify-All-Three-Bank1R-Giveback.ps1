[CmdletBinding()]param()
$ErrorActionPreference='Stop'
$root='C:\SolTrade';$share=Split-Path -Parent $MyInvocation.MyCommand.Path
$common=Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
$out=Join-Path $share 'remote-output\all-three-bank1r-giveback-verification.json'
$accounts=@(
 [ordered]@{id='fp';login='7404213';server='FPMarketsSC-Demo';home_path="$root\MT5-FP-DEMO";state='SolTradeFastMultiMarketV2';expert='SolTradeFastMultiMarketV2';source='4d1980812f3312728d8c8258c6b8b59d4c29013f3f3832128866fbcfcab3c63e';binary='fa2107a6088cf211d73eee646676cb3d61a6975b5b98eb47a548544c04199fea';ini='fp-demo.ini';risk='1.00';aggregate='1.50'},
 [ordered]@{id='fxify-10k';login='7196820';server='FXIFY-Server';home_path="$root\MT5-FXIFY-10K";state='SolTradeFastMultiMarketV2F10';expert='SolTradeFastMultiMarketV202F10';source='055855e84ad7fe392932edc1c878f6ff66288360d148575c8dbc5a9692f2c1c3';binary='f1a527764b264b903ee54d4d9a890873bd7f0ceb38edca8b98f33df0f5715039';ini='fxify-10k.ini';risk='1.00';aggregate='1.50'},
 [ordered]@{id='fxify-100k';login='7198096';server='FXIFY-Server';home_path="$root\MT5-FXIFY-100K";state='SolTradeFastMultiMarketV2F100';expert='SolTradeFastMultiMarketV202F100';source='b10d8a40f422cfba2dcb9c02b1b5b0d44dc9d669e4336d4c21601fbb17a483ef';binary='63bbbfa3a0fd81180d93cad558e5c841b2a5608aac2c921cf26aca13e7aad1f8';ini='fxify-100k.ini';risk='1.00';aggregate='1.50'}
)
function Sha($p){if(!(Test-Path -LiteralPath $p)){return $null};(Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLowerInvariant()}
function Runtime($state){$p=Join-Path (Join-Path $common $state) 'runtime.csv';for($i=0;$i -lt 8;$i++){try{$r=@(Get-Content -LiteralPath $p -TotalCount 2)|ConvertFrom-Csv|Select-Object -First 1;if($r.login){return $r}}catch{};Start-Sleep -Milliseconds 250};return $null}
function Fresh($r){try{$t=[DateTime]::ParseExact($r.timestamp_utc,'yyyy.MM.dd HH:mm:ss',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal);return ([DateTime]::UtcNow-$t).TotalSeconds -le 90}catch{return $false}}
function Procs($terminalHome){@(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'"|Where-Object {$_.ExecutablePath -eq "$terminalHome\terminal64.exe"})}
$rows=@();$all=$true
foreach($a in $accounts){
 $r=Runtime $a.state;$er=Join-Path $a.home_path 'MQL5\Experts\SolTrade';$ini=Join-Path "$root\state" $a.ini;$iniText=[IO.File]::ReadAllText($ini);$m=[regex]::Match($iniText,'(?m)^ExpertParameters=([^\r\n]+)');$preset=$null;$presetText=''
 if($m.Success){$preset=Join-Path (Join-Path $a.home_path 'MQL5\Presets') ([IO.Path]::GetFileName($m.Groups[1].Value));if(Test-Path -LiteralPath $preset){$presetText=[IO.File]::ReadAllText($preset)}}
 $checks=[ordered]@{fresh=(Fresh $r);identity=($r.login -eq $a.login -and $r.server -eq $a.server);connected=($r.connected -eq 'true');scanner=($r.scanner_active -eq 'true');autonomous=($r.autonomous_entry -eq 'true');ownership=($r.ownership_permit -eq 'GRANTED');manager=($r.manager_version -eq 'ADAPTIVE_PAYOFF_V1_BANK1R_GIVEBACK');process_count=(@(Procs $a.home_path).Count -eq 1);source_hash=(Sha (Join-Path $er ($a.expert+'.mq5'))) -eq $a.source;binary_hash=(Sha (Join-Path $er ($a.expert+'.ex5'))) -eq $a.binary;startup_enabled=($iniText -match '(?m)^Enabled=1\r?$' -and $iniText -match '(?m)^AllowLiveTrading=1\r?$');preset_active=($presetText -match '(?m)^DryRunOnly=false\r?$');risk=($presetText -match ('(?m)^RiskPerTradePercent='+[regex]::Escape($a.risk)+'\r?$'));aggregate=($presetText -match ('(?m)^MaxPortfolioRiskPercent='+[regex]::Escape($a.aggregate)+'\r?$'))}
 $healthy=!($checks.Values -contains $false);if(!$healthy){$all=$false}
 $rows+=@{id=$a.id;account=$a.login;healthy=$healthy;checks=$checks;pids=@(Procs $a.home_path|ForEach-Object {$_.ProcessId});source_sha256=Sha (Join-Path $er ($a.expert+'.mq5'));binary_sha256=Sha (Join-Path $er ($a.expert+'.ex5'));preset=$preset;preset_sha256=Sha $preset;runtime=$r}
}
$tasks=@();foreach($name in @('SolTrade-Watchdog','SolTrade-AccountOwnership-7404213','SolTrade-AccountOwnership-7196820','SolTrade-AccountOwnership-7198096')){try{$t=Get-ScheduledTask -TaskName $name;$i=Get-ScheduledTaskInfo -TaskName $name;$tasks+=@{name=$name;state=[string]$t.State;enabled=$t.Settings.Enabled;last_result=$i.LastTaskResult;last_run=$i.LastRunTime}}catch{$tasks+=@{name=$name;error=$_.Exception.Message};$all=$false}}
[ordered]@{schema='SOLTRADE_ALL_THREE_BANK1R_GIVEBACK_VERIFICATION_V1';timestamp_utc=[DateTime]::UtcNow.ToString('o');status=if($all){'ALL_THREE_ACTIVE_VERIFIED'}else{'VERIFICATION_FAILED'};accounts=$rows;tasks=$tasks;total_terminal_processes=@(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'").Count;forced_orders=$false} | ConvertTo-Json -Depth 15 | Set-Content -Encoding UTF8 -LiteralPath $out
if(!$all){throw 'All-three verification failed'}
