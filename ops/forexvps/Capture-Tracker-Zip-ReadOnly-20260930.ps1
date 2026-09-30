$ErrorActionPreference='Stop'
$out=Join-Path $PSScriptRoot 'remote-output\full-readonly-audit-20260930'
$root='C:\SolTrade\Research\SolTrade-Full-Lifetime-Tracker-V1\MQL5\Files\SolTradeFullLifetimeTrackerV1'
$temp=Join-Path $env:TEMP ('soltrade-audit-tracker-'+[Guid]::NewGuid().ToString('N')+'.zip')
Add-Type -AssemblyName System.IO.Compression
$stream=[IO.File]::Open($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
$zip=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create)
$counts=@{}
try {
 foreach($kind in @('events','outcomes','lifetime_observations')) {
  $n=0
  foreach($f in (Get-ChildItem -LiteralPath (Join-Path $root $kind) -File -Filter '*.csv' -Recurse -ErrorAction SilentlyContinue)) {
   $entry=$zip.CreateEntry($f.FullName.Substring($root.Length+1).Replace('\','/'),[IO.Compression.CompressionLevel]::Fastest)
   $src=[IO.File]::Open($f.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
   $dst=$entry.Open()
   try {$src.CopyTo($dst)} finally {$dst.Dispose();$src.Dispose()}
   $n++
  }
  $counts[$kind]=$n
 }
} finally {$zip.Dispose();$stream.Dispose()}
Copy-Item -LiteralPath $temp -Destination (Join-Path $out 'tracker-all-quick.zip') -Force
$hash=(Get-FileHash -Algorithm SHA256 -LiteralPath $temp).Hash.ToLowerInvariant()
Remove-Item -LiteralPath $temp -Force
[ordered]@{captured_utc=[DateTime]::UtcNow.ToString('o');file_counts=$counts;sha256=$hash;order_capability=$false;orders_sent=0;read_only=$true}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $out 'tracker-quick-receipt.json')
