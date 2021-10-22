$si = Get-View ServiceInstance
$alarmMgr = Get-View -Id $si.Content.AlarmManager

# AlarmSpec
$alarm = New-Object VMware.Vim.AlarmSpec
$alarm.Name = "vCenter administrator@vsphere.local Logon"
$alarm.Description = "administrator@vsphere.local account logon to vCenter"
$alarm.Enabled = $true

# Transition - green --> red
$trans = New-Object VMware.Vim.AlarmTriggeringActionTransitionSpec
$trans.StartState = "green"
$trans.FinalState = "Yellow"

# Expression - Login
$expression = New-Object VMware.Vim.EventAlarmExpression
$expression.EventType = 'UserLoginSessionEvent'
$expression.objectType = "Datacenters"
$expression.status = "Yellow"

# Root login
$comparison = New-Object VMware.Vim.EventAlarmExpressionComparison
$comparison.AttributeName = 'userName'
$comparison.Operator = 'equals'
$comparison.Value = 'VSPHERE.LOCAL\Administrator'
$expression.Comparisons += $comparison
$alarm.expression = New-Object VMware.Vim.OrAlarmExpression
$alarm.expression.expression += $expression
$alarm.setting = New-Object VMware.Vim.AlarmSetting
$alarm.setting.reportingFrequency = 0
$alarm.setting.toleranceRange = 0
$alarmMgr.CreateAlarm($si.Content.RootFolder,$alarm)