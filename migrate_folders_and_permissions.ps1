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
#$sourceVC = 'pivcss001.vconsultants.local'
$sourceVC = 'ldnlxpvcsa1.vitol.com'
#$destVC = 'tanzu-vcsa-1.tanzu.demo'
$destVC = 'gvalxpvcsa1.vitol.com'

$exportPath = 'C:\vCenterConfExport'

# TEST OR DEBUG
$Test = $false # Run without execution on the destination
$debug = 1 # Show debug information -- 0 = No debug info | 1 = Verbose | 2 = Very Verbose
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

### MAIN

# Disconnect existing sessions
if ($global:defaultVIServers) {
    Disconnect-VIServer -Server * -force -confirm:$false | Out-Null
}

#$credsSource = get-credential
#$credsDestination = get-credential
connect-viserver -server $sourceVC -User tmp_export@vsphere.local -Password VMware123! #-credential $credsSource
connect-viserver -server $destVC -User administrator@vsphere.local -Password VMware123! #-credential $credsDestination -NotDefault:$false

# Migrate Roles
# Variables
$strRolesCustomPrefix = 'VITOL' # based on this prefix string we will filter the roles to transfer

try {
    If ($debug -ge 1) {Write-Host "`nChecking Roles in $($sourceVC) ..."}
    $roleCreated = 0
    # Get roles to transfer (for everything else than system roles: '| ?{$_.IsSystem -eq $False}')
    $roles = Get-VIRole -Server $sourceVC -Name $strRolesCustomPrefix*
    # Get role Privileges for each role
    foreach ($role in $roles) {
        [string[]]$privsforRoleAfromsourceVC = Get-VIPrivilege -Role (Get-VIRole -Name $role -server $sourceVC) |%{$_.id}
        If (Get-VIRole -Name $role.Name -Server $destVC -ErrorAction Ignore) {
            If ($debug -ge 1) {Write-Host "`nRole $($role.Name) already exists in $($destVC) - Updating Privileges" -ForegroundColor Green}
        }
        else {
            # Create new role in Destination vCenter
            If ($debug -ge 1) {Write-Host "`nCreating Role $($role.Name) in $($destVC)" -ForegroundColor Yellow}
            If (-not $Test) {New-VIRole -name $role -Server $destVC | Out-Null}
            $roleCreated = +1
            # Add Privileges to new role.
            If ($debug -ge 1) {Write-Host "Adding Privileges to Role $($role.Name) in $($destVC)" -ForegroundColor Yellow}
            If (-not $Test) {Set-VIRole -role (get-virole -Name $role -Server $destVC) -AddPrivilege (get-viprivilege -id $privsforRoleAfromsourceVC -server $destVC) | Out-Null}
        }
    }
    If ($roleCreated -eq 0) {If ($debug -ge 1) {Write-Host "`nNo Roles to create in $($destVC) ..." -ForegroundColor Green}}
}
catch {
    Write-Host "There was an error in the Roles Migration part" -ForegroundColor Red
    Write-Error "`n($_.Exception.Message)`n"
}


