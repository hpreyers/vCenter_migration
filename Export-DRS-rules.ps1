$viserver = 'tanzu-vcsa-1.tanzu.demo'
$clusterName = 'tanzu-cluster'

$outfileVMToHosts = "c:\temp\drs-rules-vm_to_hosts.txt"
Remove-Item $outfileVMToHosts
$rules = get-cluster -Name $clusterName | Get-DrsVMHostRule

foreach($rule in $rules){
  $line = (Get-View -Id $rule.Cluster.Id).Name
  $line += ("," + $rule.Name + "," + $rule.Enabled + "," + $rule.VMGroup + "," + $rule.Type + "," + $rule.VMHostGroup)
  
  $line | Out-File -Append $outfileVMToHosts 
}

$outfileAffinityAntiAffinity = "c:\temp\drs-rules-AffinityAntiAffinity.txt"
Remove-Item $outfileAffinityAntiAffinity
$rules = get-cluster -Name $clusterName | Get-DrsRule

foreach($rule in $rules){
  $line = (Get-View -Id $rule.Cluster.Id).Name
  $line += ("," + $rule.Name + "," + $rule.Enabled + "," + $rule.Type)
  foreach($vmId in $rule.VMIds){
    $line += ("," + (Get-View -Id $vmId).Name)
  }
  $line | Out-File -Append $outfileAffinityAntiAffinity 
}

$outfileDRSGroups = "c:\temp\drs-groups.txt"
Remove-Item $outfileDRSGroups
$DRSGroups = get-cluster -Name $clusterName | Get-DrsClusterGroup

foreach($DRSGroup in $DRSGroups){
  $line = (Get-View -Id $DRSGroup.Cluster.Id).Name
  $line += ("," + $DRSGroup.Name + "," + $DRSGroup.GroupType)
  foreach($member in $DRSGroup.Member){
    $line += ("," + $member.Name)
  }
  $line | Out-File -Append $outfileDRSGroups 
}
