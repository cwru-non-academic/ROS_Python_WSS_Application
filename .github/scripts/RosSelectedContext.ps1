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
    Invoke-RosIsolatedChild (Join-Path $PSScriptRoot 'Invoke-SelectedRosTests.ps1') $options
    Invoke-ReviewedSelectionCore $CoreRoot evidence 'python-ros' $ContextPath $RootsPath (Join-Path $work 'selection/evidence.json')
}
