# Trusted child only. The WithContext bridge authenticates all source identities.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RosRoot,[Parameter(Mandatory)][string]$RosSha,
    [Parameter(Mandatory)][string]$WrapperRoot,[Parameter(Mandatory)][string]$WrapperSha,
    [Parameter(Mandatory)][string]$FixtureRoot,[Parameter(Mandatory)][string]$ToolsRoot,
    [Parameter(Mandatory)][string]$ConfigPath,[Parameter(Mandatory)][string]$OutputRoot,
    [Parameter(Mandatory)][string]$TestRoot,
    [ValidateSet('committed','candidate')][string]$Mode='committed',
    [string]$ArtifactRoot='',[string]$CandidatePath='',[string]$PythonExe='python'
)
$ErrorActionPreference='Stop'
$env:PYTHONDONTWRITEBYTECODE='1'
$null=& $PythonExe -I -B "$PSScriptRoot/selected_ros_tests.py" validate --tests $TestRoot
if($LASTEXITCODE -ne 0){throw 'Invalid selected ROS test-only bundle.'}
. (Join-Path $ToolsRoot '.github/scripts/PythonContract.ps1')
$config=Read-PythonConfig $ConfigPath
if($config.baseline_ready -cne $true){throw 'Product baseline is not ready.'}
if($env:GITHUB_REF -ceq 'refs/heads/main'){$null=Read-PythonConfig $ConfigPath 'main'}
$options=@{RosRoot=$RosRoot;RosSha=$RosSha;WrapperRoot=$WrapperRoot;WrapperSha=$WrapperSha;FixtureRoot=$FixtureRoot;ToolsRoot=$ToolsRoot;ConfigPath=$ConfigPath;Mode=$Mode;PythonExe=$PythonExe;OutputRoot=(Join-Path $OutputRoot 'baseline')}
if($Mode -ceq 'candidate'){$options.ArtifactRoot=$ArtifactRoot;$options.CandidatePath=$CandidatePath}
switch -CaseSensitive ($config.fixture_sha256) {
    '1cdfb9448a1776011eadc9aef8356362216032013a4f268f50242746c50a0b44' {$runner='Invoke-RosConformance.ps1'}
    '14313786be4d5c6daea28e40d2f48567cbc1356feb0f0309e0a212339137923b' {$runner='Invoke-LayeredRosConformance.ps1';$options.Stage='all'}
    default {throw 'Unsupported canonical fixture profile; no fallback.'}
}
# A selected suite is additional to the actual product baseline.
& (Join-Path $PSScriptRoot $runner) @options
if(!$?){throw 'Mandatory ROS baseline failed.'}
$options.OutputRoot=Join-Path $OutputRoot 'selected-canonical'
$options.TestRoot=$TestRoot
& (Join-Path $PSScriptRoot $runner) @options
if(!$?){throw 'Selected ROS canonical suite failed.'}
& $PythonExe -I -B "$PSScriptRoot/selected_ros_tests.py" run --tests $TestRoot --ros $RosRoot --wrapper $WrapperRoot --output (Join-Path $OutputRoot 'selected-own')
if($LASTEXITCODE -ne 0){throw 'Selected ROS full inventory failed.'}
