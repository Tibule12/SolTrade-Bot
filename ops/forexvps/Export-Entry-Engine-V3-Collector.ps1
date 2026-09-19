[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
[Diagnostics.Process]::GetCurrentProcess().PriorityClass='BelowNormal'
$root='C:\SolTrade'
$share=Split-Path -Parent $MyInvocation.MyCommand.Path
$out=Join-Path $share 'remote-output\entry-engine-v3-20260918'
$collector="$root\Research\SolTrade-Brain-Collector-V1\MQL5\Files\SolTradeBrainCollectorV1"
$common=Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
$stage=Join-Path ([IO.Path]::GetTempPath()) ('entry-v3-'+[guid]::NewGuid().ToString('N')+'.zip')
New-Item -ItemType Directory -Force -Path $out | Out-Null

function Sha([string]$path){if(Test-Path -LiteralPath $path){(Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()}else{$null}}
function Runtime([string]$state){$p=Join-Path $common "$state\runtime.csv";$lines=@(Get-Content -LiteralPath $p -TotalCount 2);if($lines.Count -ne 2){return $null};$lines|ConvertFrom-Csv|Select-Object -First 1}
function Proc([string]$exe){@(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'"|Where-Object ExecutablePath -eq $exe|ForEach-Object ProcessId)}
function Fx([string]$id,[string]$login,[string]$terminalHome,[string]$state){
 $ini="$root\state\$id.ini";$preset="$terminalHome\MQL5\Profiles\Presets\SolTradeFastMultiMarketV2.set";$text=[IO.File]::ReadAllText($ini)
 [ordered]@{login=$login;startup=$ini;startup_sha256=Sha $ini;enabled_zero=($text -match '(?m)^Enabled=0\r?$');allow_live_zero=($text -match '(?m)^AllowLiveTrading=0\r?$');preset_sha256=Sha $preset;runtime=Runtime $state;pids=Proc "$terminalHome\terminal64.exe"}
}

$receipt=[ordered]@{schema='ENTRY_ENGINE_V3_COLLECTOR_EXPORT_V1';status='EXPORTING';started_utc=[DateTime]::UtcNow.ToString('o');read_only=$true;orders_sent=$false;positions_modified=$false;files=@()}
try{
 if(-not(Test-Path -LiteralPath $collector)){throw 'collector data root absent'}
 $fpHome="$root\MT5-FP-DEMO";$fpSource="$fpHome\MQL5\Experts\SolTrade\SolTradeFastMultiMarketV2.mq5";$fpBinary=$fpSource.Replace('.mq5','.ex5')
 $receipt.fp=[ordered]@{login='7404213';source_sha256=Sha $fpSource;binary_sha256=Sha $fpBinary;runtime=Runtime 'SolTradeFastMultiMarketV2';pids=Proc "$fpHome\terminal64.exe"}
 $receipt.fxify=@(Fx 'fxify-10k' '7196820' "$root\MT5-FXIFY-10K" 'SolTradeFastMultiMarketV2F10';Fx 'fxify-100k' '7198096' "$root\MT5-FXIFY-100K" 'SolTradeFastMultiMarketV2F100')
 foreach($x in $receipt.fxify){if(-not $x.enabled_zero -or -not $x.allow_live_zero){throw "FXIFY pause configuration failed for $($x.login)"}}
 $hb=@(Get-Content -LiteralPath "$collector\status\heartbeat.csv" -TotalCount 2)|ConvertFrom-Csv|Select-Object -First 1
 if($hb.order_capability -ne 'false' -or $hb.mql_trade_allowed -ne 'false' -or $hb.terminal_trade_allowed -ne 'false'){throw 'collector orderless invariant failed'}
 $receipt.collector_heartbeat=$hb
 $files=@(Get-ChildItem -LiteralPath "$collector\raw_ticks","$collector\features" -File -Recurse);[long]$sourceBytes=0
 Add-Type -AssemblyName System.IO.Compression
 $zipStream=[IO.File]::Create($stage);$archive=[IO.Compression.ZipArchive]::new($zipStream,[IO.Compression.ZipArchiveMode]::Create,$false)
 try{
  foreach($file in $files){
   $relative=$file.FullName.Substring($collector.Length).TrimStart('\').Replace('\','/')
   $input=[IO.File]::Open($file.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
   $length=$input.Length;$sourceBytes+=$length;$entry=$archive.CreateEntry($relative,[IO.Compression.CompressionLevel]::Fastest);$target=$entry.Open()
   try{$remaining=$length;$buffer=New-Object byte[] 1048576;while($remaining -gt 0){$n=$input.Read($buffer,0,[int][Math]::Min($buffer.Length,$remaining));if($n -le 0){throw 'source shortened during snapshot'};$target.Write($buffer,0,$n);$remaining-=$n}}
   finally{$target.Dispose();$input.Dispose()}
   $receipt.files+=@{path=$relative;bytes=$length;last_write_utc=$file.LastWriteTimeUtc.ToString('o')}
  }
 }finally{$archive.Dispose();$zipStream.Dispose()}
 $receipt.source_file_count=$files.Count;$receipt.source_bytes=$sourceBytes
 $receipt.archive_bytes=(Get-Item $stage).Length;$receipt.archive_sha256=Sha $stage
 $dest=Join-Path $out 'collector-snapshot.zip';Copy-Item -Force -LiteralPath $stage -Destination ($dest+'.tmp');Move-Item -Force -LiteralPath ($dest+'.tmp') -Destination $dest
 $receipt.status='COMPLETE';$receipt.completed_utc=[DateTime]::UtcNow.ToString('o')
}catch{$receipt.status='FAILED';$receipt.error=$_.Exception.Message;$receipt.completed_utc=[DateTime]::UtcNow.ToString('o')}
finally{if(Test-Path $stage){Remove-Item -Force $stage};$receipt|ConvertTo-Json -Depth 12|Set-Content -Encoding UTF8 -LiteralPath (Join-Path $out 'export.json')}
if($receipt.status -ne 'COMPLETE'){throw $receipt.error}
$receipt|ConvertTo-Json -Depth 12
