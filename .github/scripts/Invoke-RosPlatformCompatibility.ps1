param(
    [Parameter(Mandatory)][string]$RosRoot,
    [Parameter(Mandatory)][string]$RosSha,
    [Parameter(Mandatory)][string]$WrapperRoot,
    [Parameter(Mandatory)][string]$WrapperSha,
    [Parameter(Mandatory)][string]$FixtureRoot,
    [Parameter(Mandatory)][string]$ToolsRoot,
    [Parameter(Mandatory)][string]$OutputRoot,
    [string]$PythonExe='python',
    [ValidateSet('committed','candidate')][string]$Mode='committed',
    [string]$ArtifactRoot='',
    [string]$CandidatePath=''
)
$ErrorActionPreference = 'Stop'
. (Join-Path $ToolsRoot '.github/scripts/PythonContract.ps1')
Assert-PythonSource $RosRoot $RosSha -IgnoreSubmodule
if (Test-Path -LiteralPath $OutputRoot) { throw 'ROS platform output must be new.' }
New-Item -ItemType Directory -Path $OutputRoot | Out-Null
# Exercise the same installed-wheel, Ports and C# backend checks as Python CLI.
$candidateOptions = @{Mode=$Mode}
if ($Mode -ceq 'candidate') { $candidateOptions.ArtifactRoot=$ArtifactRoot; $candidateOptions.CandidatePath=$CandidatePath }
& (Join-Path $ToolsRoot '.github/scripts/Invoke-PlatformCompatibility.ps1') @candidateOptions -WrapperRoot $WrapperRoot -WrapperSha $WrapperSha -FixtureRoot $FixtureRoot -OutputRoot (Join-Path $OutputRoot 'wrapper-platform') -PythonExe $PythonExe
if (!$?) { throw 'Shared Python platform compatibility failed.' }
Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue
$runtime = Join-Path $OutputRoot 'application'
$projection = Join-Path $WrapperRoot '.github/python-candidate.json'
$payload = Join-Path $WrapperRoot 'Cs_Libraries'
if ($Mode -ceq 'candidate') {
    $payload = Join-Path $OutputRoot 'wrapper-platform/projection'
    $record = New-PythonProjection $ArtifactRoot $WrapperRoot (Join-Path $OutputRoot 'ros-projection') (Get-Content $CandidatePath -Raw | ConvertFrom-Json)
    $projection = Join-Path $OutputRoot 'projection.json'
    $record | ConvertTo-Json -Depth 10 | Set-Content $projection
}
& (Join-Path $RosRoot '.github/scripts/Stage-RosRuntime.ps1') -RosRoot $RosRoot -WrapperRoot $WrapperRoot -PayloadRoot $payload -ProjectionPath $projection -ToolsRoot $ToolsRoot -Destination $runtime
Push-Location $runtime
try {
    & $PythonExe -m unittest discover -s tests -v
    if ($LASTEXITCODE -ne 0) { throw 'ROS import, contract and lifecycle tests failed.' }
    & $PythonExe -u conformance/ros_emulator.py --output (Join-Path $OutputRoot 'ros-model.json')
    if ($LASTEXITCODE -ne 0) { throw 'ROS production model fixtures failed.' }
} finally { Pop-Location }
$model = Get-Content (Join-Path $OutputRoot 'ros-model.json') -Raw | ConvertFrom-Json
if ($model.tests -ne 5 -or $model.failed -ne 0 -or $model.skipped -ne 0 -or $model.observations.Count -ne 15) {
    throw 'All five existing model tests and fifteen device/scenario observations must execute without skips.'
}
Assert-PythonSource $RosRoot $RosSha -IgnoreSubmodule
Assert-PythonSource $WrapperRoot $WrapperSha
$platform = Get-Content (Join-Path $OutputRoot 'wrapper-platform/platform.json') -Raw | ConvertFrom-Json
@{
    schema='wss-ros-platform/v1'; ros_sha=$RosSha; wrapper_sha=$WrapperSha
    os=$platform.os; projection_sha256=$platform.projection_sha256
    scope='actual Python application contracts, import/layout selection, wrapper/Core model and installed wrapper platform loading; ROS APIs doubled'
    native_ros='not exercised in this job; real Humble colcon/rclpy/DDS is tested separately on Ubuntu 22.04'
    ble=$platform.ble; model_tests=$model.tests; model_observations=$model.observations.Count
    model_skipped=$model.skipped
    model_sha256=(Get-FileHash (Join-Path $OutputRoot 'ros-model.json')).Hash.ToLowerInvariant()
} | ConvertTo-Json | Set-Content (Join-Path $OutputRoot 'platform-summary.json')
Write-Output 'PASS: ROS application and wrapper platform compatibility; this is not native ROS certification for this OS.'
