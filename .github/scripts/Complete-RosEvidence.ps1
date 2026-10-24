param([Parameter(Mandatory)][string]$ToolsRoot,[Parameter(Mandatory)][string]$Root)
. (Join-Path $ToolsRoot '.github/scripts/PythonPromotion.ps1')
$config=Read-PythonConfig (Join-Path $PSScriptRoot '../python-ci.json')
$e=Get-Content -LiteralPath (Join-Path $Root 'evidence.json') -Raw | ConvertFrom-Json
if ($e.role -cne 'ros' -or $e.execution -cne 'pythonnet' -or !$e.python_executed -or
    $e.run_repository -cne $env:GITHUB_REPOSITORY -or [string]$e.run_id -cne $env:GITHUB_RUN_ID -or
    $e.run_sha -cne $env:GITHUB_SHA -or $e.ros_sha -cne $env:GITHUB_SHA) { throw 'ROS canonical source/run identity mismatch.' }
Assert-PythonResults (Join-Path $Root 'results.xml') $config -DotNet
if ($e.sdk -cne $config.dotnet_sdk -or $e.python -cne $config.python_version -or $e.pythonnet -cne $config.pythonnet_version -or
    $e.fixture_sha -cne $config.fixture_commit -or $e.fixture_sha256 -cne $config.fixture_sha256 -or
    $e.target_framework -cne 'net9.0' -or $e.test_framework -cne 'NUnit 3.14.0' -or
    $e.discovered -ne 10 -or $e.executed -ne 10 -or $e.passed -ne 10 -or $e.failed -ne 0 -or $e.skipped -ne 0 -or $e.assertion_expressions -ne 18) { throw 'Canonical runtime/fixture/execution mismatch.' }
$projection=Get-Content -LiteralPath (Join-Path $Root 'projection.json') -Raw | ConvertFrom-Json
Assert-PythonSameCandidate $projection.candidate $e.candidate
if ($projection.schema -cne 'wss-python-projection/v1' -or (Get-PythonProjectionDigest $projection.files) -cne $e.projection_sha256 -or
    $projection.projection_sha256 -cne $e.projection_sha256 -or @(Compare-Object $PythonProjectionFiles @($projection.files.source) -CaseSensitive).Count) { throw 'Projection/evidence mismatch.' }
foreach ($pair in @(@('results.xml','results_sha256'),@('dotnet.log','log_sha256'))) {
    if ((Get-FileHash -LiteralPath (Join-Path $Root $pair[0])).Hash.ToLowerInvariant() -cne $e.($pair[1])) { throw 'Canonical result/log hash mismatch.' }
}
foreach ($pair in @(@('ros-model.json','ros_model_sha256'),@('ros-native-symlink.json','ros_native_symlink_sha256'),@('ros-native-copy.json','ros_native_copy_sha256'))) {
    $e | Add-Member -NotePropertyName $pair[1] -NotePropertyValue (Get-FileHash -LiteralPath (Join-Path $Root $pair[0])).Hash.ToLowerInvariant() -Force
}
$e | Add-Member -NotePropertyName native_ros_distribution -NotePropertyValue humble -Force
Assert-PythonRosReports $e $Root
$actual=@(Get-ChildItem -LiteralPath $Root -Recurse -File | ForEach-Object { [IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/') })
if (@(Compare-Object @(Get-PythonEvidenceFiles ros) $actual -CaseSensitive).Count) { throw 'ROS evidence must contain exactly seven files.' }
$e | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $Root 'evidence.json')
Write-Output 'Verified canonical execution plus independent model and native ROS reports; seven-file evidence assembled.'