If ($debug -ge 1) {Write-Host "`nChecking Root folders in $($sourceVC) ..."}
# Retrieve the root folders and loop through each root folder
$rootFolders = get-folder -server $sourceVC -Type Datacenter | Sort-Object
foreach ($rootFolder in $rootFolders) {
    # Discard the root folder 'Datacenters'
    If ($rootFolder.Name -ne 'Datacenters'){
        If ($debug -ge 1) {
            write-host "`nChecking Datacenter Folder: $($rootFolder.Parent)\$($rootFolder.Name) on $($destVC)"
        }
        If (Get-Folder -Server $destVC -Name "$($rootFolder.Name)" -Location "$($rootFolder.Parent)" -ErrorAction Ignore) {
            If ($debug -ge 1) {
                Write-Host "Datacenter Folder $($rootFolder.Name) already exists in $($destVC)" -ForegroundColor Green
            }
        }
        else {
            If ($debug -ge 1) {Write-Host "Creating Datacenter Folder $($rootFolder.Name) in $($destVC)" -ForegroundColor Yellow}
            If (-not $Test) {New-Folder -Server $destVC -Name "$($rootFolder.Name)" -Location "$($rootFolder.Parent)" |Out-Null}
        }
        # Retrieve the datacenters
        $datacenters = get-datacenter -server $sourceVC -Location $rootFolder | Sort-Object
        foreach ($datacenter in $datacenters) {
            If ($debug -ge 1) {write-host "`n    Checking Datacenter: $($datacenter.ParentFolder)\$($datacenter.Name)"}
            If (Get-Datacenter -Server $destVC -Name "$($datacenter.Name)" -Location "$($datacenter.ParentFolder)" -ErrorAction Ignore) {
                If ($debug -ge 1) {Write-Host "    Datacenter $($datacenter.Name) already exists in $($destVC)" -ForegroundColor Green}
            }
            else {
                If ($debug -ge 1) {Write-Host "    Creating Datacenter $($datacenter.Name) in $($destVC)" -ForegroundColor Yellow}
                If (-not $Test) {New-Datacenter -Server $destVC -Name "$($datacenter.Name)" -Location "$($datacenter.ParentFolder)" |Out-Null}
            }
            # Check if the datacenter has subfolders
            $dcSubFolders = get-folder -server $sourceVC -Type Datacenter -Location $datacenter | Sort-Object
            foreach ($dcSubFolder in $dcSubFolders) {
                If ($debug -ge 1) {
                    write-host "`nChecking Datacenter SubFolder: $($datacenter.Name)\$($dcSubFolder.Name) on $($destVC)"
                }
                If (Get-Folder -Server $destVC -Name "$($dcSubFolder.Name)" -Location $datacenter -ErrorAction Ignore) {
                    If ($debug -ge 1) {Write-Host "Datacenter SubFolder $($dcSubFolder.Name) already exists in $($destVC)" -ForegroundColor Green}
                }
                else {
                    If ($debug -ge 1) {Write-Host "Creating Datacenter SubFolder $($dcSubFolder.Name) in $($destVC)" -ForegroundColor Yellow}
                    If (-not $Test) {New-Folder -Server $destVC -Name "$($dcSubFolder.Name)" -Location (Get-Datacenter -Server $destVC -Name "$($datacenter.Name)") |Out-Null}
                }
            }
            # Check the clusters within the datacenter
            $clusters = Get-cluster -Server $sourceVC -Location $datacenter | Sort-Object
            foreach ($cluster in $clusters) {
                If ($debug -ge 1) {
                    write-host "        Checking Cluster: $($datacenter.Name)\$($cluster.Name)"
                    If ($debug -ge 2) {
                        write-host "         -DrsAutomationLevel: $($cluster.DrsAutomationLevel)"
                        write-host "         -DrsEnabled: $($cluster.DrsEnabled)"
                        write-host "         -EVCMode: $($cluster.EVCMode)"
                        write-host "         -HAAdmissionControlEnabled: $($cluster.HAAdmissionControlEnabled)"
                        write-host "         -HAEnabled: $($cluster.HAEnabled)"
                        write-host "         -HAFailoverLevel: $($cluster.HAFailoverLevel)"
                        write-host "         -HAIsolationResponse: $($cluster.HAIsolationResponse)"
                        write-host "         -HARestartPriority: $($cluster.HARestartPriority)"
                        write-host "         -VMSwapfilePolicy: $($cluster.VMSwapfilePolicy)"
                    }
                }
                $clusterSettings = @{
                    Name = $cluster.Name
                    HAEnabled = If ($cluster.HAEnabled -eq $False) {$False} else {[Boolean]$cluster.HAEnabled}
                    DrsEnabled = If ($cluster.DrsEnabled -eq $False) {$False} else {[Boolean]$cluster.DrsEnabled}
                    Confirm = $false
                }
                If ($destCluster = Get-Cluster -Server $destVC -Name "$($cluster.Name)" -Location "$($datacenter.Name)" -ErrorAction Ignore) {
                    If ($debug -ge 1) {
                        Write-Host "        Cluster $($cluster.Name) already exists in $($destVC)" -ForegroundColor Green
                        $clusterExists = $true
                    }
                }
                else {
                    If ($debug -ge 1) {Write-Host "        Creating Cluster $($cluster.Name) in $($datacenter.Name) in $($destVC)" -ForegroundColor Yellow}
                    If (-not $Test) {
                        $destCluster = New-Cluster -Server $destVC -Location (get-datacenter -server $destVC -Name $datacenter.Name) @clusterSettings | Out-Null
                        $clusterExists = $true
                    }
                }
                If ($cluster.HAEnabled -eq $True -and $clusterExists -eq $true){
                    If ($debug -ge 1) {Write-Host "        Updating Cluster HA Settings on $($cluster.Name) in $($datacenter.Name) in $($destVC)" -ForegroundColor Yellow}
                    $clusterSettings = @{
                        Name = $cluster.Name
                        HAAdmissionControlEnabled = If ($cluster.HAAdmissionControlEnabled -eq $False) {$False} else {[Boolean]$cluster.HAAdmissionControlEnabled}
                        HAFailoverLevel = $cluster.HAFailoverLevel
                        HARestartPriority = $($cluster.HARestartPriority)
                        HAIsolationResponse = $($cluster.HAIsolationResponse)
                        Confirm = $false
                    }
                    Set-Cluster -Cluster $destCluster @clusterSettings | Out-Null
                }
                If ($cluster.DrsEnabled -eq $True -and $clusterExists -eq $true){
                    If ($debug -ge 1) {Write-Host "        Updating Cluster Drs Settings on $($cluster.Name) in $($datacenter.Name) in $($destVC)" -ForegroundColor Yellow}
                    $clusterSettings = @{
                        Name = $cluster.Name
                        DrsAutomationLevel = $($cluster.DrsAutomationLevel)
                        Confirm = $false
                    }
                    Set-Cluster -Cluster $destCluster @clusterSettings | Out-Null
                }
                #EVCMode = $cluster.EVCMode # To be defined as this is a chicken/egg problem, if enabled hosts need to be in MM, if not all hosts need to be put in MM afterwards to enable
            }
            # Check for VM folders within the datacenter
            $vmFolders = get-datacenter $datacenter -Server $sourceVC| Get-folder -type vm | Sort-Object
            If ($debug -ge 1) {write-host "`n    Checking VM Folders:"}
            foreach ($vmFolder in $vmFolders) {
                If ($($vmFolder.Name) -ne 'vm' -and $($vmFolder.Name) -ne 'vCLS' -and $($vmFolder.Name) -ne 'Discovered virtual machine'){
                    $location = $null
                    $vmFolderPath = $vmFolder | Get-FolderPath
                    $vmFolderPath.Path = ($vmFolderPath.Path).Replace($rootFolder.Name + "\" + $datacenter.Name + "\",$rootFolder.Name + "\" + "vm\")
                    If ($debug -ge 1) {write-host "        Checking VM Folder: $($vmFolderPath.Path)"}
                    If (get-datacenter $datacenter -Server $destVC| Get-Folder -Server $destVC  -Name "$($vmFolder.Name)" -Location "$($vmFolder.Parent)" -ErrorAction Ignore) {
                        If ($debug -ge 1) {Write-Host "        VM Folder $($vmFolder.Name) already exists in $($destVC)" -ForegroundColor Green}
                    }
                    else {
                        $key = @()
                        $key =  ($vmFolderPath.Path -split "\\")[-2]
                        if ($key -eq "vm") {
                            Get-Datacenter $datacenter -Server $destVC | Get-Folder vm | New-Folder -Name $vmFolderPath.Name | Out-Null
                        }
                        else {
                            $location = Get-Datacenter -Server $destVC -Name "$($datacenter.Name)" | get-folder -type vm | get-folder $key
                            Try{
                                Get-Folder -Name $vmFolder.Name -Location $location -ErrorAction Stop | Out-Null
                            }
                            Catch{
                                If (-not $Test) {New-Folder -Name $vmFolder.Name -Location $location | Out-Null}
                            }
                        }
                    }
                    # $folderperms = Get-Folder -Location $vmFolder | Get-VIPermission #| ?{$_.IsSystem -eq $False}
                    # foreach ($folderperm in $folderperms) {
                    #     Write-Host "VM Permissions: $folderperm"
                    # }
                }
            }
            If ($debug -ge 1) {write-host "`n    Checking VM Folders: done" -ForegroundColor Green}
        }
    }
}

# Get the Permissions  - Users need to exist
$folderperms = Get-VIpermission -Server $sourceVC | Where ($_.Principal -inotcontains "VSPHERE.LOCAL")

$report = @()
foreach($perm in $folderperms){
    $row = "" | select EntityId, FolderName, Role, Principal, IsGroup, Propagate
    $row.EntityId = $perm.EntityId
    $Foldername = (Get-View -id $perm.EntityId).Name
    $row.FolderName = $foldername
    $row.Principal = $perm.Principal
    $row.Role = $perm.Role
    $row.IsGroup = $perm.IsGroup
    $row.Propagate = $perm.Propagate
    $report += $row
}
$report | export-csv "$exportPath\perms-$($sourceVC).csv" -NoTypeInformation

# If (-not $Test){
#     ##Import Permissions
#     $permissions = @()
#     $permissions = Import-Csv "$exportPath\perms-$($sourceVC).csv"

#     foreach ($perm in $permissions) {
#         $entity = ""
#         $entity = New-Object VMware.Vim.ManagedObjectReference

#         switch -wildcard ($perm.EntityId)
#             {
#                 Folder* {
#                 $entity.type = "Folder"
#                 $entity.value = ((get-folder "$($perm.Foldername)" -Server $destVC).ID).Trimstart("Folder-")
#             }
#                 VirtualMachine* {
#                 $entity.Type = "VirtualMachine"
#                 $entity.value = ((Get-vm $perm.Foldername).Id).Trimstart("VirtualMachine-")
#             }
#     }
#     $setperm = New-Object VMware.Vim.Permission
#     $setperm.principal = $perm.Principal
#         if ($perm.isgroup -eq "True") {
#             $setperm.group = $true
#         } else {
#             $setperm.group = $false
#         }
#     $setperm.roleId = (Get-virole $perm.Role -Server $destVC).id
#         if ($perm.propagate -eq "True") {
#             $setperm.propagate = $true
#         } else {
#             $setperm.propagate = $false
#         }

#     $doactual = Get-View -Id 'AuthorizationManager-AuthorizationManager' -Server $destVC
#     $doactual.SetEntityPermissions($entity, $setperm)
#     }
# }

Disconnect-VIServer -Server $sourceVC -force -confirm:$false
Disconnect-VIServer -Server $destVC -force -confirm:$false