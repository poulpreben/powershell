Param ( 
    [Parameter(Mandatory=$true)][string]$JobName,
    [Parameter(Mandatory=$true)][ValidateSet("WriteBack", "WriteThrough")][string]$Mode
)


Add-PSSnapin VMware.VimAutomation.Core -ErrorAction SilentlyContinue
Add-PSSnapin VeeamPSSnapIn -ErrorAction SilentlyContinue

$vmware = Connect-VIServer -Server vcenter -User root -Password vmware -WarningAction SilentlyContinue

"Getting VBRJob"
$job = Get-VBRJob -Name $JobName

"Getting VBRJob objects"
$objects = $job.GetObjectsInJob() | ?{$_.Type -eq "Include"}
$excludes = $job.GetObjectsInJob() | ?{$_.Type -eq "Exclude"}

# Initiate empty array for VMs to exclude
[System.Collections.ArrayList]$es = @()

"Building excludes"
foreach ($e in $excludes) {
    $e.Name

    $view = Get-View -ViObject $e.Name | Get-VIObjectByVIView
    
    # If the object added to the job is not a VM, find the contained VMs
    if ($view.GetType().Name -ne "VirtualMachineImpl") {
        foreach ($vm in ($view | Get-VM)) {
            $i = $es.Add($vm.Name)
        }
    } else {
        $i = $es.Add($view.Name)
    }

}

"Building includes"
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

Import-Module PrnxCLI -ErrorAction SilentlyContinue
$prnx = Connect-PrnxServer -NameOrIPAddress localhost -UserName root -Password vmware

foreach ($vm in $is) {
    if ($Mode -eq "WriteThrough") {
        # "WT for " + $vm
        $CacheMode = Set-PrnxAccelerationPolicy -Name $vm -WriteThrough -WaitTimeSeconds 60
    } elseif ($mode -eq "WriteBack") {
        # "WB for " + $vm
        $CacheMode = Set-PrnxAccelerationPolicy -Name $vm -WriteBack -NumWBPeers 0 -NumWBExternalPeers 0 -WaitTimeSeconds 60
    }
}