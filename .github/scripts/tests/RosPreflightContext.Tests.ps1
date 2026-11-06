$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Exercise the actual precredential workflow blocks. These fixtures establish
# wiring and caller/root checks, not canonical producer acceptance. The real
# Assert-PythonProducer and frozen Core authorization still run in live preflights.
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$workflowPath = Join-Path $repositoryRoot '.github/workflows/wss-preflight.yml'
$parser = @'
import json, sys, yaml
with open(sys.argv[1], encoding='utf-8') as stream:
    print(json.dumps(yaml.safe_load(stream)))
'@
$raw = & python -c $parser $workflowPath
if ($LASTEXITCODE -ne 0) { throw 'Cannot parse the production preflight workflow.' }
$workflow = ($raw -join "`n") | ConvertFrom-Json -AsHashtable
$resolverJobs = @('python-core', 'platform-compatibility', 'macos-architectures')
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('ROS context $(literal) with spaces ' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $sandbox
$environmentKeys = @('GITHUB_ACTIONS','GITHUB_REPOSITORY','GITHUB_EVENT_NAME','GITHUB_REF','GITHUB_REF_NAME','GITHUB_SHA','GITHUB_WORKFLOW_SHA','GITHUB_WORKFLOW_REF','GITHUB_WORKSPACE','GITHUB_OUTPUT','ROS_MODE','WSS_CI_CHANNEL','WSS_TARGET_ROOT','WSS_CORE_TOOLS_ROOT','WRAPPER_SHA','ROS_SHA','CANDIDATE_JSON','CORRELATION','GH_TOKEN')
$savedEnvironment = @{}
foreach ($key in $environmentKeys) { $savedEnvironment[$key] = [Environment]::GetEnvironmentVariable($key) }

function Invoke-FixtureGit([string]$Root, [string[]]$GitArguments) {
    $result = & git -C $Root @GitArguments
    if ($LASTEXITCODE -ne 0) { throw "Fixture git failed: $($GitArguments -join ' ')" }
    $result
}
function Commit-Fixture([string]$Root) {
    $null = Invoke-FixtureGit $Root @('-c','core.autocrlf=false','add','.')
    $null = Invoke-FixtureGit $Root @('-c','user.name=CI Context Fixture','-c','user.email=ci-context@example.invalid','-c','core.autocrlf=false','commit','-q','-m','context fixture')
    ((Invoke-FixtureGit $Root @('rev-parse','HEAD')) -join '').Trim()
}
function Write-Json([string]$Path, $Value) {
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 40), [Text.UTF8Encoding]::new($false))
}
function New-Fixture {
    $workspace = Join-Path $sandbox ([guid]::NewGuid().ToString('N'))
    $sourceRoot = Join-Path $workspace 'source'
    $coreRoot = Join-Path $workspace 'workflow-guard'
    $null = New-Item -ItemType Directory -Path $sourceRoot, $coreRoot -Force
    [IO.File]::WriteAllText((Join-Path $coreRoot 'fixture.txt'), 'precredential checkout identity only')
    $null = Invoke-FixtureGit $coreRoot @('init','-q')
    $coreSha = Commit-Fixture $coreRoot
    $null = New-Item -ItemType Directory -Path (Join-Path $sourceRoot '.github/scripts'), (Join-Path $sourceRoot '.github/workflows') -Force
    Copy-Item -LiteralPath (Join-Path $repositoryRoot '.github/scripts/wss-ci') -Destination (Join-Path $sourceRoot '.github/scripts/wss-ci') -Recurse
    Copy-Item -LiteralPath $workflowPath -Destination (Join-Path $sourceRoot '.github/workflows/wss-preflight.yml')
    Copy-Item -LiteralPath (Join-Path $repositoryRoot '.github/python-ci.json') -Destination (Join-Path $sourceRoot '.github/python-ci.json')
    $lock = Get-Content -LiteralPath (Join-Path $repositoryRoot '.github/scripts/wss-ci.lock.json') -Raw | ConvertFrom-Json -AsHashtable
    $lock.source_commit = $coreSha
    $lock.source_ref = "refs/heads/ci/tooling/$coreSha"
    Write-Json (Join-Path $sourceRoot '.github/scripts/wss-ci.lock.json') $lock
    $null = Invoke-FixtureGit $sourceRoot @('init','-q')
    $sourceSha = Commit-Fixture $sourceRoot
    @{ workspace=$workspace; source=$sourceRoot; core=$coreRoot; sourceSha=$sourceSha; coreSha=$coreSha }
}
function Get-Wiring($Document, [string]$JobName) {
    $steps = @($Document.jobs[$JobName].steps)
    $source = @($steps | Where-Object { $_.Contains('id') -and $_.id -eq 'sources' })
    $lock = @($steps | Where-Object { $_.Contains('id') -and $_.id -eq 'guard' })
    $checkout = @($steps | Where-Object { $_.Contains('uses') -and $_.uses -eq 'actions/checkout@v4' -and $_.Contains('with') -and $_.with.Contains('repository') -and $_.with.repository -eq 'cwru-non-academic/WSSCore' })
    $verify = @($steps | Where-Object { $_.Contains('name') -and $_.name -eq 'Verify locked Core guard checkout before credentials' })
    if ($source.Count -ne 1 -or $lock.Count -ne 1 -or $checkout.Count -ne 1 -or $verify.Count -ne 1) { throw 'Missing or ambiguous production candidate boundary/guard checkout.' }
    if ($checkout[0].with.ref -cne '${{ steps.guard.outputs.commit }}' -or $checkout[0].with.path -cne 'workflow-guard' -or $checkout[0].with['persist-credentials'] -ne $false) { throw 'Core checkout is not the declared immutable guard.' }
    $sourceCheckout = @($steps | Where-Object { $_.Contains('uses') -and $_.uses -eq 'actions/checkout@v4' -and $_.Contains('with') -and $_.with.Contains('path') -and $_.with.path -eq 'source' })
    if ($sourceCheckout.Count -ne 1 -or $sourceCheckout[0].with['persist-credentials'] -ne $false -or ($sourceCheckout[0].with.Contains('repository') -and $sourceCheckout[0].with.repository -cne 'cwru-non-academic/ROS_Python_WSS_Application')) { throw 'Source checkout is not the ROS target.' }
    $positions = @{}
    $firstCredential = $steps.Count
    for ($index=0; $index -lt $steps.Count; $index++) {
        if ([object]::ReferenceEquals($steps[$index], $source[0])) { $positions.source=$index }
        if ([object]::ReferenceEquals($steps[$index], $lock[0])) { $positions.lock=$index }
        if ([object]::ReferenceEquals($steps[$index], $checkout[0])) { $positions.checkout=$index }
        if ([object]::ReferenceEquals($steps[$index], $verify[0])) { $positions.verify=$index }
        if ($steps[$index].Contains('uses') -and $steps[$index].uses -like 'actions/create-github-app-token@*') { $firstCredential=[Math]::Min($firstCredential,$index) }
    }
    if (!($positions.source -lt $positions.lock -and $positions.lock -lt $positions.checkout -and $positions.checkout -lt $positions.verify -and $positions.verify -lt $firstCredential)) { throw 'Candidate guards must execute before credentials.' }
    @{ source=$source[0]; lock=$lock[0]; verify=$verify[0]; job=$Document.jobs[$JobName] }
}
function Expand-ContextValue([string]$Value, $Frame) {
    $result = [regex]::Replace($Value, '\$\{\{\s*([^}]+?)\s*\}\}', {
        param($match)
        $key=$match.Groups[1].Value.Trim()
        if (!$Frame.Contains($key)) { throw "Unmodelled workflow context: $key" }
        [string]$Frame[$key]
    }.GetNewClosure())
    $result
}
function Run-Boundary($Document, [string]$JobName, $Fixture, [string]$Channel, [string]$Mutation='') {
    foreach ($key in $environmentKeys) { [Environment]::SetEnvironmentVariable($key, $null) }
    $wiring = Get-Wiring $Document $JobName
    if ($Mutation -like 'poisoned-*') {
        $Fixture['trustedSha']=$Fixture.sourceSha
        $channelPath=Join-Path $Fixture.source '.github/scripts/wss-ci/Channel.ps1'
        $probe=@'
[IO.File]::WriteAllText((Join-Path $env:GITHUB_WORKSPACE 'UNTRUSTED_HELPER_EXECUTED'), 'input-selected PowerShell helper executed')
'@
        [IO.File]::WriteAllText($channelPath, $probe+"`n"+[IO.File]::ReadAllText($channelPath), [Text.UTF8Encoding]::new($false))
        $verifyPath=Join-Path $Fixture.source '.github/scripts/wss-ci/verify.mjs'
        $nodeProbe="import {writeFileSync as __rosSourceTripwire} from 'node:fs'; __rosSourceTripwire(process.env.GITHUB_WORKSPACE+'/UNTRUSTED_HELPER_EXECUTED','input-selected Node helper executed');"
        [IO.File]::WriteAllText($verifyPath, $nodeProbe+"`n"+[IO.File]::ReadAllText($verifyPath), [Text.UTF8Encoding]::new($false))
        if ($Mutation -ne 'poisoned-dirty') { $Fixture.sourceSha=Commit-Fixture $Fixture.source }
    }
    $candidate = @{repository='cwru-non-academic/WSSCore';commit=('b'*40);run_id='11';artifact_id='22';archive='WSS-Universal-ci.zip';sha256=('c'*64)} | ConvertTo-Json -Compress
    $wrapper = 'a'*40
    $frame = @{'github.ref_name'=$Channel;'github.workspace'=$Fixture.workspace;'matrix.arch'='x64';'inputs.wrapper_sha'=$wrapper;'inputs.ros_sha'=$Fixture.sourceSha;'inputs.candidate_json'=$candidate;'inputs.correlation_id'="wss-11-22-$wrapper-$($Fixture.sourceSha)"}
    $env:GITHUB_ACTIONS='true'; $env:GITHUB_REPOSITORY='cwru-non-academic/ROS_Python_WSS_Application'; $env:GITHUB_EVENT_NAME='workflow_dispatch'
    $env:GITHUB_REF="refs/heads/$Channel"; $env:GITHUB_REF_NAME=$Channel; $env:GITHUB_SHA=$Fixture.sourceSha; $env:GITHUB_WORKFLOW_SHA=$Fixture.sourceSha
    $env:GITHUB_WORKFLOW_REF="$($env:GITHUB_REPOSITORY)/.github/workflows/wss-preflight.yml@$($env:GITHUB_REF)"
    $env:GITHUB_WORKSPACE=$Fixture.workspace; $env:GITHUB_OUTPUT=Join-Path $Fixture.workspace 'outputs.txt'
    $jobEnvironment = if ($wiring.job.Contains('env')) { $wiring.job.env } else { $null }
    foreach ($scope in @($Document.env, $jobEnvironment, $wiring.source.env)) {
        if ($null -ne $scope) { foreach ($key in $scope.Keys) { [Environment]::SetEnvironmentVariable($key,(Expand-ContextValue ([string]$scope[$key]) $frame)) } }
    }
    switch ($Mutation) {
        'missing-channel' { $env:WSS_CI_CHANNEL=$null }
        'unknown-channel' { $env:WSS_CI_CHANNEL='other' }
        'swapped-channel' { $env:WSS_CI_CHANNEL=if($Channel -eq 'dev'){'main'}else{'dev'} }
        'wrong-ref' { $env:GITHUB_REF='refs/heads/feature' }
        'wrong-event' { $env:GITHUB_EVENT_NAME='pull_request' }
        'wrong-repository' { $env:GITHUB_REPOSITORY='cwru-non-academic/Other' }
        'wrong-workflow' { $env:GITHUB_WORKFLOW_REF="$($env:GITHUB_REPOSITORY)/.github/workflows/other.yml@$($env:GITHUB_REF)" }
        'wrong-source' { $env:GITHUB_SHA='d'*40 }
        'wrong-workflow-source' { $env:GITHUB_WORKFLOW_SHA='d'*40 }
        'wrong-input-source' { $env:ROS_SHA='d'*40 }
        'wrong-wrapper' { $env:WRAPPER_SHA='not-a-sha' }
        'wrong-correlation' { $env:CORRELATION='another-candidate' }
        'malformed-candidate' { $env:CANDIDATE_JSON='{}' }
        'target-root-swap' {
            $neighbor=Join-Path $Fixture.workspace 'neighbor wrapper with same lock'
            Copy-Item -LiteralPath $Fixture.source -Destination $neighbor -Recurse -Force
            $env:WSS_TARGET_ROOT=$neighbor
        }
        'guard-root-swap' {
            $neighbor=Join-Path $Fixture.workspace 'neighbor guard with same revision'
            Copy-Item -LiteralPath $Fixture.core -Destination $neighbor -Recurse -Force
            $env:WSS_CORE_TOOLS_ROOT=$neighbor
        }
        'guard-revision' {
            [IO.File]::WriteAllText((Join-Path $Fixture.core 'later.txt'),'later equivalent checkout')
            $null=Commit-Fixture $Fixture.core
        }
        'dirty-guard' { [IO.File]::WriteAllText((Join-Path $Fixture.core 'fixture.txt'),'changed') }
        'not-actions' { $env:GITHUB_ACTIONS='false' }
        'poisoned-source' { $env:GITHUB_SHA=$Fixture.trustedSha; $env:GITHUB_WORKFLOW_SHA=$Fixture.trustedSha }
        'poisoned-workflow-source' { $env:GITHUB_WORKFLOW_SHA=$Fixture.trustedSha }
        'poisoned-input-source' { $env:ROS_SHA=$Fixture.trustedSha }
        'poisoned-ref' { $env:GITHUB_REF='refs/heads/feature'; $env:GITHUB_WORKFLOW_REF="$($env:GITHUB_REPOSITORY)/.github/workflows/wss-preflight.yml@$($env:GITHUB_REF)" }
        'poisoned-workflow' { $env:GITHUB_WORKFLOW_REF="$($env:GITHUB_REPOSITORY)/.github/workflows/other.yml@$($env:GITHUB_REF)" }
    }
    & ([scriptblock]::Create($wiring.source.run))
    & ([scriptblock]::Create($wiring.lock.run))
    & ([scriptblock]::Create($wiring.verify.run))
    if (!(Test-Path -LiteralPath $env:GITHUB_OUTPUT)) { throw 'Boundary did not emit its validated bindings.' }
    $bindings = @(Get-Content -LiteralPath $env:GITHUB_OUTPUT)
    if (@($bindings | Where-Object { $_ -ceq "wrapper=$wrapper" }).Count -ne 1 -or @($bindings | Where-Object { $_ -ceq "commit=$($Fixture.coreSha)" }).Count -ne 1) { throw 'Declared checkout outputs differ from the validated source/guard.' }
    # Credential acquisition, canonical producer reads and artifact/runtime steps
    # deliberately remain outside this precredential contract fixture.
}
function Expect-Rejection($Document, [string]$JobName, $Fixture, [string]$Channel, [string]$Mutation, [string]$Expected) {
    $rejected=$false
    try { Run-Boundary $Document $JobName $Fixture $Channel $Mutation } catch {
        if ($_.Exception.Message -notmatch $Expected) { throw "Unexpected rejection for $JobName/$Mutation : $($_.Exception.Message)" }
        $rejected=$true
    }
    if (!$rejected) { throw "Candidate boundary accepted $JobName/$Mutation" }
    if (Test-Path -LiteralPath (Join-Path $Fixture.workspace 'UNTRUSTED_HELPER_EXECUTED')) { throw "Source helper executed before identity rejection: $JobName/$Mutation" }
}

