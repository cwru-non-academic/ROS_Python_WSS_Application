param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$ToolsRoot,
    [Parameter(Mandatory)][string]$ContractRoot,
    [Parameter(Mandatory)][string]$OutputRoot
)
$ErrorActionPreference='Stop'
if ($env:GITHUB_REPOSITORY -cne 'cwru-non-academic/ROS_Python_WSS_Application' -or $env:TARGET_ID -cne 'python-ros') { throw 'Wrong application receipt source/role.' }
& node (Join-Path $ToolsRoot '.github/scripts/Write-ReleaseReceipt.mjs') $SourceRoot $ToolsRoot $ContractRoot $OutputRoot
if ($LASTEXITCODE -ne 0) { throw 'Read-only application acceptance verification failed.' }
