$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'ops/forexvps/Repair-V3-Forward-Evaluator-20260924.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Deployment helper parse failure'}
$function=$ast.Find({param($node) $node-is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name-eq 'StableTaskXml'},$true)
. ([scriptblock]::Create($function.Extent.Text))
$before='<Task xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task"><Settings><ExecutionTimeLimit>PT4M</ExecutionTimeLimit><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy></Settings><Triggers><TimeTrigger><ExecutionTimeLimit>PT0S</ExecutionTimeLimit></TimeTrigger></Triggers><Actions><Exec><Command>powershell.exe</Command><Arguments>-NoProfile -File evaluator.ps1</Arguments></Exec></Actions></Task>'
$after=$before.Replace('PT4M','PT8M').Replace('<MultipleInstancesPolicy>','<Priority>6</Priority><MultipleInstancesPolicy>')
if((StableTaskXml $before)-cne (StableTaskXml $after)){throw 'Default omitted priority must compare equal'}
if((StableTaskXml $before)-cne (StableTaskXml $after.Replace('</Settings>',"`n</Settings>"))){throw 'Formatting-only whitespace must compare equal'}
foreach($changed in @($after.Replace('powershell.exe','unexpected.exe'),$after.Replace('IgnoreNew','Parallel'),$after.Replace('PT0S','PT5M'),$after.Replace('-NoProfile -File','-NoProfile  -File'))){
 if((StableTaskXml $before)-ceq (StableTaskXml $changed)){throw 'Unauthorized task change was ignored'}
}
[ordered]@{status='PASS';checks=6;production_paths_read=$false}|ConvertTo-Json
