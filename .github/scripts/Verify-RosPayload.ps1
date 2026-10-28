param(
    [string]$WrapperRoot = 'HFI_WSS_Python_Interface',
    [string]$OutputPath = 'results/payload.json'
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $WrapperRoot).Path
# Reuse the pinned library's canonical inventory/digest algorithm. This is CI
# evidence validation, not a runtime allowlist or external-install policy.
. (Join-Path $root '.github/scripts/PythonContract.ps1')
$record = Get-Content -LiteralPath (Join-Path $root '.github/python-candidate.json') -Raw | ConvertFrom-Json
Assert-PythonProjection (Join-Path $root 'Cs_Libraries') $record
$sha = & git -C $root rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Cannot identify exact wrapper checkout.' }
$result = [ordered]@{
    schema = 'wss-ros-payload/v1'
    wrapper_sha = $sha.Trim()
    candidate = $record.candidate
    projection_sha256 = $record.projection_sha256
    verified_files = $record.files.Count
}
$destination = [IO.Path]::GetFullPath($OutputPath)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $destination
$result | ConvertTo-Json -Depth 6
