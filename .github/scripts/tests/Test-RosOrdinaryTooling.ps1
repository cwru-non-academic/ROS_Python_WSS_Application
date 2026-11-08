param([string]$ToolsRoot='',[string]$ToolsSha='',[string]$WrapperRoot='',[string]$WrapperSha='',[string]$RosRoot='',[string]$RosSha='')
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../RosOrdinaryTooling.ps1"
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Reject([string]$Name,[scriptblock]$Action){$rejected=$false;try{& $Action}catch{$rejected=$true};if(!$rejected){throw "Accepted invalid binding: $Name"};Write-Output "Rejected: $Name"}
$sourceSha=(& git -C $repository rev-parse HEAD).Trim()
$pin=Read-RosOrdinaryToolsPin (Get-Content (Join-Path $repository '.github/workflows/ros-ci.yml') -Raw)
Reject 'wrong committed source SHA' {Get-RosOrdinaryToolsSha $repository ('f'*40)}
Reject 'wrong tools checkout SHA' {Assert-RosOrdinaryToolsCheckout $repository ('f'*40)}
if($pin -cnotmatch '^[a-f0-9]{40}$'){throw 'Missing ordinary pin.'}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('ros-tooling-negatives-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path (Join-Path $fixture '.github/workflows') -Force
$path=Join-Path $fixture '.github/workflows/ros-ci.yml'
$original=Get-Content (Join-Path $repository '.github/workflows/ros-ci.yml') -Raw
[IO.File]::WriteAllText($path,$original.Replace("ref: $pin",'ref: dev'))
Reject 'mutable tooling branch' {Read-RosOrdinaryToolsPin (Get-Content $path -Raw)}
$changed=[regex]::new([regex]::Escape("ref: $pin")).Replace($original,('ref: '+('a'*40)),1)
[IO.File]::WriteAllText($path,$changed)
Reject 'one divergent tooling pin' {Read-RosOrdinaryToolsPin (Get-Content $path -Raw)}
[IO.File]::WriteAllText($path,$original.Replace('path: tools','path: selected-tools'))
Reject 'missing tooling checkouts' {Read-RosOrdinaryToolsPin (Get-Content $path -Raw)}
[IO.File]::WriteAllText($path,$original)
& git -C $fixture init -q
& git -C $fixture add .
& git -C $fixture -c user.name=ContractFixture -c user.email=fixture@invalid commit -qm fixture
if($LASTEXITCODE -ne 0){throw 'Cannot commit source-binding fixture.'}
$fixtureSha=(& git -C $fixture rev-parse HEAD).Trim()
if((Get-RosOrdinaryToolsSha $fixture $fixtureSha) -cne $pin){throw 'Wrong committed fixture pin.'}
[IO.File]::AppendAllText($path,"`n# dirty workflow`n")
Reject 'dirty workflow source' {Get-RosOrdinaryToolsSha $fixture $fixtureSha}
if($ToolsRoot){
    . (Join-Path $ToolsRoot '.github/scripts/PythonContract.ps1')
    . (Join-Path $ToolsRoot '.github/scripts/PythonProfiles/Tooling.ps1')
    $options=@{ToolsRoot=$ToolsRoot;ToolsSha=$ToolsSha;ConfigPath=(Join-Path $ToolsRoot '.github/python-ci.json');WrapperRoot=$WrapperRoot;WrapperSha=$WrapperSha}
    $null=Resolve-PythonOrdinaryTooling @options
    Assert-RosOrdinaryProductPair $RosRoot $RosSha $WrapperSha
    Reject 'wrong tooling SHA' {Resolve-PythonOrdinaryTooling @options -ErrorAction Stop | Out-Null; Assert-PythonToolingBinding $ToolsRoot ('f'*40) $options.ConfigPath}
    Reject 'product config used as common config' {Assert-PythonToolingBinding $ToolsRoot $ToolsSha (Join-Path $WrapperRoot '.github/python-ci.json')}
    Reject 'product used as tooling checkout' {Assert-PythonToolingBinding $WrapperRoot $WrapperSha (Join-Path $WrapperRoot '.github/python-ci.json')}
    Reject 'wrapper gitlink substitution' {Assert-RosOrdinaryProductPair $RosRoot $RosSha ('a'*40)}
}
Write-Output 'PASS: ordinary ROS tooling and product bindings.'
# Keep the retired frontend contract in an actual ordinary CI job, not only local tests.
function Assert-ReceiptRetirementStep([string]$Workflow) {
    $text=$Workflow.Replace("`r`n","`n")
    $job=[regex]::Match($text,'(?ms)^  preflight-context-contracts:\n(?<body>.*?)(?=^  [a-zA-Z0-9_-]+:\n|\z)').Groups['body'].Value
    $step=(@'
      - name: Verify retired receipt entrypoint contract
        shell: pwsh
        run: node --test .github/scripts/tests/ReceiptEntrypointRetirement.test.mjs
'@).Replace("`r`n","`n")+"`n"
    $node=(@'
      - uses: actions/setup-node@v4
        with:
          node-version: '24'
'@).Replace("`r`n","`n")+"`n"
    if(!$job -or $job -match '(?m)^    (if|continue-on-error):' -or !$job.Contains($step) -or [regex]::Matches($job,'(?m)^        run: node --test \.github/scripts/tests/ReceiptEntrypointRetirement\.test\.mjs$').Count -ne 1){throw 'Ordinary CI must execute the complete unconditional retired receipt test step.'}
    if($job.IndexOf($node) -lt 0 -or $job.IndexOf($node) -gt $job.IndexOf($step)){throw 'Receipt retirement contract requires Node 24 before its test step.'}
    if($job.IndexOf('      - uses: actions/checkout@v4') -lt 0 -or $job.IndexOf('      - uses: actions/checkout@v4') -gt $job.IndexOf($step)){throw 'Receipt retirement contract requires its source checkout first.'}
}
$retirementWorkflow=Get-Content (Join-Path $repository '.github/workflows/ros-ci.yml') -Raw
Assert-ReceiptRetirementStep $retirementWorkflow
$retirementStep=(@'
      - name: Verify retired receipt entrypoint contract
        shell: pwsh
        run: node --test .github/scripts/tests/ReceiptEntrypointRetirement.test.mjs
'@).Replace("`r`n","`n")+"`n"
$retirementWorkflow=$retirementWorkflow.Replace("`r`n","`n")
foreach($changed in @(
    $retirementWorkflow.Replace($retirementStep,''),
    $retirementWorkflow.Replace($retirementStep,$retirementStep.Replace('        shell: pwsh',"        if: false`n        shell: pwsh")),
    $retirementWorkflow.Replace($retirementStep,$retirementStep.Replace('        shell: pwsh',"        continue-on-error: true`n        shell: pwsh")),
    $retirementWorkflow.Replace($retirementStep,$retirementStep.Replace('node --test','echo skipped')),
    $retirementWorkflow.Replace("node-version: '24'","node-version: '20'"),
    $retirementWorkflow.Replace("  preflight-context-contracts:`n","  preflight-context-contracts:`n    if: false`n")
)) {
    if($changed -ceq $retirementWorkflow){throw 'Retirement workflow mutation did not change its fixture.'}
    $rejected=$false;try{Assert-ReceiptRetirementStep $changed}catch{$rejected=$true}
    if(!$rejected){throw 'Disabled retirement workflow test was accepted.'}
}
Write-Output 'PASS: retired receipt hosted step and six disabling mutations.'
