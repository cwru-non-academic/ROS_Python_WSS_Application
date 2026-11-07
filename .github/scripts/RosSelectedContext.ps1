. "$PSScriptRoot/SelectedTestContext.ps1"

function Invoke-RosIsolatedChild([string]$Script,[hashtable]$Options) {
    # A child interpreter prevents selected code seeing parent's saved-token variables.
    $start=[Diagnostics.ProcessStartInfo]::new((Get-Command pwsh -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source)
    $start.UseShellExecute=$false
    $start.CreateNoWindow=$true
    foreach($name in @($start.Environment.Keys)) {
        if($name -match 'TOKEN|SECRET|PASSWORD|PRIVATE.?KEY|CREDENTIAL' -or $name -in @('GITHUB_OUTPUT','GITHUB_ENV','GITHUB_PATH','GITHUB_STATE','GITHUB_STEP_SUMMARY','PYTHONPATH','PYTHONSTARTUP','SSH_AUTH_SOCK','SSH_AGENT_PID','GIT_ASKPASS','GIT_SSH_COMMAND')) {$null=$start.Environment.Remove($name)}
    }
    foreach($argument in @('-NoLogo','-NoProfile','-NonInteractive','-File',$Script)) {$start.ArgumentList.Add($argument)}
    foreach($key in $Options.Keys){if($Options[$key] -is [bool]){if($Options[$key]){$start.ArgumentList.Add("-$key")}}else{$start.ArgumentList.Add("-$key");$start.ArgumentList.Add([string]$Options[$key])}}
    $process=[Diagnostics.Process]::Start($start)
    if(!$process.WaitForExit(1800000)){$process.Kill($true);$process.WaitForExit();throw 'ROS selected child timed out.'}
    if($process.ExitCode -ne 0){throw 'Mandatory or selected ROS suite failed; no selection evidence emitted.'}
}

function Get-RosBaselineSnapshot([string]$Root,[string]$Profile) {
    if (!(Test-Path -LiteralPath $Root -PathType Container)) { throw 'Mandatory baseline output is missing.' }
    $stages=if($Profile -ceq 'layered-v1'){@('', 'multi')}elseif($Profile -ceq 'legacy-v1'){@('')}else{throw 'Unknown baseline evidence profile.'}
    foreach($stage in $stages){foreach($name in @('evidence.json','results.xml','dotnet.log','projection.json')){
        if(!(Test-Path -LiteralPath (Join-Path (Join-Path $Root $stage) $name) -PathType Leaf)){throw 'Mandatory baseline evidence file is missing.'}
    }}
    $entries=@(Get-ChildItem -LiteralPath $Root -Recurse -Force)
    if((Get-Item -LiteralPath $Root -Force).Attributes -band [IO.FileAttributes]::ReparsePoint -or @($entries | Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}).Count){throw 'Baseline output cannot contain redirected paths.'}
    @($entries | Where-Object {!$_.PSIsContainer} | ForEach-Object {
        [IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/')+'|'+(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    } | Sort-Object -CaseSensitive) -join "`n"
}

function Invoke-RosSelectedWithContext {
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
    $ErrorActionPreference='Stop'
    $binding=Invoke-ReviewedSelectionCore $CoreRoot inspect 'python-ros' $ContextPath $RootsPath
    $context=Get-Content -LiteralPath $ContextPath -Raw | ConvertFrom-Json
    $roots=Get-Content -LiteralPath $RootsPath -Raw | ConvertFrom-Json
    $ros=Get-SelectedProduct $roots 'cwru-non-academic/ROS_Python_WSS_Application'
    $wrapper=Get-SelectedProduct $roots 'cwru-non-academic/Python_WSS_Integration_Lib'
    $fixture=Get-SelectedProduct $roots 'cwru-non-academic/CSharp_WSS_Integration_Lib'
    # ToolsRoot is immutable product tooling, never a selected test checkout.
    if([IO.Path]::GetFullPath($ToolsRoot) -cne [IO.Path]::GetFullPath($wrapper.path)){throw 'ToolsRoot must be the declared immutable wrapper product.'}
    $work=[IO.Path]::GetFullPath($WorkRoot)
    $ancestor=$work;$tail=[Collections.Generic.List[string]]::new()
    while(!(Test-Path -LiteralPath $ancestor)){$tail.Insert(0,[IO.Path]::GetFileName($ancestor));$ancestor=[IO.Path]::GetDirectoryName($ancestor)}
    $physical=(Get-Item -LiteralPath $ancestor -Force).ResolveLinkTarget($true)
    if($physical){$ancestor=$physical.FullName}
    foreach($part in $tail){$ancestor=Join-Path $ancestor $part}
    if([IO.Path]::GetFullPath($ancestor) -cne $work){throw 'Output ancestors must not redirect through links.'}
    if(Test-Path -LiteralPath $work){throw 'Validation work root must be new.'}
    foreach($source in @($roots.test_root)+@($roots.products.path)+@($CoreRoot)){
        $path=[IO.Path]::GetFullPath($source)
        if($work -eq $path -or $work.StartsWith($path+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Output must remain outside immutable source checkouts.'}
    }
    if($Mode -ceq 'candidate'){
        if(!$ArtifactRoot -or !$CandidatePath){throw 'Candidate mode requires authenticated resolver output.'}
    } elseif($ArtifactRoot -or $CandidatePath){throw 'Committed mode cannot accept candidate overrides.'}
    $options=@{RosRoot=$ros.path;RosSha=$ros.commit;WrapperRoot=$wrapper.path;WrapperSha=$wrapper.commit;FixtureRoot=$fixture.path;ToolsRoot=$ToolsRoot;ConfigPath=(Join-Path $wrapper.path '.github/python-ci.json');OutputRoot=$work;Mode=$Mode;PythonExe=$PythonExe;TestRoot=$roots.test_root;SelectionEnabledCampaign=($context.scope -ceq 'campaign')}
    if($Mode -ceq 'candidate'){$options.ArtifactRoot=$ArtifactRoot;$options.CandidatePath=$CandidatePath}
    $options.Phase='baseline'
    Invoke-RosIsolatedChild (Join-Path $PSScriptRoot 'Invoke-SelectedRosTests.ps1') $options
    $profilePath=Join-Path $work 'profile.json'
    $profile=Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
    $profileHash=(Get-FileHash -LiteralPath $profilePath -Algorithm SHA256).Hash
    $baselineRoot=Join-Path $work 'baseline'
    $baselineSnapshot=Get-RosBaselineSnapshot $baselineRoot $profile.profile
    $options.Phase='selected'
    Invoke-RosIsolatedChild (Join-Path $PSScriptRoot 'Invoke-SelectedRosTests.ps1') $options
    if((Get-FileHash -LiteralPath $profilePath -Algorithm SHA256).Hash -cne $profileHash -or (Get-RosBaselineSnapshot $baselineRoot $profile.profile) -cne $baselineSnapshot){throw 'Selected suite changed mandatory ROS baseline output; no selection evidence emitted.'}
    Invoke-ReviewedSelectionCore $CoreRoot evidence 'python-ros' $ContextPath $RootsPath (Join-Path $work 'selection/evidence.json')
}
