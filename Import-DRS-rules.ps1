$viserver = 'tanzu-vcsa-1.tanzu.demo'

$infileDRSGroups = "c:\temp\drs-groups.txt"
$DRSGroups = Get-Content $infileDRSGroups

foreach($DRSGroup in $DRSGroups){
  $DRSGroupArr = $DRSGroup.Split(",")
  if($DRSGroupArr[2] -eq "VMHostGroup"){
    Get-Cluster $DRSGroupArr[0] -Server $viserver | `
    New-DrsClusterGroup -Name $DRSGroupArr[1] -VMHost (Get-VMHost -Name ($DRSGroupArr[3..($DRSGroupArr.Count - 1)])) | Out-Null
  } else {
    Get-Cluster $DRSGroupArr[0] -Server $viserver | `
    New-DrsClusterGroup -Name $DRSGroupArr[1] -VM (Get-VM -Name ($DRSGroupArr[3..($DRSGroupArr.Count - 1)])) | Out-Null
  }
}

$infileVMToHosts = "c:\temp\drs-rules-vm_to_hosts.txt"
$rules = Get-Content $infileVMToHosts

foreach($rule in $rules){
  $ruleArr = $rule.Split(",")
  if($ruleArr[2] -eq "True"){$rEnabled = $true} else {$rEnabled = $false}
  switch ($ruleArr[4]) {
    ShouldRunOn {$rMustOrShould = 'ShouldRunOn'}
    MustRunOn {$rMustOrShould = 'MustRunOn'}
    ShouldNotRunOn {$rMustOrShould = 'ShouldNotRunOn'}
    MustNotRunOn {$rMustOrShould = 'MustNotRunOn'}
  }
  New-DrsVMHostRule -Cluster (Get-Cluster $ruleArr[0] -Server $viserver) -Name $ruleArr[1] -Enabled $rEnabled -Type $rMustOrShould -VMGroup $ruleArr[3] -VMHostGroup $ruleArr[5] | Out-Null
}

$infileAffinityAntiAffinity = "c:\temp\drs-rules-AffinityAntiAffinity.txt"
$rules = Get-Content $infileAffinityAntiAffinity
Write-Host
foreach($rule in $rules){
  $ruleArr = $rule.Split(",")
  if($ruleArr[2] -eq "True"){$rEnabled = $true} else {$rEnabled = $false}
  if($ruleArr[3] -eq "VMAffinity"){$rTogether = $true} else {$rTogether = $false}
  New-DrsRule -Cluster (Get-Cluster $ruleArr[0] -Server $viserver) -Name $ruleArr[1] -Enabled $rEnabled -KeepTogether $rTogether -VM (Get-VM -Name ($ruleArr[4..($ruleArr.Count - 1)])) | Out-Null
}