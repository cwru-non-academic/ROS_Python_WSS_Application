param([Parameter(Mandatory)][string]$MainRoot,[Parameter(Mandatory)][string]$DevRoot,[string]$LegacyRoot='')
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../RosCapabilityProfile.ps1"
$count=0
function Reject([scriptblock]$Action,[string]$Name){try{& $Action | Out-Null}catch{$script:count++;return};throw "Unexpected acceptance: $Name"}
# Read metadata, never load/execute the WSS assembly. Both current channel inputs
# can be layered; legacy shape coverage is independent of a channel nickname.
$mainApi=[WssProfileMetadata]::Read((Join-Path $MainRoot 'Cs_Libraries/WSS_Core_Interface.dll'))
$modern=[WssProfileMetadata]::Read((Join-Path $DevRoot 'Cs_Libraries/WSS_Core_Interface.dll'))
if((Get-WssCapabilityProfile $mainApi) -cnotin @('legacy-v1','layered-v1') -or (Get-WssCapabilityProfile $modern) -cne 'layered-v1'){throw 'Actual baseline profile mismatch.'};$count+=2
$legacy=[Collections.Generic.Dictionary[string,string[]]]::new([StringComparer]::Ordinal)
foreach($type in @('Wss.Testing.WssBehaviorScenarios','Wss.Testing.IWssConformance')){$legacy.Add($type,$modern[$type])}
if((Get-WssCapabilityProfile $legacy) -cne 'legacy-v1'){throw 'Complete baseline-only API must retain legacy eligibility.'};$count++
foreach($type in @('Wss.Testing.WssStimulationSequence','Wss.Testing.WssStimulationStep','Wss.Testing.WssStimulationSequences','Wss.Testing.WssStimulationWindow','Wss.Testing.WssStimulationWindowResult','Wss.CoreModule.WssConfigurationSnapshot')){
 $broken=[Collections.Generic.Dictionary[string,string[]]]::new($modern,[StringComparer]::Ordinal)
 $null=$broken.Remove($type)
 Reject {Get-WssCapabilityProfile $broken} "missing $type"
 foreach($member in $modern[$type] | Where-Object {$_ -ne '.ctor'}) {
  $broken=[Collections.Generic.Dictionary[string,string[]]]::new($modern,[StringComparer]::Ordinal)
  $broken[$type]=@($modern[$type] | Where-Object {$_ -cne $member})
  Reject {Get-WssCapabilityProfile $broken} "missing $type.$member"
 }
 $partial=[Collections.Generic.Dictionary[string,string[]]]::new($legacy,[StringComparer]::Ordinal)
 $partial.Add($type,$modern[$type]);Reject {Get-WssCapabilityProfile $partial} "legacy plus $type"
}
foreach($type in @('Wss.Testing.WssBehaviorScenarios','Wss.Testing.IWssConformance')){
 foreach($member in $legacy[$type]){
  $broken=[Collections.Generic.Dictionary[string,string[]]]::new($legacy,[StringComparer]::Ordinal)
  $broken[$type]=@($legacy[$type] | Where-Object {$_ -cne $member})
  Reject {Get-WssCapabilityProfile $broken} "missing baseline $type.$member"
 }
}
$mainProducer=(Get-Content (Join-Path $MainRoot '.github/python-candidate.json') -Raw | ConvertFrom-Json).candidate
$devProducer=(Get-Content (Join-Path $DevRoot '.github/python-candidate.json') -Raw | ConvertFrom-Json).candidate
foreach($case in @(@($MainRoot,$mainProducer),@($DevRoot,$devProducer))){
 $resolved=Resolve-WssReviewedProfile (Join-Path $case[0] 'Cs_Libraries') $case[1]
 if($resolved.profile -ceq 'layered-v1'){$null=Resolve-WssReviewedProfile (Join-Path $case[0] 'Cs_Libraries') $case[1] -SelectionEnabledCampaign;$count++}
 else {Reject {Resolve-WssReviewedProfile (Join-Path $case[0] 'Cs_Libraries') $case[1] -SelectionEnabledCampaign} 'campaign cannot downgrade to legacy'}
 $count++
}
# A layered package remains eligible outside a hard-coded producer allowlist.
# Its actual producer authenticity is established upstream, not by this helper.
$unlisted=$devProducer | ConvertTo-Json | ConvertFrom-Json
$unlisted.commit='f'*40
$null=Resolve-WssReviewedProfile (Join-Path $DevRoot 'Cs_Libraries') $unlisted -SelectionEnabledCampaign;$count++
foreach($key in @('repository','commit','archive','sha256','run_id','artifact_id')){
 $changed=$devProducer | ConvertTo-Json | ConvertFrom-Json
 $changed.$key='wrong'
 Reject {Resolve-WssReviewedProfile (Join-Path $DevRoot 'Cs_Libraries') $changed} "malformed producer $key"
}
# Keep the immutable legacy producer/package binding checks available without
# assuming that current main still carries that historical binary.
if($LegacyRoot){
 $old=(Get-Content (Join-Path $LegacyRoot '.github/python-candidate.json') -Raw | ConvertFrom-Json).candidate
 $null=Resolve-WssReviewedProfile (Join-Path $LegacyRoot 'Cs_Libraries') $old;$count++
 Reject {Resolve-WssReviewedProfile (Join-Path $LegacyRoot 'Cs_Libraries') $old -SelectionEnabledCampaign} 'campaign cannot downgrade to legacy'
 Reject {Resolve-WssReviewedProfile (Join-Path $LegacyRoot 'Cs_Libraries') $devProducer} 'legacy DLL modern producer'
 Reject {Resolve-WssReviewedProfile (Join-Path $DevRoot 'Cs_Libraries') $old} 'modern DLL legacy producer'
 foreach($key in @('repository','commit','archive','sha256','run_id','artifact_id')){
  $changed=$old | ConvertTo-Json | ConvertFrom-Json
  $changed.$key=if($key -ceq 'commit'){'f'*40}else{'wrong'}
  Reject {Resolve-WssReviewedProfile (Join-Path $LegacyRoot 'Cs_Libraries') $changed} "wrong legacy producer $key"
 }
} else {Write-Output 'NOT RUN: optional historical legacy producer/package binding; no LegacyRoot supplied.'}
"$count profile checks passed (metadata only; no product execution)."
