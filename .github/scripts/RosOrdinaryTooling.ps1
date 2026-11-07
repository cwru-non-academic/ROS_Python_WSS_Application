# Read only the immutable tools checkout declarations from this reviewed workflow.
# No mutable ref, selected source, product gitlink or checkout HEAD selects tooling.
function Get-RosOrdinaryToolsSha([string]$RosRoot,[string]$RosSha) {
    if($RosSha -cnotmatch '^[a-f0-9]{40}$'){throw 'Exact ROS workflow source SHA required.'}
    if((& git -C $RosRoot rev-parse HEAD).Trim() -cne $RosSha -or $LASTEXITCODE -ne 0){throw 'ROS workflow checkout differs from expected source.'}
    $dirty=& git -C $RosRoot status --porcelain --untracked-files=all --ignore-submodules=all
    if($LASTEXITCODE -ne 0 -or $dirty){throw 'ROS workflow source must remain clean.'}
    $workflow=(& git -C $RosRoot show "${RosSha}:.github/workflows/ros-ci.yml") -join "`n"
    if($LASTEXITCODE -ne 0){throw 'Cannot read committed ROS workflow.'}
    Read-RosOrdinaryToolsPin $workflow
}
function Assert-RosOrdinaryToolsCheckout([string]$ToolsRoot,[string]$ToolsSha) {
    if($ToolsSha -cnotmatch '^[a-f0-9]{40}$' -or (& git -C $ToolsRoot rev-parse HEAD).Trim() -cne $ToolsSha -or $LASTEXITCODE -ne 0){throw 'Tools checkout differs from committed workflow pin.'}
    $dirty=& git -C $ToolsRoot status --porcelain --untracked-files=all
    if($LASTEXITCODE -ne 0 -or $dirty){throw 'Tools checkout must remain clean.'}
}
function Read-RosOrdinaryToolsPin([string]$workflow) {
    $blocks=[regex]::Matches($workflow,'(?m)^      - uses: actions/checkout@v4\r?\n        with:\r?\n(?:(?:          .*)?\r?\n)+')
    $pins=@()
    foreach($block in $blocks){
        if($block.Value -match '(?m)^          path: tools\r?$'){
            if($block.Value -notmatch '(?m)^          repository: cwru-non-academic/Python_WSS_Integration_Lib\r?$' -or $block.Value -notmatch '(?m)^          persist-credentials: false\r?$'){throw 'Unexpected ordinary tooling checkout.'}
            $pin=[regex]::Match($block.Value,'(?m)^          ref: ([a-f0-9]{40})\r?$')
            if(!$pin.Success){throw 'Ordinary tooling requires an immutable literal checkout ref.'}
            $pins+=$pin.Groups[1].Value
        }
    }
    if($pins.Count -ne 5 -or @($pins | Select-Object -Unique).Count -ne 1){throw 'Every ordinary tooling checkout must use the same reviewed immutable source.'}
    $pins[0]
}
function Assert-RosOrdinaryProductPair([string]$RosRoot,[string]$RosSha,[string]$WrapperSha) {
    Assert-PythonSource $RosRoot $RosSha -IgnoreSubmodule
    Assert-PythonSha $WrapperSha
    $entry=Invoke-PythonGit $RosRoot @('ls-tree',$RosSha,'--','HFI_WSS_Python_Interface')
    if($entry -cnotmatch '^160000 commit ([a-f0-9]{40})\s+HFI_WSS_Python_Interface$' -or $Matches[1] -cne $WrapperSha){throw 'Ordinary ROS must retain its exact committed wrapper gitlink; use candidate preflight for a proposed replacement.'}
}
