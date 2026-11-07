$ErrorActionPreference='Stop'
. "$PSScriptRoot/../RosSelectedContext.ps1"
$temp=Join-Path ([IO.Path]::GetTempPath()) ('ros-context-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory $temp
$temp=(& python -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve())' $temp).Trim()
$null=New-Item -ItemType Directory -Path (Join-Path $temp 'core') -Force
'core fixture' | Set-Content (Join-Path $temp 'core/code.mjs')
$roots=@{selection_id=('a'*64);test_root=(Join-Path $temp 'tests');products=@(
    @{repository='cwru-non-academic/ROS_Python_WSS_Application';commit=('b'*40);path=(Join-Path $temp 'ros')},
    @{repository='cwru-non-academic/Python_WSS_Integration_Lib';commit=('c'*40);path=(Join-Path $temp 'wrapper')},
    @{repository='cwru-non-academic/CSharp_WSS_Integration_Lib';commit=('d'*40);path=(Join-Path $temp 'fixture')}
)}
$roots | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $temp 'roots.json')
'{"scope":"run"}' | Set-Content (Join-Path $temp 'context.json')
$script:events=[Collections.Generic.List[string]]::new()
$script:failure=''
function Invoke-ReviewedSelectionCore($CoreRoot,$Operation,$TargetId,$ContextPath,$RootsPath,$EvidencePath='') {
    if($TargetId -cne 'python-ros'){throw 'Wrong target role.'}
    $script:events.Add($Operation)
    if($Operation -ceq $script:failure){throw 'Injected Core failure'}
    [pscustomobject]@{selection_id=('a'*64);test_commit=('e'*40);test_repository='cwru-non-academic/ROS_Python_WSS_Application'}
}
$realChild=${function:Invoke-RosIsolatedChild}
function Invoke-RosIsolatedChild($Script,$Options) {
    $script:events.Add($Options.Phase)
    if($Options.TestRoot -cne $roots.test_root -or $Options.RosRoot -cne $roots.products[0].path){throw 'Root selection changed.'}
    if($script:failure -ceq 'child'){throw 'Injected child failure'}
    if($Options.Phase -ceq 'baseline') {
        $baseline=Join-Path $Options.OutputRoot 'baseline'
        $null=New-Item -ItemType Directory -Path $baseline -Force
        '{"profile":"legacy-v1"}' | Set-Content (Join-Path $Options.OutputRoot 'profile.json')
        foreach($file in @('evidence.json','results.xml','dotnet.log','projection.json')){'baseline proof' | Set-Content (Join-Path $baseline $file)}
    } elseif($script:failure -ceq 'mutate-core') {
        $probe=Join-Path $temp 'mutate-core.ps1'
        'param([string]$EvidencePath); "tampered" | Set-Content -LiteralPath $EvidencePath' | Set-Content $probe
        & $realChild $probe @{EvidencePath=(Join-Path $temp 'core/code.mjs')}
    } elseif($script:failure -ceq 'mutate-baseline') {
        $probe=Join-Path $temp 'mutate-baseline.ps1'
        'param([string]$EvidencePath); "tampered" | Set-Content -LiteralPath $EvidencePath' | Set-Content $probe
        & $realChild $probe @{EvidencePath=(Join-Path (Join-Path $Options.OutputRoot 'baseline') 'results.xml')}
    }
}
function Invoke-RosContextTest {
    param($CoreRoot,$ContextPath,$RootsPath,$WorkRoot,$ToolsRoot)
    Invoke-RosSelectedWithContext -CoreRoot $CoreRoot -ContextPath $ContextPath -RootsPath $RootsPath -WorkRoot ($WorkRoot+'-'+[guid]::NewGuid().ToString('N')) -ToolsRoot $ToolsRoot
}
$options=@{CoreRoot=(Join-Path $temp 'core');ContextPath=(Join-Path $temp 'context.json');RootsPath=(Join-Path $temp 'roots.json');WorkRoot=(Join-Path $temp 'output');ToolsRoot=$roots.products[1].path}
Invoke-RosContextTest @options
if(($events -join ',') -cne 'inspect,baseline,selected,evidence'){throw 'Core verification ordering changed.'}
$script:observedCampaign=$null
$recordingChild=${function:Invoke-RosIsolatedChild}
function Invoke-RosIsolatedChild($Script,$Options){$script:observedCampaign=$Options.SelectionEnabledCampaign; & $recordingChild $Script $Options}
'{"scope":"campaign"}' | Set-Content (Join-Path $temp 'context.json')
Invoke-RosContextTest @options
if($observedCampaign -cne $true){throw 'Authenticated campaign lost modern-only requirement.'}
'{"scope":"run"}' | Set-Content (Join-Path $temp 'context.json')
Invoke-RosContextTest @options
if($observedCampaign -cne $false){throw 'Ordinary run incorrectly forced modern.'}
${function:Invoke-RosIsolatedChild}=$recordingChild
foreach($failure in @('inspect','child','mutate-baseline','mutate-core')){
    $events.Clear();$script:failure=$failure;$rejected=$false
    try{Invoke-RosContextTest @options}catch{$rejected=$true}
    if(!$rejected -or $events.Contains('evidence')){throw 'Failure emitted evidence.'}
}
$script:failure=''
foreach($change in @(@{WorkRoot=(Join-Path $roots.test_root 'output')},@{ToolsRoot=$roots.test_root},@{Mode='candidate'})){
    $bad=$options.Clone();foreach($key in $change.Keys){$bad[$key]=$change[$key]}
    $rejected=$false;try{Invoke-RosSelectedWithContext @bad}catch{$rejected=$true}
    if(!$rejected){throw 'Invalid sources/output/candidate accepted.'}
}
${function:Invoke-RosIsolatedChild}=$realChild
$probe=Join-Path $temp 'probe.ps1'
@('param([string]$Unused)', 'foreach($name in @("GH_TOKEN","GITHUB_TOKEN","WSS_TEST_VARIABLE_READ_TOKEN","SAMPLE_SECRET","GITHUB_OUTPUT","PYTHONPATH")){if([Environment]::GetEnvironmentVariable($name)){throw "Secret/control leaked to child."}}','if(Get-Variable parentSecret -ErrorAction SilentlyContinue){throw "Parent PowerShell scope leaked."}') | Set-Content $probe
$names=@('GH_TOKEN','GITHUB_TOKEN','WSS_TEST_VARIABLE_READ_TOKEN','SAMPLE_SECRET','GITHUB_OUTPUT','PYTHONPATH');$prior=@{};$parentSecret='sentinel'
try{
    foreach($name in $names){$prior[$name]=[Environment]::GetEnvironmentVariable($name);[Environment]::SetEnvironmentVariable($name,'sentinel')}
    Invoke-RosIsolatedChild $probe @{Unused='x'}
    'exit 7' | Add-Content $probe
    $rejected=$false;try{Invoke-RosIsolatedChild $probe @{Unused='x'}}catch{$rejected=$true}
    if(!$rejected){throw 'Child failure ignored.'}
    foreach($name in $names){if([Environment]::GetEnvironmentVariable($name) -cne 'sentinel'){throw 'Parent token changed.'}}
}finally{foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$prior[$name])}}
Write-Output 'PASS: ROS authenticated ordering, failure gates, exact roots, and real child environment/scope isolation.'
