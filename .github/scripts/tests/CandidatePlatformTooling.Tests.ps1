# Nonloading test: actual workflow run blocks stop at a fabricated child sentinel.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. "$PSScriptRoot/../RosOrdinaryTooling.ps1"
$parser='import json,sys,yaml; print(json.dumps(yaml.safe_load(open(sys.argv[1],encoding="utf-8"))))'
$raw=& python -c $parser (Join-Path $root '.github/workflows/wss-preflight.yml')
if($LASTEXITCODE){throw 'Cannot parse candidate workflow.'}
$workflow=($raw -join [Environment]::NewLine)|ConvertFrom-Json -AsHashtable
$ordinary=Get-Content (Join-Path $root '.github/workflows/ros-ci.yml') -Raw
$pin=Read-RosOrdinaryToolsPin $ordinary
$sandbox=Join-Path ([IO.Path]::GetTempPath()) ('ros candidate tools '+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $sandbox
$count=0
$keys=@('GITHUB_WORKSPACE','GITHUB_SHA','RUNNER_TEMP','WRAPPER_SHA','ROS_TOOLING_SENTINEL')
$saved=@{};foreach($key in $keys){$saved[$key]=[Environment]::GetEnvironmentVariable($key)}
function Write-Fixture([string]$Path,[string]$Text){$null=New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force;[IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false))}
function Commit-Fixture([string]$Path){& git -C $Path -c core.autocrlf=false add .;if($LASTEXITCODE){throw 'Fixture add failed.'};& git -C $Path -c user.name=Fixture -c user.email=fixture@example.invalid -c core.autocrlf=false commit -qm fixture;if($LASTEXITCODE){throw 'Fixture commit failed.'};(& git -C $Path rev-parse HEAD).Trim()}
function New-Fixture {
 $workspace=Join-Path $sandbox ([guid]::NewGuid().ToString('N'))
 $tools=Join-Path $workspace 'tools';$source=Join-Path $workspace 'source'
 $contract=@'
function Assert-PythonSource([string]$Root,[string]$Sha,[switch]$IgnoreSubmodule){
 if([IO.Path]::GetFullPath($Root) -cne [IO.Path]::GetFullPath((Join-Path $env:GITHUB_WORKSPACE 'source')) -or $Sha -cne $env:GITHUB_SHA){throw 'Fabricated ROS source binding mismatch.'}
}
'@
 $sentinel=@'
param([string]$ToolsRoot,[string]$ToolsSha,[string]$ConfigPath,[string]$WrapperRoot,[string]$WrapperSha,[string]$FixtureRoot,[string]$OutputRoot,[string]$PythonExe,[string]$Mode,[string]$ArtifactRoot,[string]$CandidatePath)
$PSBoundParameters | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $env:ROS_TOOLING_SENTINEL
throw 'ROS_SYNTHETIC_CHILD_BOUNDARY'
'@
 Write-Fixture (Join-Path $tools '.github/scripts/PythonContract.ps1') $contract
 Write-Fixture (Join-Path $tools '.github/scripts/Invoke-PlatformCompatibility.ps1') $sentinel
 Write-Fixture (Join-Path $tools '.github/python-ci.json') '{"fixture_commit":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"}'
 & git -C $tools init -q;$toolSha=Commit-Fixture $tools
 Write-Fixture (Join-Path $source '.github/workflows/ros-ci.yml') ($ordinary.Replace($pin,$toolSha))
 foreach($name in @('RosOrdinaryTooling.ps1','Invoke-RosPlatformCompatibility.ps1')){Write-Fixture (Join-Path $source ".github/scripts/$name") (Get-Content (Join-Path $root ".github/scripts/$name") -Raw)}
 & git -C $source init -q;$sourceSha=Commit-Fixture $source
 foreach($path in @('wrapper','fixture','runner')){$null=New-Item -ItemType Directory -Path (Join-Path $workspace $path)}
 @{workspace=$workspace;tools=$tools;source=$source;toolsSha=$toolSha;sourceSha=$sourceSha}
}
function Get-Wiring($Document,[string]$Job){
 $steps=@($Document.jobs[$Job].steps)
 $byPath=@{}
 foreach($path in @('tools','wrapper','fixture','source')){
  $matches=@($steps|Where-Object {$_.Contains('with') -and $_.with.Contains('path') -and $_.with.path -ceq $path})
  if($matches.Count -ne 1){throw 'Missing or ambiguous candidate checkout.'};$byPath[$path]=$matches[0]
 }
 $runner=@($steps|Where-Object {$_.Contains('name') -and $_.name -ceq 'Check actual application contracts, model and platform runtime'})
 if($runner.Count -ne 1){throw 'Missing or ambiguous candidate runner.'}
 if($byPath.tools.with.repository -cne 'cwru-non-academic/Python_WSS_Integration_Lib' -or $byPath.tools.with.ref -cne $pin -or $byPath.tools.with['persist-credentials'] -ne $false){throw 'Candidate tools must equal reviewed ordinary immutable pin.'}
 if($byPath.wrapper.with.repository -cne 'cwru-non-academic/Python_WSS_Integration_Lib' -or $byPath.wrapper.with.ref -cne '${{ needs.python-core.outputs.wrapper }}' -or $byPath.source.with.ref -cne '${{ inputs.ros_sha }}'){throw 'Candidate product checkout selection changed.'}
 if($byPath.fixture.with.repository -cne 'cwru-non-academic/CSharp_WSS_Integration_Lib' -or $byPath.fixture.with.ref -cnotmatch '^[a-f0-9]{40}$'){throw 'Candidate fixture checkout is not exact.'}
 if($runner[0].Contains('if') -or $runner[0].Contains('continue-on-error')){throw 'Candidate platform runner may not be bypassed.'}
 $runner[0].run
}
function Invoke-Fixture($Document,[string]$Job,[string]$Mutation=''){
 $run=Get-Wiring $Document $Job;$f=New-Fixture
 $env:GITHUB_WORKSPACE=$f.workspace;$env:GITHUB_SHA=$f.sourceSha;$env:RUNNER_TEMP=Join-Path $f.workspace 'runner';$env:WRAPPER_SHA='b'*40;$env:ROS_TOOLING_SENTINEL=Join-Path $f.workspace 'sentinel.json'
 switch($Mutation){
  'wrong-source' {$env:GITHUB_SHA='f'*40}
  'dirty-source' {[IO.File]::AppendAllText((Join-Path $f.source '.github/workflows/ros-ci.yml'),'dirty')}
  'dirty-tools' {[IO.File]::AppendAllText((Join-Path $f.tools '.github/python-ci.json'),'dirty')}
  'wrong-tools-checkout' {Write-Fixture (Join-Path $f.tools 'later.txt') 'later';$null=Commit-Fixture $f.tools}
 }
 Push-Location $f.workspace
 try {& ([scriptblock]::Create($run));throw 'Synthetic runner did not stop before runtime.'}catch{
  if($_.Exception.Message -cne 'ROS_SYNTHETIC_CHILD_BOUNDARY'){throw}
 }finally{Pop-Location}
 if(!(Test-Path -LiteralPath $env:ROS_TOOLING_SENTINEL)){throw 'Candidate child sentinel was not reached.'}
 $actual=Get-Content -LiteralPath $env:ROS_TOOLING_SENTINEL -Raw|ConvertFrom-Json -AsHashtable
 $expected=@{ToolsRoot=$f.tools;ToolsSha=$f.toolsSha;ConfigPath=(Join-Path $f.tools '.github/python-ci.json');WrapperRoot=(Join-Path $f.workspace 'wrapper');WrapperSha=('b'*40);FixtureRoot=(Join-Path $f.workspace 'fixture');OutputRoot=(Join-Path $env:RUNNER_TEMP 'ros-platform/wrapper-platform');PythonExe='python';Mode='candidate';ArtifactRoot=(Join-Path $env:RUNNER_TEMP 'resolved/extracted/WSS-Universal');CandidatePath=(Join-Path $env:RUNNER_TEMP 'resolved/candidate.json')}
 foreach($key in $expected.Keys){if(!$actual.Contains($key)){throw "Missing emitted candidate argument $key"};$a=[string]$actual[$key];$b=[string]$expected[$key];if($key -match 'Root$|Path$'){$a=[IO.Path]::GetFullPath($a);$b=[IO.Path]::GetFullPath($b)};if($a -cne $b){throw "Wrong emitted candidate argument $key"}}
 $script:count++
}
function Reject([string]$Name,[scriptblock]$Action){$caught=$false;try{& $Action}catch{$caught=$true};if(!$caught){throw "Accepted candidate mutation $Name"};$script:count++}
try{
 foreach($job in @('platform-compatibility','macos-architectures')){
  Invoke-Fixture $workflow $job
  foreach($mutation in @('wrong-source','dirty-source','dirty-tools','wrong-tools-checkout')){Reject "$job/$mutation" {Invoke-Fixture $workflow $job $mutation}}
  foreach($mutation in @('mutable-pin','wrong-repository','missing-tools','product-pin','missing-sha','wrong-sha','product-as-tools','wrong-role-mode','wrong-fixture','bypass')){
   $changed=$workflow|ConvertTo-Json -Depth 100|ConvertFrom-Json -AsHashtable
   foreach($step in $changed.jobs[$job].steps){
    if($step.Contains('with') -and $step.with.Contains('path') -and $step.with.path -ceq 'tools'){
     switch($mutation){'mutable-pin'{$step.with.ref='main'}'wrong-repository'{$step.with.repository='example/wrong'}'missing-tools'{$step.with.path='not-tools'}'product-pin'{$step.with.ref='${{ needs.python-core.outputs.wrapper }}'}}
    }
    if($step.Contains('name') -and $step.name -ceq 'Check actual application contracts, model and platform runtime'){
     switch($mutation){'missing-sha'{$step.run=$step.run.Replace(' -ToolsSha $toolsSha','')}'wrong-sha'{$step.run=$step.run.Replace('-ToolsSha $toolsSha',('-ToolsSha '+('f'*40)))}'product-as-tools'{$step.run=$step.run.Replace('-ToolsRoot "$env:GITHUB_WORKSPACE/tools"','-ToolsRoot "$env:GITHUB_WORKSPACE/wrapper"')}'wrong-role-mode'{$step.run=$step.run.Replace('-Mode candidate','-Mode committed')}'wrong-fixture'{$step.run=$step.run.Replace('-FixtureRoot "$env:GITHUB_WORKSPACE/fixture"','-FixtureRoot "$env:GITHUB_WORKSPACE/tools"')}'bypass'{$step['if']='false'}}
    }
   }
   Reject "$job/$mutation" {Invoke-Fixture $changed $job}
  }
 }
 Write-Output "PASS: $count actual ROS candidate workflow/runner sentinel routes and mutations; no product/native execution."
}finally{
 foreach($key in $keys){[Environment]::SetEnvironmentVariable($key,$saved[$key])}
 $full=[IO.Path]::GetFullPath($sandbox);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
 if(!$full.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($full) -notlike 'ros candidate tools *'){throw 'Unsafe fixture cleanup target.'}
 Remove-Item -LiteralPath $full -Recurse -Force
}
