[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$base='C:\SolTrade\Research\SolTrade-Full-Lifetime-Tracker-V1\MQL5\Files\SolTradeFullLifetimeTrackerV1'
$out=Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'remote-output\full-readonly-audit-20260924'
foreach($n in @('events','outcomes')){
 $rows=New-Object System.Collections.Generic.List[object]
 foreach($f in @(Get-ChildItem -LiteralPath (Join-Path $base $n) -Filter '*.csv' -Recurse -File -ErrorAction SilentlyContinue)){
  foreach($r in @(Import-Csv -LiteralPath $f.FullName)){$rows.Add($r)}
 }
 if($rows.Count){$rows|Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath (Join-Path $out ('tracker-'+$n+'-all.csv'))}
}
