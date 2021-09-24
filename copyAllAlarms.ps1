$VIServer = 'gvalxpvcsa1.vitol.com'

$si = Get-View serviceInstance -Server $VIServer
$alarmMgr = Get-View -Id $si.Content.AlarmManager -Server $VIServer
$alarms = Get-View -Id ($alarmMgr.GetAlarm($si.Content.RootFolder)) -Server $VIServer
$to = Get-Folder -Type Datacenter -Server $VIServer

$folderName = 'SINGAPORE' # Make sure this is capitalized correctly as the first 3 letters will be used as the start of the alarm
$to = Get-Folder -Type Datacenter -Name $folderName -Server $VIServer

$RequestedAlarms = Import-Csv .\alarms.csv -Header Name

# show the filtered alarms
foreach ($alarm in $alarms){
    foreach ($item in $RequestedAlarms){
        If ($item -match $alarm.Info.Name){
            Write-Host "$($alarm.Info.Name)   $($alarm.Info.Alarm.Value)"
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

            write-host $spec.Expression.Expression
            ### Creating the Alarms ###
            $alarmMgr.CreateAlarm($to.ExtensionData.MoRef,$spec)
        }
    }
}