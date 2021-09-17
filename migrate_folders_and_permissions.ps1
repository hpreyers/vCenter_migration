<#
.SYNOPSIS
Migrate settings from a Source vCenter to a Destination vCenter
#

.DESCRIPTION
Migrate settings from a Source vCenter to a Destination vCenter

.EXAMPLE
No parameters are currently foreseen

.NOTES
No notes
#>

### GLOBAL VARIABLES

# Get vCenter Server Names
#$sourceVC = Read-Host "Please enter the name of the source Server"; 
#$destVC = Read-Host "Please enter the name of the destination Server"
$sourceVC = 'pivcss001.vconsultants.local'
#$sourceVC = 'ldnlxpvcsa1.vitol.com'
$destVC = 'tanzu-vcsa-1.tanzu.demo'
#$destVC = 'gvalxpvcsa1.vitol.com'
$ssoDomain = 'vsphere.local'
$strRolesCustomPrefix = 'VITOL' # based on this prefix string we will filter the roles to transfer
$sourceVCUser = 'administrator@vsphere.local'
$destVCUser = 'administrator@vsphere.local'
$sourceVCPass = 'd+P+31n*B%Q1'
$destVCPass = 'VMware123!'
# $sourceVCUser = 'tpphdp@geneva.vitol.com'
# $destVCUser = 'tpphdp@geneva.vitol.com'
# $sourceVCPass = ''
# $destVCPass = ''

$timeStamp = Get-Date -Format "yyMMdd_hhmmss"
#$exportPath = 'C:\TEMP\vCenterConfExport'
$exportPath = 'C:\TEMP\'
#$exportPath = "$($env:USERPROFILE)\Desktop"
$verboseLogFile = "$($exportPath)\$($timeStamp)_MigrationLog.log"
$LogToConsole = $true

# TEST OR DEBUG
$Test = $false # Run without execution on the destination
###

### FUNCTIONS

