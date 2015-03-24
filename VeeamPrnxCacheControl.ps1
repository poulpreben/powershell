Param ( 
    [Parameter(Mandatory=$true)][string]$JobName,
    [Parameter(Mandatory=$true)][ValidateSet("WriteBack", "WriteThrough")][string]$Mode
)
cls

Add-PSSnapin VMware.VimAutomation.Core -ErrorAction SilentlyContinue
Add-PSSnapin VeeamPSSnapIn -ErrorAction SilentlyContinue

$job = Get-VBRJob -Name $JobName

# Verify the job exists
if (!$job) {
    Write-Error "Backup job not found!"
    Exit 2
}

$SettingsFile = "C:\Temp\Job."+$job.TargetFile+".Settings.csv"

if ($Mode -eq "WriteThrough") {
    if (Test-Path $SettingsFile) {
        Write-Error "It seems the script was not properly stopped before this job run. Review $SettingsFile and perform manual clean-up."
        Exit 2
    } else {
        Write-Host "Create the peer settings file: $SettingsFile"
        $SettingsFileHandle = New-Item $SettingsFile -Type File
    }
} elseif ( -and ($Mode -eq "WriteBack")) {
    if (Test-Path $SettingsFile) {
        Write-Host "Now we just have to revert the acceleration mode."
        $SettingsFileHandle = Get-Content $SettingsFile
    } else {
        Write-Host "If we want to stop, but there are no settings to be reverted, everything's just fine..."
        Exit 0
}

if ($Mode -eq "WriteThrough") {
    Write-Host "Connecting to vCenter"
    $vmware = Connect-VIServer -Server vcenter -User root -Password vmware -WarningAction SilentlyContinue
    Write-Host "Connected to vCenter"

    "Getting objects in backup job"
    $objects = $job.GetObjectsInJob() | ?{$_.Type -eq "Include"}
    $excludes = $job.GetObjectsInJob() | ?{$_.Type -eq "Exclude"}

    # Initiate empty array for VMs to exclude
    [System.Collections.ArrayList]$es = @()

    "Building list of excluded job objects"
    foreach ($e in $excludes) {
        $e.Name

        # If the object added to the job is not a VM, find the contained VMs
        $view = Get-View -ViObject $e.Name | Get-VIObjectByVIView
        if ($view.GetType().Name -ne "VirtualMachineImpl") {
            foreach ($vm in ($view | Get-VM)) {
                $i = $es.Add($vm.Name)
            }
        } else {
            $i = $es.Add($view.Name)
        }

    }

    "Building list of included objects"
    # Initiate empty array for VMs to include
    [System.Collections.ArrayList]$is = @()

    foreach ($o in $objects) {
        $o.Name 

        # If the object added to the job is not a VM, find the contained VMs
        $view = Get-View -ViObject $o.Name | Get-VIObjectByVIView
        if ($view.GetType().Name -ne "VirtualMachineImpl") {
            foreach ($vm in ($view | Get-VM)) {
                if ($es -notcontains $vm.Name) {
                    $i = $is.Add($vm.Name)
                }
            }
        } else {
            $i = $is.Add($o.Name)
        }
    }
}

Write-Host "Connecting to PernixData FVP Management Server"

Import-Module PrnxCLI -ErrorAction SilentlyContinue
$prnx = Connect-PrnxServer -NameOrIPAddress localhost -UserName root -Password vmware

if ($Mode -eq "WriteThrough") {
    Write-Host "Getting list of included, powered on VMs with PernixData write-back caching enabled"
    $prnxVMs = Get-PrnxVM | Where-Object {($_.powerState -eq "poweredOn") -and ($_.effectivePolicy -eq "7")} | Where-Object {$_.Name -in $is}
    
    foreach ($vm in $prnxVMs) {
        if ($vm.numWbExternalPeers -eq $null) {
            $ext_peers = 0
        } else {
            $ext_peers = $vm.numWbExternalPeers
        }

        $VMName = $vm.Name
        $VMWBPeers = $vm.NumWBPeers
        $VMWBExternalPeers = $ext_peers

        $WriteBackPeerInfo = @($VMName,$VMWBPeers,$VMWBExternalPeers)
        $WriteBackPeerInfo -join ',' | Out-File $SettingsFile -Append

        Write-Host "Transitioning $VMName (peers: $VMWBPeers, external: $VMWBExternalPeers) into writethrough"
            
        Try { 
            $CacheMode = Set-PrnxAccelerationPolicy -Name $VMName -WriteThrough -ea Stop
        }
        Catch {
            Write-Error "Failed to transition $VMName : $($_.Exception.Message)"
            Exit 2
        }
    }
    
} elseif ($Mode -eq "WriteBack") {
    foreach ($vm in $SettingsFileHandle) {
        $VMName            = $vm.split(",")[0]
        $VMWBPeers         = $vm.split(",")[1]
        $VMWBExternalPeers = $vm.split(",")[2]

        Write-Host "Transitioning $VMName into writeback mode with $VMWBPeers peers and $VMWBExternalPeers external peers"
            
        Try { 
            $CacheMode = Set-PrnxAccelerationPolicy -Name $VMName -WriteBack -NumWBPeers $VMWBPeers -NumWBExternalPeers $VMWBExternalPeers -ea Stop
        }
        Catch {
            Write-Error "Failed to transition $VMName : $($_.Exception.Message)"
            Exit 2
        }
    }
    
    Remove-Item -Path $SettingsFile
}

foreach ($vm in $is) {
    if ($Mode -eq "WriteThrough") {
        # "WT for " + $vm
        $CacheMode = Set-PrnxAccelerationPolicy -Name $vm -WriteThrough -WaitTimeSeconds 60
    } elseif ($mode -eq "WriteBack") {
        # "WB for " + $vm
        $CacheMode = Set-PrnxAccelerationPolicy -Name $vm -WriteBack -NumWBPeers 0 -NumWBExternalPeers 0 -WaitTimeSeconds 60
    }
}

Disconnect-PrnxServer -Connection $prnx > $null