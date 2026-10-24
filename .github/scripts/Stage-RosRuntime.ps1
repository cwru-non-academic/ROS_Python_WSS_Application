param(
    [Parameter(Mandatory)][string]$RosRoot,
    [Parameter(Mandatory)][string]$WrapperRoot,
    [Parameter(Mandatory)][string]$PayloadRoot,
    [Parameter(Mandatory)][string]$ProjectionPath,
    [Parameter(Mandatory)][string]$ToolsRoot,
    [Parameter(Mandatory)][string]$Destination
)
$ErrorActionPreference='Stop'
. (Join-Path $ToolsRoot '.github/scripts/PythonContract.ps1')
$record=Get-Content -LiteralPath $ProjectionPath -Raw | ConvertFrom-Json
Assert-PythonProjection $PayloadRoot $record
if (Test-Path -LiteralPath $Destination) { throw 'Disposable ROS runtime must be new.' }
$archive=$Destination+'.zip'
& git -C $RosRoot archive --format=zip "--output=$archive" HEAD
if ($LASTEXITCODE -ne 0) { throw 'Cannot stage exact ROS source.' }
Expand-Archive -LiteralPath $archive -DestinationPath $Destination
$bundle=Join-Path $Destination 'HFI_WSS_Python_Interface'
New-Item -ItemType Directory -Force -Path $bundle | Out-Null
Copy-Item -LiteralPath (Join-Path $WrapperRoot 'src') -Destination $bundle -Recurse
Copy-Item -LiteralPath $PayloadRoot -Destination (Join-Path $bundle 'Cs_Libraries') -Recurse
Assert-PythonProjection (Join-Path $bundle 'Cs_Libraries') $record
