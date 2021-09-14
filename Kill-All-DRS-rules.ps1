#Cleanup
$cluster = 'tanzu-cluster'

Get-DrsClusterGroup -cluster $cluster * | Remove-DrsClusterGroup -Confirm:$false
get-drsrule -cluster $cluster | Remove-DrsRule -Confirm:$false
Get-DrsVMHostRule -cluster $cluster | Remove-DrsVMHostRule -Confirm:$false