param([Parameter(Mandatory)][string]$ToolsRoot,[Parameter(Mandatory)][string]$Root)
. (Join-Path $ToolsRoot '.github/scripts/PythonPromotion.ps1')
function Require-Rejection([string]$Name,[scriptblock]$Check) {
    $rejected=$false
    try { & $Check } catch { $rejected=$true }
    if (!$rejected) { throw "Safety check unexpectedly accepted: $Name" }
    Write-Output "Rejected as required: $Name"
}
$e=Get-Content -LiteralPath (Join-Path $Root 'evidence.json') -Raw | ConvertFrom-Json
Assert-PythonRosReports $e $Root
Require-Rejection 'legacy CLI-only approval cannot authorize ROS' { Assert-PythonFanoutApproval ([pscustomobject]@{schema='wss-python-promotion/v1'}) }
foreach ($case in @('hash','model-skip','native-channel','model-scenario')) {
    $copy=Join-Path (Split-Path -Parent $Root) ('ros-negative-'+[guid]::NewGuid().ToString('N'))
    Copy-Item -LiteralPath $Root -Destination $copy -Recurse
    $proof=Get-Content -LiteralPath (Join-Path $copy 'evidence.json') -Raw | ConvertFrom-Json
    if ($case -ceq 'hash') {
        Add-Content -LiteralPath (Join-Path $copy 'ros-native-copy.json') -Value ' '
    } elseif ($case -ceq 'native-channel') {
        $path=Join-Path $copy 'ros-native-copy.json'
        $report=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $report.channels=@(1..8)
        $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path
        $proof.ros_native_copy_sha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()
    } else {
        $path=Join-Path $copy 'ros-model.json'
        $report=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        if ($case -ceq 'model-skip') { $report.skipped=1 }
        else { $report.observations=@($report.observations | Select-Object -Skip 1) }
        $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path
        $proof.ros_model_sha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()
    }
    Require-Rejection $case { Assert-PythonRosReports $proof $copy }
}
if (@(Get-PythonEvidenceFiles ros).Count -ne 7 -or @(Get-PythonEvidenceJobs ros).Count -ne 3) { throw 'ROS role contract changed.' }
Write-Output 'ROS negative evidence checks passed; these are rejection tests, not promotion approval.'
