# Evaluate only argument-array assignments, never launch .NET or WSS.
$ErrorActionPreference='Stop'
$root=Join-Path $PSScriptRoot '..'
$count=0
function Assert-Arguments([string]$Text){
 $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($Text,[ref]$tokens,[ref]$errors)
 if($errors){throw 'Invalid runner syntax.'}
 $arrays=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -ceq '$arguments'},$true))
 if($arrays.Count -ne 1){throw 'Expected one real test argument array.'}
 $OutputRoot=Join-Path ([IO.Path]::GetTempPath()) 'synthetic output';$nunit=Join-Path $OutputRoot 'nunit'
 $arguments=& ([scriptblock]::Create($arrays[0].Right.Extent.Text))
 $expected=@('test','Wss.DotNet.Conformance.Tests.csproj','-p:DisablePackageAssetsCache=true','--logger','"trx;LogFileName=results.trx"','--results-directory',('"'+(Join-Path $OutputRoot 'test-results')+'"'),'--blame-hang-timeout','2m','--',('NUnit.TestOutputXml="'+$nunit+'"'))
 if(($arguments|ConvertTo-Json -Compress) -cne ($expected|ConvertTo-Json -Compress)){throw 'Test runner arguments changed beyond mandatory cache avoidance.'}
 if(!$Text.Contains('-ArgumentList $arguments -WindowStyle Hidden') -or !$Text.Contains('$process.WaitForExit($TimeoutSeconds*1000)') -or !$Text.Contains('if ($process.ExitCode -ne 0)')){throw 'Mandatory process timeout, hidden launch or exit guard missing.'}
}
foreach($file in @('Invoke-LayeredRosConformance.ps1','Invoke-ProfiledRosConformance.ps1','Invoke-RosConformance.ps1')){
 $text=Get-Content (Join-Path $root $file) -Raw
 Assert-Arguments $text;$count++
 foreach($changed in @($text.Replace("'-p:DisablePackageAssetsCache=true',",''),$text.Replace('DisablePackageAssetsCache=true','DisablePackageAssetsCache=false'),$text.Replace("'test','Wss.DotNet","'build','Wss.DotNet"),$text.Replace("'-p:DisablePackageAssetsCache=true',","'-p:DisablePackageAssetsCache=true','-p:DisablePackageAssetsCache=true',"),$text.Replace('-ArgumentList $arguments','-ArgumentList @()'))){
  $rejected=$false;try{Assert-Arguments $changed}catch{$rejected=$true};if(!$rejected){throw "Accepted cache/runner mutation in $file"};$count++
 }
}
Write-Output "PASS: $count ROS emitted test argument and cache mutations; baseline launch semantics retained."
