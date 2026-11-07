[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CoreRoot,
    [Parameter(Mandatory)][string]$ContextPath,
    [Parameter(Mandatory)][string]$RootsPath,
    [Parameter(Mandatory)][string]$WorkRoot,
    [Parameter(Mandatory)][string]$ToolsRoot,
    [ValidateSet('committed','candidate')][string]$Mode='committed',
    [string]$ArtifactRoot='',[string]$CandidatePath='',[string]$PythonExe='python'
)
. "$PSScriptRoot/RosSelectedContext.ps1"
Invoke-RosSelectedWithContext @PSBoundParameters