### Retrieve the whole path for a folder
filter Get-FolderPath {
    $_ | Get-View | % {
        $row = "" | select Name, Path
        $row.Name = $_.Name

        $current = Get-View $_.Parent
        $path = $_.Name

        do {
            $parent = $current
            if($parent.Name -ne "vm"){$path = $parent.Name + "\" + $path}
            $current = Get-View $current.Parent
        } while ($current.Parent -ne $null)
        $row.Path = $path
        $row
    }
}

Function MyLogger {
    param(
    [Parameter(Mandatory=$true)]
    [String]$Message,
    [String]$Color = 'White'
    )

    $timeStamp = Get-Date -Format "yyMMdd hh:mm:ss"

    If ($LogToConsole){
        Write-Host -NoNewline -ForegroundColor White "[$timestamp]"
        Write-Host -ForegroundColor  $color " $message"
    }
    $logMessage = "[$timeStamp] $message"
    $logMessage | Out-File -Append -LiteralPath $verboseLogFile
}

Function AddPermission {
    param(
        [Parameter(Mandatory=$true)]$ObjectSource,
        [Parameter(Mandatory=$true)]$ObjectDest
        )
    
    $authMgr = Get-View AuthorizationManager -Server $sourceVC
    $inherited = $false
    #$permisions = $authMgr.RetrieveEntityPermissions($rootFolder.ExtensionData.MoRef,$inherited)
    $permisions = $authMgr.RetrieveEntityPermissions($ObjectSource.ExtensionData.MoRef,$inherited)
    MyLogger -Message "Checking Permissions"

    foreach ($permission in $permisions) {
        $Domain = ($permission.Principal -split "\\")[0]
        If ($($Domain) -ine $($ssoDomain)){
            If ($permission.Group -eq $false){
                MyLogger -Message "Found user $($permission.Principal) on $($ObjectSource.Name) -- Updating on $($destVC)" -Color Green
            } else {
                MyLogger -Message "Found group $($permission.Principal) on $($ObjectSource.Name) -- Updating on $($destVC)" -Color Green
            }
            $authMgrDest = Get-View AuthorizationManager -Server $destVC
            $sourceRole = $authMgr.RoleList | where{$_.RoleId -eq $permission.RoleId}
            $roleName = $sourceRole.Name
            $destRole = $authMgrDest.RoleList | where{$_.Name -eq $roleName}

            $perm = New-Object VMware.Vim.Permission
            #$tmpPerm = $authMgrDest.RetrieveEntityPermissions($ObjectDest.ExtensionData.MoRef,$inherited)
            $perm.Entity = $ObjectSource.Id
            $perm.principal = $permission.Principal
            $perm.propagate = $permission.Propagate
            $perm.Group = $permission.Group
            $perm.roleid = $destRole.RoleId

            $authMgrDest.SetEntityPermissions($ObjectDest.ExtensionData.MoRef, @($perm))
        } else {
            MyLogger -Message "Found user $($permission.Principal) on $($ObjectSource.Name) -- Disregarding ssoDomain: $($ssoDomain)" -Color Red
        }
    }
    MyLogger -Message "Done Checking Permissions" -Color Blue
}

Function CheckCluster {
    param(
        [Parameter(Mandatory=$true)]$ObjectSource,
        [Parameter(Mandatory=$true)]$ObjectDest
        )

    $clusters = Get-cluster -Server $sourceVC -Location $ObjectSource | Sort-Object
    foreach ($cluster in $clusters) {
        MyLogger -Message "Checking Cluster: $($datacenter.Name)\$($cluster.Name)"
        MyLogger -Message "- DrsAutomationLevel: $($cluster.DrsAutomationLevel)"
        MyLogger -Message "- DrsEnabled: $($cluster.DrsEnabled)"
        MyLogger -Message "- EVCMode: $($cluster.EVCMode)"
        MyLogger -Message "- HAAdmissionControlEnabled: $($cluster.HAAdmissionControlEnabled)"
        MyLogger -Message "- HAEnabled: $($cluster.HAEnabled)"
        MyLogger -Message "- HAFailoverLevel: $($cluster.HAFailoverLevel)"
        MyLogger -Message "- HAIsolationResponse: $($cluster.HAIsolationResponse)"
        MyLogger -Message "- HARestartPriority: $($cluster.HARestartPriority)"
        MyLogger -Message "- VMSwapfilePolicy: $($cluster.VMSwapfilePolicy)"
        $clusterSettings = @{
            Name = $cluster.Name
            HAEnabled = If ($cluster.HAEnabled -eq $False) {$False} else {[Boolean]$cluster.HAEnabled}
            DrsEnabled = If ($cluster.DrsEnabled -eq $False) {$False} else {[Boolean]$cluster.DrsEnabled}
            VsanEnabled = If ($cluster.VsanEnabled -eq $False) {$False} else {[Boolean]$cluster.VsanEnabled}
            Confirm = $false
        }
        If ($destCluster = Get-Cluster -Server $destVC -Name "$($cluster.Name)" -Location $ObjectDest -ErrorAction Ignore) {
            MyLogger -Message "Cluster $($cluster.Name) already exists in $($destVC)" -Color Green
            $clusterExists = $true
        }
        else {
            MyLogger -Message "Creating Cluster $($cluster.Name) in $($ObjectDest.Name) in $($destVC)" -Color Yellow
            If (-not $Test) {
                $destCluster = New-Cluster -Server $destVC -Location $ObjectDest @clusterSettings -ErrorAction Ignore
                $clusterExists = $true
                #Start-Sleep 1
            }
        }
        If ($cluster.HAEnabled -eq $True -and $clusterExists -eq $true){
            MyLogger -Message "Setting Cluster HA Settings on $($cluster.Name) in $($ObjectDest.Name) in $($destVC)" -Color Yellow
            $spec = $null
            $spec = New-Object VMware.Vim.ClusterConfigSpecEx
            $spec.DasConfig = New-Object VMware.Vim.ClusterDasConfigInfo
            $spec.DasConfig.Enabled = $cluster.ExtensionData.Configuration.DasConfig.Enabled
            $spec.DasConfig.VmMonitoring = $cluster.ExtensionData.Configuration.DasConfig.VmMonitoring
            $spec.DasConfig.HostMonitoring = $cluster.ExtensionData.Configuration.DasConfig.HostMonitoring
            $spec.DasConfig.VmComponentProtecting = $cluster.ExtensionData.Configuration.DasConfig.VmComponentProtecting
            $spec.DasConfig.FailoverLevel = $cluster.ExtensionData.Configuration.DasConfig.FailoverLevel
            $spec.DasConfig.AdmissionControlPolicy = New-Object VMware.Vim.ClusterFailoverLevelAdmissionControlPolicy
            $spec.DasConfig.AdmissionControlEnabled = $cluster.ExtensionData.Configuration.DasConfig.AdmissionControlEnabled
            $spec.DasConfig.AdmissionControlPolicy.FailoverLevel = $cluster.ExtensionData.Configuration.DasConfig.AdmissionControlPolicy.FailoverLevel
            $spec.DasConfig.AdmissionControlPolicy.ResourceReductionToToleratePercent = $cluster.ExtensionData.Configuration.DasConfig.AdmissionControlPolicy.ResourceReductionToToleratePercent
            $spec.DasConfig.DefaultVmSettings = New-Object VMware.Vim.ClusterDasVmSettings
            $spec.DasConfig.DefaultVmSettings.RestartPriority = $cluster.ExtensionData.Configuration.DasConfig.DefaultVmSettings.RestartPriority
            $spec.DasConfig.DefaultVmSettings.RestartPriorityTimeout = $cluster.ExtensionData.Configuration.DasConfig.DefaultVmSettings.RestartPriorityTimeout
            $spec.DasConfig.DefaultVmSettings.IsolationResponse = $cluster.ExtensionData.Configuration.DasConfig.DefaultVmSettings.IsolationResponse
            $spec.DasConfig.DefaultVmSettings.VmToolsMonitoringSettings = New-Object VMware.Vim.ClusterVmToolsMonitoringSettings
            $spec.DasConfig.DefaultVmSettings.VmToolsMonitoringSettings.Enabled = $cluster.ExtensionData.Configuration.DasConfig.DefaultVmSettings.VmToolsMonitoringSettings.Enabled
            $spec.DasConfig.DefaultVmSettings.VmToolsMonitoringSettings.VmMonitoring = $cluster.ExtensionData.Configuration.DasConfig.DefaultVmSettings.VmToolsMonitoringSettings.VmMonitoring
            $spec.DasConfig.DefaultVmSettings.VmToolsMonitoringSettings.ClusterSettings = $cluster.ExtensionData.Configuration.DasConfig.DefaultVmSettings.VmToolsMonitoringSettings.ClusterSettings
            $spec.DasConfig.DefaultVmSettings.VmToolsMonitoringSettings.FailureInterval = $cluster.ExtensionData.Configuration.DasConfig.DefaultVmSettings.VmToolsMonitoringSettings.FailureInterval
            $spec.DasConfig.DefaultVmSettings.VmToolsMonitoringSettings.MinUpTime = $cluster.ExtensionData.Configuration.DasConfig.DefaultVmSettings.VmToolsMonitoringSettings.MinUpTime
            $spec.DasConfig.DefaultVmSettings.VmToolsMonitoringSettings.MaxFailures = $cluster.ExtensionData.Configuration.DasConfig.DefaultVmSettings.VmToolsMonitoringSettings.MaxFailures
            $spec.DasConfig.DefaultVmSettings.VmToolsMonitoringSettings.MaxFailureWindow = $cluster.ExtensionData.Configuration.DasConfig.DefaultVmSettings.VmToolsMonitoringSettings.MaxFailureWindow
            $spec.DasConfig.DefaultVmSettings.VmComponentProtectionSettings = New-Object VMware.Vim.ClusterVmComponentProtectionSettings
            $spec.DasConfig.DefaultVmSettings.VmComponentProtectionSettings.VmStorageProtectionForAPD = $cluster.ExtensionData.Configuration.DasConfig.DefaultVmSettings.VmComponentProtectionSettings.VmStorageProtectionForAPD
            $spec.DasConfig.DefaultVmSettings.VmComponentProtectionSettings.EnableAPDTimeoutForHosts = $cluster.ExtensionData.Configuration.DasConfig.DefaultVmSettings.VmComponentProtectionSettings.EnableAPDTimeoutForHosts
            $spec.DasConfig.DefaultVmSettings.VmComponentProtectionSettings.VmTerminateDelayForAPDSec = $cluster.ExtensionData.Configuration.DasConfig.DefaultVmSettings.VmComponentProtectionSettings.VmTerminateDelayForAPDSec
            $spec.DasConfig.DefaultVmSettings.VmComponentProtectionSettings.VmReactionOnAPDCleared = $cluster.ExtensionData.Configuration.DasConfig.DefaultVmSettings.VmComponentProtectionSettings.VmReactionOnAPDCleared
            $spec.DasConfig.DefaultVmSettings.VmComponentProtectionSettings.VmStorageProtectionForPDL = $cluster.ExtensionData.Configuration.DasConfig.DefaultVmSettings.VmComponentProtectionSettings.VmStorageProtectionForPDL
            $spec.DasConfig.Option = $cluster.ExtensionData.Configuration.DasConfig.Option
            $spec.DasConfig.HeartbeatDatastore = $cluster.ExtensionData.Configuration.DasConfig.HeartbeatDatastore
            $spec.DasConfig.HBDatastoreCandidatePolicy = $cluster.ExtensionData.Configuration.DasConfig.HBDatastoreCandidatePolicy
            $modify = $true
            $_this = Get-View -Id $destCluster.Id
            $_this.ReconfigureComputeResource_Task($spec, $modify) | Out-Null
        }
        If ($cluster.DrsEnabled -eq $True -and $clusterExists -eq $true){
            MyLogger -Message "Setting Cluster Drs Settings on $($cluster.Name) in $($ObjectDest.Name) in $($destVC)" -Color Yellow
            $spec = $null
            $spec = New-Object VMware.Vim.ClusterConfigSpecEx
            $spec.DrsConfig = New-Object VMware.Vim.ClusterDrsConfigInfo
            $spec.DrsConfig.Enabled = $cluster.ExtensionData.Configuration.DrsConfig.Enabled
            $spec.DrsConfig.EnableVmBehaviorOverrides = $cluster.ExtensionData.Configuration.DrsConfig.EnableVmBehaviorOverrides
            $spec.DrsConfig.DefaultVmBehavior = $cluster.ExtensionData.Configuration.DrsConfig.DefaultVmBehavior
            $spec.DrsConfig.VmotionRate = $cluster.ExtensionData.Configuration.DrsConfig.VmotionRate
            $spec.DrsConfig.Option = $cluster.ExtensionData.Configuration.DrsConfig.Option
            $modify = $true
            $_this = Get-View -Id $destCluster.Id
            $_this.ReconfigureComputeResource_Task($spec, $modify) | Out-Null  
        }
        #EVCMode = $cluster.EVCMode # To be defined as this is a chicken/egg problem, if enabled hosts need to be in MM, if not all hosts need to be put in MM afterwards to enable

        # Updating Permissions on the object
        AddPermission -ObjectSource $cluster -ObjectDest $destCluster
    }
}

#Check if Log location exists
If (-not (Test-Path $exportPath)) {
    Write-Host "The log location ($exportPath) cannot be found" -ForegroundColor Red
    exit
}

### MAIN

# Disconnect existing sessions
if ($global:defaultVIServers) {
    Disconnect-VIServer -Server * -force -confirm:$false | Out-Null
}

#$credsSource = get-credential
#$credsDestination = get-credential
connect-viserver -server $sourceVC -User $sourceVCUser -Password $sourceVCPass #-credential $credsSource
connect-viserver -server $destVC -User $destVCUser -Password $destVCPass #-credential $credsDestination -NotDefault:$false

if ($global:defaultVIServers) {
    # Migrate Roles
    # Variables

    try {
        MyLogger -Message "Checking Roles in $($sourceVC) ..."
        $roleCreated = 0
        # Get roles to transfer (for everything else than system roles: '| ?{$_.IsSystem -eq $False}')
        $roles = Get-VIRole -Server $sourceVC -Name $strRolesCustomPrefix*
        # Get role Privileges for each role
        foreach ($role in $roles) {
            [string[]]$privsforRoleAfromsourceVC = Get-VIPrivilege -Role (Get-VIRole -Name $role -server $sourceVC) |%{$_.id}
            If (Get-VIRole -Name $($role.Name) -Server $destVC -ErrorAction Ignore) {
                MyLogger -Message "Role $($role.Name) already exists in $($destVC) - Updating Privileges" -Color Green
            }
            else {
                # Create new role in Destination vCenter
                MyLogger -Message "Creating Role $($role.Name) in $($destVC)" -Color Yellow
                If (-not $Test) {New-VIRole -name $role -Server $destVC | Out-Null}
                $roleCreated = +1
                # Add Privileges to new role.
                MyLogger -Message "Adding Privileges to Role $($role.Name) in $($destVC)" -Color Yellow
                If (-not $Test) {Set-VIRole -role (get-virole -Name $role -Server $destVC) -AddPrivilege (get-viprivilege -id $privsforRoleAfromsourceVC -server $destVC) | Out-Null}
            }
        }
        If ($roleCreated -eq 0) {MyLogger -Message "No Roles to create in $($destVC) ..." -Color Blue}
    }
    catch {
        MyLogger -Message "There was an error in the Roles Migration part" Red
        MyLogger -Message "`n($_.Exception.Message)`n"
    }

    MyLogger -Message "Checking Root folders in $($sourceVC) ..."
    # Retrieve the root folders and loop through each root folder
    $rootFolders = get-folder -server $sourceVC -Type Datacenter | Sort-Object
    foreach ($rootFolder in $rootFolders) {
        # Discard the root folder 'Datacenters'
        If ($rootFolder.Name -ne 'Datacenters'){
            MyLogger -Message "Checking Datacenter Folder: $($rootFolder.Parent)\$($rootFolder.Name) on $($destVC)"
            If ($destrootFolder = Get-Folder -Server $destVC -Name "$($rootFolder.Name)" -Location "$($rootFolder.Parent)" -ErrorAction Ignore) {
                MyLogger -Message "Datacenter Folder $($rootFolder.Name) already exists in $($destVC)" -Color Green
            }
            else {
                MyLogger -Message "Creating Datacenter Folder $($rootFolder.Name) in $($destVC)" -Color Yellow
                If (-not $Test) {
                    $destrootFolder = New-Folder -Server $destVC -Name "$($rootFolder.Name)" -Location "$($rootFolder.Parent)" -ErrorAction Ignore
                }
            }
            # Updating Permissions on the object
            AddPermission -ObjectSource $rootFolder -ObjectDest $destrootFolder

            # Retrieve the datacenters and loop through each DC
            $datacenters = get-datacenter -server $sourceVC -Location $rootFolder | Sort-Object
            foreach ($datacenter in $datacenters) {
                MyLogger -Message "Checking Datacenter: $($datacenter.ParentFolder)\$($datacenter.Name)"
                If ($destDatacenter = Get-Datacenter -Server $destVC -Name "$($datacenter.Name)" -Location "$($datacenter.ParentFolder)" -ErrorAction Ignore) {
                    MyLogger -Message "Datacenter $($datacenter.Name) already exists in $($destVC)" -Color Green
                }
                else {
                    MyLogger -Message "Creating Datacenter $($datacenter.Name) in $($destVC)" -Color Yellow
                    If (-not $Test) {$destDatacenter = New-Datacenter -Server $destVC -Name "$($datacenter.Name)" -Location "$($datacenter.ParentFolder)" -ErrorAction Ignore}
                }
                # Updating Permissions on the object
                AddPermission -ObjectSource $datacenter -ObjectDest $destDatacenter

                # Check the datacenter subfolders
                MyLogger -Message "Checking Datacenter SubFolders"
                $dcSubFolders = get-folder -server $sourceVC -Type HostAndCluster -Location $datacenter | Sort-Object
                foreach ($dcSubFolder in $dcSubFolders) {
                    If ($($dcSubFolder.Name) -eq 'host'){
                        MyLogger -Message "Checking Datacenter SubFolder: $($datacenter.Name)\$($dcSubFolder.Name) on $($destVC)"
                        If ($destdcSubFolder = Get-Datacenter -Server $destVC -Name $destDatacenter | Get-Folder -Server $destVC -Name "$($dcSubFolder.Name)" -Type HostAndCluster -ErrorAction Ignore) {
                            MyLogger -Message "Datacenter SubFolder $($dcSubFolder.Name) already exists in $($destVC)" -Color Green
                            CheckCluster -ObjectSource $dcSubFolder -ObjectDest $destdcSubFolder
                        }
                        else {
                            MyLogger -Message "Creating Datacenter SubFolder $($dcSubFolder.Name) in $($destVC)" -Color Yellow
                            If (-not $Test) {$destdcSubFolder = New-Folder -Server $destVC -Name "$($dcSubFolder.Name)" -Location (Get-Datacenter -Server $destVC -Name "$($datacenter.Name)") -ErrorAction Ignore}
                            CheckCluster -ObjectSource $dcSubFolder -ObjectDest $destdcSubFolder
                        }
                        # Updating Permissions on the object
                        AddPermission -ObjectSource $dcSubFolder -ObjectDest $destdcSubFolder    
                    } else {
                        MyLogger -Message "Checking Datacenter SubFolder: $($datacenter.Name)\$($dcSubFolder.Name) on $($destVC)"
                        If ($destdcSubFolder = Get-Datacenter -Server $destVC -Name $destDatacenter | Get-Folder -Server $destVC -Name "$($dcSubFolder.Name)" -Type HostAndCluster -ErrorAction Ignore) {
                            MyLogger -Message "Datacenter SubFolder $($dcSubFolder.Name) already exists in $($destVC)" -Color Green
                            CheckCluster -ObjectSource $dcSubFolder -ObjectDest $destdcSubFolder
                        }
                        else {
                            MyLogger -Message "Creating Datacenter SubFolder $($dcSubFolder.Name) in $($destVC)" -Color Yellow
                            If (-not $Test) {$destdcSubFolder = New-Folder -Server $destVC -Name "$($dcSubFolder.Name)" -Location (Get-Datacenter -Server $destVC -Name "$($datacenter.Name)") -ErrorAction Ignore}
                            CheckCluster -ObjectSource $dcSubFolder -ObjectDest $destdcSubFolder
                        }
                        # Updating Permissions on the object
                        AddPermission -ObjectSource $dcSubFolder -ObjectDest $destdcSubFolder    
                    }
                }
                # Check for VM folders within the datacenter
                $vmFolders = get-datacenter $datacenter -Server $sourceVC| Get-folder -type vm #| Sort-Object 
                MyLogger -Message "Checking VM Folders:"
                foreach ($vmFolder in $vmFolders) {
                    If ($($vmFolder.Name) -ne 'vm' -and $($vmFolder.Name) -ne 'vCLS' -and $($vmFolder.Name) -ne 'Discovered virtual machine'){
                        $location = $null
                        $vmFolderPath = $vmFolder | Get-FolderPath
                        If ($debug -ge 2) {MyLogger -Message "Checking VM Folder: $($vmFolderPath.Path)"}
                        $vmFolderPath.Path = ($vmFolderPath.Path).Replace($($rootFolder.Name) + "\" + $($datacenter.Name) + "\",$($rootFolder.Name) + "\" + "vm\")
                        MyLogger -Message "Checking VM Folder: $($vmFolderPath.Path)"
                        $key = @()
                        $key =  ($vmFolderPath.Path -split "\\")[-2]
                        $destvmFolder = $null
                        if ($key -eq "vm") {
                            $location = Get-Datacenter -Server $destVC -Name "$($datacenter.Name)" | get-folder -type vm
                            If ($destvmFolder = Get-Folder -Name $vmFolder.Name -Location $location -ErrorAction Ignore) {
                                MyLogger -Message "VM Folder $($vmFolder.Name) already exists in $($destVC)" -Color Green
                            }
                            else{
                                MyLogger -Message "Creating VM Folder $($vmFolder.Name) in $($destVC)) at $($vmFolderPathDest.Path)" -Color Yellow
                                If (-not $Test) {$destvmFolder = Get-Datacenter $datacenter -Server $destVC | Get-Folder vm | New-Folder -Name $vmFolderPath.Name -ErrorAction Ignore}
                            }
                        }
                        else {
                            $location = Get-Datacenter -Server $destVC -Name "$($datacenter.Name)" | get-folder -type vm | get-folder $key -ErrorAction Ignore
                            foreach ($loc in $location) {
                                $vmFolderPathDest = $loc | Get-FolderPath
                                $vmFolderPathDest.Path = ($vmFolderPathDest.Path).Replace($($rootFolder.Name) + "\" + $($datacenter.Name) + "\",$($rootFolder.Name) + "\" + "vm\")
                                If ($vmFolderPath.Path -eq $vmFolderPathDest.Path){
                                    $location = $loc
                                    break
                                }
                            }
                            If ($destvmFolder = Get-Folder -Name $vmFolder.Name -Location $location -ErrorAction Ignore) {
                                MyLogger -Message "VM Folder $($vmFolder.Name) already exists in $($destVC)" -Color Green
                            }
                            else{
                                MyLogger -Message "Creating VM Folder $($vmFolder.Name) in $($destVC)) at $($vmFolderPathDest.Path)" -Color Yellow
                                If (-not $Test) {$destvmFolder = New-Folder -Name $vmFolder.Name -Location $location -ErrorAction Ignore}
                            }   
                        }
                    # Updating Permissions on the object
                    AddPermission -ObjectSource $vmFolder -ObjectDest $destvmFolder
                    }
                }
                MyLogger -Message "Checking VM Folders: done" -Color Blue
            }
        }
    }

    Disconnect-VIServer -Server $sourceVC -force -confirm:$false
    Disconnect-VIServer -Server $destVC -force -confirm:$false
} else {
    Write-Host 'Could not connect to vCenters' -ForegroundColor Red
}

MyLogger -Message "Script Finished" -Color Blue