$viserver = 'tanzu-vcsa-1.tanzu.demo'
$exportLocation = '.'
$clusters = Get-Cluster -Server $viserver

Do {
  $i = 1
  foreach ($cluster in $clusters){
    Write-Host "$i. $($cluster.Name)"
    $i = $i + 1
  }
  [int]$clusterNumber = Read-Host -Prompt "Enter the number for the cluster"
} Until ($clusterNumber -in 1..$clusters.Count) # -and ($clusterNumber -lt 1))

$clusterName = ($clusters[$clusterNumber-1]).Name

$outfileVMToHosts = "$exportLocation\$clusterName-drs-rules-vm_to_hosts.txt"
If (Test-path $outfileVMToHosts) {Remove-Item $outfileVMToHosts}
$rules = Get-Cluster -Server $viserver -Name $clusterName | Get-DrsVMHostRule

foreach($rule in $rules){
  $line = (Get-View -Id $rule.Cluster.Id).Name
  $line += ("," + $rule.Name + "," + $rule.Enabled + "," + $rule.VMGroup + "," + $rule.Type + "," + $rule.VMHostGroup)
  
  $line | Out-File -Append $outfileVMToHosts 
}

$outfileAffinityAntiAffinity = "$exportLocation\$clusterName-drs-rules-AffinityAntiAffinity.txt"
If (Test-path $outfileAffinityAntiAffinity) {Remove-Item $outfileAffinityAntiAffinity}
$rules = Get-Cluster -Server $viserver -Name $clusterName | Get-DrsRule

foreach($rule in $rules){
  $line = (Get-View -Id $rule.Cluster.Id).Name
  $line += ("," + $rule.Name + "," + $rule.Enabled + "," + $rule.Type)
  foreach($vmId in $rule.VMIds){
    $line += ("," + (Get-View -Id $vmId).Name)
  }
  $line | Out-File -Append $outfileAffinityAntiAffinity 
}

$outfileDRSGroups = "$exportLocation\$clusterName-drs-groups.txt"
If (Test-path $outfileDRSGroups) {Remove-Item $outfileDRSGroups}
$DRSGroups = Get-Cluster -Server $viserver -Name $clusterName | Get-DrsClusterGroup

foreach($DRSGroup in $DRSGroups){
  $line = (Get-View -Id $DRSGroup.Cluster.Id).Name
  $line += ("," + $DRSGroup.Name + "," + $DRSGroup.GroupType)
  foreach($member in $DRSGroup.Member){
    $line += ("," + $member.Name)
  }
  $line | Out-File -Append $outfileDRSGroups 
}
