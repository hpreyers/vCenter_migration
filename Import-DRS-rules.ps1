$viserver = 'tanzu-vcsa-1.tanzu.demo'
$clusters = Get-Cluster -Server
Do {
  $i = 1
  foreach ($cluster in $clusters){
    Write-Host "$i. $($cluster.Name)"
    $i = $i + 1
  }
  [int]$clusterNumber = Read-Host -Prompt "Enter the number for the cluster"
} Until ($clusterNumber -in 1..$clusters.Count) # -and ($clusterNumber -lt 1))
write $clusters.count
$clusterName = ($clusters[$clusterNumber]).Name
$infileDRSGroups = "c:\temp\drs-groups.txt"
$DRSGroups = Get-Content $infileDRSGroups

foreach($DRSGroup in $DRSGroups){
  $DRSGroupArr = $DRSGroup.Split(",")
  if($DRSGroupArr[2] -eq "VMHostGroup"){
    get-cluster $DRSGroupArr[0] -Server $viserver | `
    New-DrsClusterGroup -Name $DRSGroupArr[1] -VMHost (Get-VMHost -Name ($DRSGroupArr[3..($DRSGroupArr.Count - 1)])) | Out-Null
  } else {
    get-cluster $DRSGroupArr[0] -Server $viserver | `
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
  New-DrsVMHostRule -Cluster (get-cluster $ruleArr[0] -Server $viserver) -Name $ruleArr[1] -Enabled $rEnabled -Type $rMustOrShould -VMGroup $ruleArr[3] -VMHostGroup $ruleArr[5] | Out-Null
}

$infileAffinityAntiAffinity = "c:\temp\drs-rules-AffinityAntiAffinity.txt"
$rules = Get-Content $infileAffinityAntiAffinity
Write-Host
foreach($rule in $rules){
  $ruleArr = $rule.Split(",")
  if($ruleArr[2] -eq "True"){$rEnabled = $true} else {$rEnabled = $false}
  if($ruleArr[3] -eq "VMAffinity"){$rTogether = $true} else {$rTogether = $false}
  New-DrsRule -Cluster (get-cluster $ruleArr[0] -Server $viserver) -Name $ruleArr[1] -Enabled $rEnabled -KeepTogether $rTogether -VM (Get-VM -Name ($ruleArr[4..($ruleArr.Count - 1)])) | Out-Null
}