$VIServer = 'tanzu-vcsa-1.tanzu.demo'

$si = Get-View serviceInstance -Server $VIServer
$alarmMgr = Get-View -Id $si.Content.AlarmManager -Server $VIServer
$alarms = Get-View -Id ($alarmMgr.GetAlarm($si.Content.RootFolder)) -Server $VIServer
$to = Get-Folder -Type Datacenter -Server $VIServer

# show to root folder to select from
Do {
  $i = 1
  foreach ($item in $to){
     If ($item.Name -inotlike "Datacenters"){
        Write-Host "$i. $($item.Name)"
        $i = $i + 1
     }
  }
  [int]$itemNumber = Read-Host -Prompt "`nEnter the number for the root folder"
} Until ($itemNumber -in 1..$to.Count) # -and ($clusterNumber -lt 1))

$folderName = ($to[$itemNumber]).Name
$to = Get-Folder -Type Datacenter -Name $folderName

# request a filter string
[string]$filter = Read-Host -Prompt "`nEnter a string to filter the alarms"
$filter = "*" + $filter +"*"

# show the filtered alarms
Do {
  Write-Host "`n"
  $i = 1
  foreach ($alarm in $alarms){ 
    $filteredAlarm = $alarm | Where {$_.Info.Name -ilike $filter}
    If ($filteredAlarm){
        Write-Host "$i. $($alarm.Info.Name)"
    }
    $i = $i + 1
  }
  [int]$alarmNumber = Read-Host -Prompt "`nEnter the number for the alarm"
} Until ($alarmNumber -in 1..($alarms.Count)) # -and ($clusterNumber -lt 1))

$alarm = $alarms[$alarmnumber - 1]

### Creation of alarm ###
#$alarm = $alarms | where{$_.Info.Name -match "^Host connection and power state"}
#$alarm = $alarms | where{$_.Info.Name -match "Test VM"}
Clear-Variable spec,expr2,exprState -ErrorAction SilentlyContinue

$spec = New-Object VMware.Vim.AlarmSpec
#$spec.Setting = New-Object VMware.Vim.AlarmSetting

$spec.Name = "$($folderName.Substring(0,3)) - $($alarm.Info.Name)"
Write-Host "`nThe following alarm will be created: $($spec.Name)" -ForegroundColor Green
$spec.Description = $alarm.Info.Description
$spec.Enabled = $true

### Compiling the State Expressions ###
$spec.Expression = New-Object VMware.Vim.OrAlarmExpression
$spec.Expression.Expression = $alarm.Info.Expression.Expression

### Creating the Alarms ###
$alarmMgr.CreateAlarm($to.ExtensionData.MoRef,$spec)