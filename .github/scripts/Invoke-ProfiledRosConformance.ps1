# Additive profile-aware bootstrap. Existing historical runner/guards stay unchanged.
param(
    [Parameter(Mandatory)][string]$WrapperRoot,
    [Parameter(Mandatory)][string]$WrapperSha,
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$OutputRoot,
    [Parameter(Mandatory)][string]$ToolsRoot, [Parameter(Mandatory)][string]$ToolsSha,
    [Parameter(Mandatory)][string]$RosRoot, [Parameter(Mandatory)][string]$RosSha,
    [ValidateSet('committed')][string]$Mode='committed',
    [ValidateSet('ros')][string]$Role='ros',
    [string]$PythonExe='python',
    [ValidateRange(30,1800)][int]$TimeoutSeconds=300
)
. (Join-Path $ToolsRoot '.github/scripts/PythonContract.ps1')
. "$PSScriptRoot/RosOrdinaryTooling.ps1"
Assert-RosOrdinaryProductPair $RosRoot $RosSha $WrapperSha
. (Join-Path $ToolsRoot '.github/scripts/PythonProfiles/Contract.ps1')
# Shared tooling/config is bound independently of actual application and wrapper.
. (Join-Path $ToolsRoot '.github/scripts/PythonProfiles/Tooling.ps1')
$tooling=Resolve-PythonOrdinaryTooling -ToolsRoot $ToolsRoot -ToolsSha $ToolsSha -ConfigPath $ConfigPath -WrapperRoot $WrapperRoot -WrapperSha $WrapperSha
$config=$tooling.config
Assert-PythonSource $WrapperRoot $WrapperSha
Assert-PythonSource $RosRoot $RosSha -IgnoreSubmodule
if(Test-Path -LiteralPath $OutputRoot){throw 'OutputRoot must be new.'}
$rootOutput=[IO.Path]::GetFullPath($OutputRoot)
foreach($source in @($WrapperRoot,$RosRoot,$ToolsRoot) | Where-Object {$_}){
    $path=[IO.Path]::GetFullPath($source)
    if($rootOutput -eq $path -or $rootOutput.StartsWith($path+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Output must remain outside immutable source checkouts.'}
}
New-Item -ItemType Directory -Path $rootOutput | Out-Null
$projection=$tooling.projection
$projectionRoot=Join-Path $WrapperRoot $PythonPluginPath
$candidate=$projection.candidate
# Metadata-only inspection happens only after exact universal inventory/hash verification.
$profile=Resolve-WssReviewedProfile $projectionRoot $candidate
$contract=Get-PythonProfileContract $profile.profile
$tests=[pscustomobject]@{root=$RosRoot;sha=$RosSha;repository=$PythonRosRepository;selection_id='';contract_sha256=''}
$stages=if($profile.profile -ceq 'layered-v1'){@('single','multi')}else{@('single')}
$previousStage=$env:WSS_CONFORMANCE_STAGE
try {
foreach($currentStage in $stages){
    $Stage=$currentStage;$env:WSS_CONFORMANCE_STAGE=$Stage
    $OutputRoot=if($Stage -ceq 'multi'){Join-Path $rootOutput 'multi'}else{$rootOutput}
    if($Stage -ceq 'multi'){New-Item -ItemType Directory -Path $OutputRoot | Out-Null}
    $caseCount=if($Stage -ceq 'multi'){$contract.multi_cases.Count}else{$contract.single_cases.Count}
$harness=Join-Path $OutputRoot 'harness'
$pythonInfo = (& $PythonExe -c 'import json,sys,sysconfig,pythonnet,pathlib; print(json.dumps(dict(version=".".join(map(str,sys.version_info[:2])),home=sys.base_prefix,dll=str(pathlib.Path(sys.base_prefix)/("python"+str(sys.version_info.major)+str(sys.version_info.minor)+".dll")),assembly=str(pathlib.Path(pythonnet.__file__).parent/"runtime"/"Python.Runtime.dll"))))') | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $pythonInfo.version -cne $config.python_version) { throw 'Pinned Python/pythonnet runtime required.' }
$netVersion=(& $PythonExe -c 'from importlib.metadata import version; print(version("pythonnet"))').Trim()
if ($netVersion -cne $config.pythonnet_version) { throw 'Wrong pythonnet version.' }
$env:PYTHON_DLL=$pythonInfo.dll
$env:PYTHON_HOME=$pythonInfo.home
$env:PYTHONNET_RUNTIME='coreclr'
$env:PYTHONPATH=(& $PythonExe -c 'import site,os; print(os.pathsep.join(site.getsitepackages()))').Trim()
$env:PYTHONDONTWRITEBYTECODE='1'
$staged=Join-Path $OutputRoot 'application'
New-Item -ItemType Directory -Path $staged | Out-Null
Copy-Item -LiteralPath (Join-Path $RosRoot 'hfi_ros_wss_driver') -Destination $staged -Recurse
Copy-Item -LiteralPath (Join-Path $RosRoot 'package.xml') -Destination $staged
$bundle=Join-Path $staged 'HFI_WSS_Python_Interface'
New-Item -ItemType Directory -Path $bundle | Out-Null
Copy-Item -LiteralPath (Join-Path $WrapperRoot 'src') -Destination $bundle -Recurse
$env:WSS_PYTHON_SOURCE=Join-Path $bundle 'src'
$env:WSS_ROS_SOURCE=$staged
$env:WSS_ROS_FIXTURES=Join-Path $RosRoot 'tests'
$env:WSS_PYTHON_PAYLOAD=$projectionRoot
& (Join-Path $PSScriptRoot 'Prepare-ProfiledRosHarness.ps1') -CanonicalFixturePath $contract.fixture -TestRoot $tests.root -ExpectedFixtureHash $contract.fixture_sha256 -ExpectedAssertions $contract.assertion_expressions -Destination $harness -ProjectionRoot $projectionRoot -Role $Role -RosRoot $RosRoot -PythonRuntimeAssembly $pythonInfo.assembly
if (!$?) { throw 'Portable harness preparation failed.' }
Push-Location $harness
try { $sdk=(& dotnet --version).Trim(); if ($LASTEXITCODE -ne 0 -or $sdk -cne $config.dotnet_sdk) { throw 'Wrong .NET SDK.' } } finally { Pop-Location }
$logPath=Join-Path $OutputRoot 'dotnet.log'
$errorPath=Join-Path $OutputRoot 'dotnet-stderr.log'
$nunit=Join-Path $OutputRoot 'nunit'
$arguments=@('test','Wss.DotNet.Conformance.Tests.csproj','-p:DisablePackageAssetsCache=true','--logger','"trx;LogFileName=results.trx"','--results-directory',('"'+(Join-Path $OutputRoot 'test-results')+'"'),'--blame-hang-timeout','2m','--',('NUnit.TestOutputXml="'+$nunit+'"'))
$process=Start-Process -FilePath (Get-Command dotnet).Source -WorkingDirectory $harness -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput $logPath -RedirectStandardError $errorPath -PassThru
if (!$process.WaitForExit($TimeoutSeconds*1000)) { $process.Kill($true); $process.WaitForExit(); throw 'Disposable .NET conformance timed out; no acceptance evidence emitted.' }
if ((Get-Item -LiteralPath $errorPath).Length) { [IO.File]::AppendAllText($logPath,[IO.File]::ReadAllText($errorPath)) }
Get-Content -LiteralPath $logPath | Write-Output
if ($process.ExitCode -ne 0) { throw ".NET test exit $($process.ExitCode). Inspect dotnet.log." }
$results=@(Get-ChildItem -LiteralPath $nunit -Filter '*.xml' -File)
if ($results.Count -ne 1) { throw 'Expected exactly one real NUnit result file.' }
$xmlPath=Join-Path $OutputRoot 'results.xml'
Copy-Item -LiteralPath $results[0].FullName -Destination $xmlPath
Assert-PythonProfileResults $xmlPath $contract $Stage
foreach ($name in @('WSS_Core_Interface.dll','Newtonsoft.Json.dll','System.Security.Permissions.dll')) {
    $binary=Join-Path $harness "bin/Debug/net9.0/$name"
    if ((Get-FileHash -LiteralPath $binary).Hash -cne (Get-FileHash -LiteralPath (Join-Path $projectionRoot $name)).Hash) { throw "Test output used a different payload assembly: $name" }
}
Assert-PythonProjection $projectionRoot $projection
Assert-PythonSource $WrapperRoot $WrapperSha
Assert-PythonSource $RosRoot $RosSha -IgnoreSubmodule
$null=Resolve-PythonOrdinaryTooling -ToolsRoot $ToolsRoot -ToolsSha $ToolsSha -ConfigPath $ConfigPath -WrapperRoot $WrapperRoot -WrapperSha $WrapperSha
$inputs=Get-Content -LiteralPath (Join-Path $harness 'conformance-inputs.json') -Raw | ConvertFrom-Json
if ($inputs.assertion_expressions -ne $contract.assertion_expressions -or $inputs.canonical_fixture_sha256 -cne $contract.fixture_sha256) { throw 'Harness provenance mismatch.' }
$evidence=[ordered]@{
    schema='wss-python-profile-evidence/v1'; profile=$profile.profile; producer_commit=$candidate.commit; core_dll_sha256=$profile.core_dll_sha256; execution='pythonnet'; role=$Role; mode=$Mode; candidate=$candidate
    tools_sha=$ToolsSha; tooling_config_sha256=$tooling.tooling_config_sha256; wrapper_sha=$WrapperSha; ros_sha=$RosSha; fixture_sha=$contract.fixture_commit; fixture_sha256=$contract.fixture_sha256
    sdk=$sdk; target_framework='net9.0'; test_framework='NUnit 3.14.0'; python_executed=$true
    python=$pythonInfo.version; pythonnet=$netVersion
    run_repository=$env:GITHUB_REPOSITORY; run_id=$env:GITHUB_RUN_ID; run_sha=$env:GITHUB_SHA
    discovered=$caseCount; executed=$caseCount; passed=$caseCount; failed=0; skipped=0; assertion_expressions=$contract.assertion_expressions; stage=$Stage
    projection_sha256=$projection.projection_sha256
    results_sha256=(Get-FileHash -LiteralPath $xmlPath).Hash.ToLowerInvariant()
    log_sha256=(Get-FileHash -LiteralPath $logPath).Hash.ToLowerInvariant()
}
$evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputRoot 'evidence.json')
Copy-Item -LiteralPath (Join-Path $WrapperRoot '.github/python-candidate.json') -Destination (Join-Path $OutputRoot 'projection.json')

    Write-Output "PASS: $($profile.profile) ${Stage}: $caseCount canonical cases; $($contract.assertion_expressions) preserved assertions; exact product Python executed."
}
if($profile.profile -ceq 'layered-v1' -and @($stages).Count -eq 2){
    $single=Get-Content (Join-Path $rootOutput 'evidence.json') -Raw | ConvertFrom-Json
    Assert-PythonMultiStageEvidence $rootOutput $single $contract
    $multi=Get-Content (Join-Path $rootOutput 'multi/evidence.json') -Raw | ConvertFrom-Json
    foreach($field in @('profile','producer_commit','core_dll_sha256','tools_sha','tooling_config_sha256')){if($single.$field -cne $multi.$field){throw 'Profile identity differs between mandatory stages.'}}
}
if(@($stages).Count -eq 2 -or $profile.profile -ceq 'legacy-v1'){Assert-PythonProfileEvidence $rootOutput $profile $projection}
$recheck=Resolve-WssReviewedProfile $projectionRoot $candidate
if($recheck.profile -cne $profile.profile -or $recheck.core_dll_sha256 -cne $profile.core_dll_sha256){throw 'Verified product capability changed during execution.'}
} finally {$env:WSS_CONFORMANCE_STAGE=$previousStage}