try {
    $reference = Get-Wiring $workflow $resolverJobs[0]
    foreach ($jobName in $resolverJobs) {
        $wiring=Get-Wiring $workflow $jobName
        if ($wiring.source.run -cne $reference.source.run -or $wiring.lock.run -cne $reference.lock.run -or $wiring.verify.run -cne $reference.verify.run) { throw 'Resolver jobs must share identical guard implementations.' }
        foreach ($channel in @('dev','main')) { Run-Boundary $workflow $jobName (New-Fixture) $channel }
        $cases=@{
            'missing-channel'='explicit CI channel'; 'unknown-channel'='CI channel'; 'swapped-channel'='Target workflow ref';
            'wrong-ref'='Target workflow ref'; 'wrong-event'='registered ROS dispatch'; 'wrong-repository'='registered ROS dispatch';
            'wrong-workflow'='workflow identity'; 'wrong-source'='exact workflow source'; 'wrong-workflow-source'='exact workflow source';
            'wrong-input-source'='exact workflow source'; 'wrong-wrapper'='exact wrapper source'; 'wrong-correlation'='correlation mismatch';
            'malformed-candidate'='Canonical candidate identity'; 'target-root-swap'='verified ROS checkout';
            'guard-root-swap'='declared checkout'; 'guard-revision'='revision differs'; 'dirty-guard'='must be clean'; 'not-actions'='registered ROS dispatch'
            'poisoned-source'='exact workflow source'; 'poisoned-workflow-source'='exact workflow source'; 'poisoned-input-source'='exact workflow source';
            'poisoned-ref'='Target workflow ref'; 'poisoned-workflow'='workflow identity'; 'poisoned-dirty'='source must be clean'
        }
        foreach ($caseName in $cases.Keys) { Expect-Rejection $workflow $jobName (New-Fixture) 'main' $caseName $cases[$caseName] }
        # Prove the behavioral regression detects the previous unsafe ordering:
        # this deliberately bad fixture imports the alternate helper too early.
        $earlyImport=$workflow|ConvertTo-Json -Depth 100|ConvertFrom-Json -AsHashtable
        $sourceLine='$source = (& git -C $root rev-parse HEAD).Trim()'
        $tripwireImport='. (Join-Path $root ''.github/scripts/wss-ci/Channel.ps1'')'
        foreach($step in $earlyImport.jobs[$jobName].steps){if($step.Contains('id') -and $step.id -eq 'sources'){$step.run=$step.run.Replace($sourceLine,$tripwireImport+"`n"+$sourceLine)}}
        $detected=$false
        try { Expect-Rejection $earlyImport $jobName (New-Fixture) 'main' 'poisoned-source' 'exact workflow source' } catch {
            if ($_.Exception.Message -notmatch 'Source helper executed before identity rejection') { throw }
            $detected=$true
        }
        if (!$detected) { throw 'Ordering regression did not detect early helper execution.' }
        $fixture=New-Fixture
        $configPath=Join-Path $fixture.source '.github/python-ci.json'
        $config=Get-Content $configPath -Raw|ConvertFrom-Json -AsHashtable; $config.channels=@('dev'); Write-Json $configPath $config
        $fixture.sourceSha=Commit-Fixture $fixture.source
        Expect-Rejection $workflow $jobName $fixture 'main' '' 'capability'
        $fixture=New-Fixture
        $lockPath=Join-Path $fixture.source '.github/scripts/wss-ci.lock.json'
        $lock=Get-Content $lockPath -Raw|ConvertFrom-Json -AsHashtable; $lock.repository='cwru-non-academic/Python_WSS_Integration_Lib'; Write-Json $lockPath $lock
        $fixture.sourceSha=Commit-Fixture $fixture.source
        Expect-Rejection $workflow $jobName $fixture 'main' '' 'ROS-owned immutable'
        foreach ($mutation in @('remove-channel','remove-guard','floating-guard')) {
            $changed=$workflow|ConvertTo-Json -Depth 100|ConvertFrom-Json -AsHashtable
            switch ($mutation) {
                'remove-channel' { $null=$changed.env.Remove('WSS_CI_CHANNEL'); $expected='explicit CI channel' }
                'remove-guard' { $changed.jobs[$jobName].steps=@($changed.jobs[$jobName].steps|Where-Object {!($_.Contains('with') -and $_.with.Contains('path') -and $_.with.path -eq 'workflow-guard')}); $expected='Missing or ambiguous' }
                'floating-guard' { foreach($step in $changed.jobs[$jobName].steps){if($step.Contains('with') -and $step.with.Contains('path') -and $step.with.path -eq 'workflow-guard'){$step.with.ref='main'}}; $expected='immutable guard' }
            }
            Expect-Rejection $changed $jobName (New-Fixture) 'main' '' $expected
        }
    }
    Write-Output 'PASS: actual three-job ROS candidate boundaries, both channels, actor/source/root/lock/guard negatives, literal paths, and missing-wiring mutations; no producer or receipt emission.'
} finally {
    foreach ($key in $environmentKeys) { [Environment]::SetEnvironmentVariable($key,$savedEnvironment[$key]) }
    $full=[IO.Path]::GetFullPath($sandbox)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
    if (!$full.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($full) -notlike 'ROS context *') { throw 'Refusing fixture cleanup outside its explicit temporary sandbox.' }
    Remove-Item -LiteralPath $full -Recurse -Force
}
