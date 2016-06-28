Param ( 
     [Parameter(Mandatory=$true)][ValidateSet("WriteBack", "WriteThrough")][string]$Mode
)
Function Writelog
{
  Param ([string]$logstring)
   $logstring = "$(Get-Date -format s) - " + $logstring
   $logstring | out-file -Filepath $logfile -append
}

Function Timer ($timeoutseconds, $vmid)
{
 $timeout = new-timespan -Seconds $timeoutseconds
            $sw = [diagnostics.stopwatch]::StartNew()
            while ($sw.elapsed -lt $timeout){
                $vmstatus = Get-PrnxAccelerationPolicy -uuid $VMID -Effective
                if ($vmstatus = "WRITE_THROUGH"){
                    writelog "Transition Complete"
                    return
                    }
                else {start-sleep -seconds 1}
            }
            writelog "Timed out"
}

#Set these required parameters
#
$fvp_server = "Name of FVP Management Server"
$vcenter = "Name of vCenter"
$username = "domain\userid"

Add-PSSnapin VMware.VimAutomation.Core -ErrorAction Stop
Add-PSSnapin VeeamPSSnapIn -ErrorAction Stop

#This bit pulls the process id of the Veeam session. From that it gets the job command used to start the job and then uses the GUID of the job to get the name of the job

$parentpid = (Get-WmiObject Win32_Process -Filter "processid='$pid'").parentprocessid.ToString()

$parentcmd = (Get-WmiObject Win32_Process -Filter "processid='$parentpid'").CommandLine

$veeamjob = Get-VBRJob | ?{$parentcmd -like "*"+$_.Id.ToString()+"*"}

$jobname=$veeamjob.name

$prnxVMs = ""

# Initialize variables
$logfilepath = "C:\veeamprnx"
$logfile = $logfilepath + "\"+$jobname+"_fvp_$(get-date -f yyyy_MM_dd_HH_mm_ss).log"
$passwordfile = $logfilepath + "\fvp_enc_pass.txt"

#Here we get the encrypted password from the password file and use a key to decrypt. You need this so it can be used by the Veeam service running the jobs

    Writelog "Retrieving encrypted password from file $passwordfile"
    Try { 
           [Byte[]] $key = (1..16)

           $enc_pass = Get-Content $passwordfile | ConvertTo-SecureString -Key $key
           Writelog $enc_pass
       }
    Catch { 
           Writelog "Error retrieving encrypted password"
          Exit 1
       }

    Try { 
           $credential = New-Object System.Management.Automation.PsCredential($username, $enc_pass)
      }
    Catch {
           Writelog "Error creating credential object"
           Exit 1
      }

# Verify the job exists
$job = Get-VBRJob -Name $JobName

Writelog "Verifying that the job exists, "$job
if (!$job) {
    Writelog "Backup job $jobname not found!"
    Exit 2
}

$SettingsFile = $logfilepath + "\Job."+$job.TargetFile+".Settings.csv"

# Running some initial tests
    if ($Mode -eq "WriteThrough") {
        if (Test-Path $SettingsFile) {
            Writelog "Warning: $SettingsFile still exists from previous run. Manually remove and re-run the job"
            Exit 2
        } else {
            Writelog "Created peer settings file: $SettingsFile"
            $SettingsFileHandle = New-Item $SettingsFile -Type File
        }
    } elseif ($Mode -eq "WriteBack") {
        if (Test-Path $SettingsFile) {
            Writelog "Transitioning VMs to write back."
            $SettingsFileHandle = Get-Content $SettingsFile
        } else {
            Writelog "Nothing to change, normal exit"
            Exit 0
        }
    }

# It's showtime!

if ($Mode -eq "WriteThrough") {
  #  Writelog "Connecting to VMware vCenter Server: $vcenter"
    $vmware = Connect-VIServer -Server $vcenter -credential $credential
    $objects = $job.GetObjectsInJob() 


Writelog "Building list of included objects."
# Initiate empty array for VMs to include
[System.Collections.ArrayList]$is = @()


# This bit looks at the Veeam job and works out if it contains a list of VM's or is a selection based on a container. 
# It checks for any exclusions if it is a container and then buils a list of VM that are going to be backed up.

writelog""
writelog "List of VM's in Backup Job"
writelog ">>>>>>>>>>>>>>>>>>>>"
foreach ($o in $objects) {

              if( $o.object.vitype -eq "Tag") {$iq = (Get-VM -Tag $o.name) 
          foreach ($vminlist in $iq){if ((Get-VBRJobObject -Job $jobname -Name $vminlist.name).Object -notmatch "Name:*"){ $i = $is.Add($vminlist.PersistentId)}
            writelog $vminlist.name
            write-host $vminlist.name
            
            }
          }

          elseif( $o.object.vitype -eq "Datastore") {$iq = (Get-VM -Datastore $o.name) 
          foreach ($vminlist in $iq){if ((Get-VBRJobObject -Job $jobname -Name $vminlist.name).Object -notmatch "Name:*"){ $i = $is.Add($vminlist.PersistentId)}
            writelog $vminlist.name
            write-host $vminlist.name
            }
          }

        elseif( $o.object.vitype -ne "VirtualMachine") {$iq = (Get-VM -Location $o.name) 
          foreach ($vminlist in $iq){if ((Get-VBRJobObject -Job $jobname -Name $vminlist.name).Object -notmatch "Name:*"){ $i = $is.Add($vminlist.PersistentId)}
            writelog $vminlist.name
            write-host $vminlist.name
            $me = Get-VBRJobObject -Job $jobname -Name $vminlist.name
            write-host $me.object
           }
          }
        
        elseif ($o.type -ne "Exclude"){ $vv = (Get-VM -name $o.name) 
                $i = $is.Add($vv.PersistentID)  
          writelog $vv.name
          write-host $vv.name        
         }
                 
         Else{ Write-host ""}

 }
 
writelog ">>>>>>>>>>>>>>>>>>>>"
writelog ""
Writelog "Connecting to PernixData Management Server: $fvp_server"

Try {
        import-module prnxcli -ea Stop
        $prnx = Connect-PrnxServer -NameOrIpAddress $fvp_server -credentials $credential -ea Stop > $null
        $FVPversion=""
        $license = Get-PrnxObject -Type PrnxMServer
        if($license.buildinfo -gt "3.1"){$FVPversion="3.1"}
        writelog $FVPversion
    }
Catch {
        Writelog "Error connecting to FVP Management Server: $($_.Exception.Message)"
        exit 1
    }

Writelog "Connected to PernixData Management Server: $fvp_server"
Writelog "Getting list of included, powered on VMs with PernixData write back enabled."
writelog""

$prnxVMs = Get-PrnxVM | Where {($_.powerState -eq "poweredOn") -and ($_.effectivePolicy -eq "7")} | Where { $is -contains $_.UUID }

writelog "*************"
Writelog "VM That will be transitioned to WriteThrough"
writelog ">>>>>>>>>>>>>>>>>>>>"

foreach ($vm in $prnxVMs) { writelog $vm.Name }
writelog ">>>>>>>>>>>>>>>>>>>>"
writelog""
writelog "Now we will transition them"

writelog "==========================="

foreach ($vm in $prnxVMs) { 

    writelog "--------------------"
    writelog $vm.name

    if ($vm.numWbExternalPeers -eq $null) {
        $ext_peers = 0
    } else {
        $ext_peers = $vm.numWbExternalPeers
    }
    
    $VMName = $vm.Name
    $VMWBPeers = $vm.NumWBPeers
    $VMWBExternalPeers = $ext_peers
    $VMID = $VM.uuid

    $WriteBackPeerInfo = @($VMName,$vmid,$VMWBPeers,$VMWBExternalPeers)
    $WriteBackPeerInfo -join ',' | Out-File $SettingsFile -Append

    
    Writelog "Transitioning $VMName (peers: $VMWBPeers, external: $VMWBExternalPeers) into WriteThrough mode."

# Here we are going to transition the VM to WriteTrhough. I have added a test to check the VM has an effective status of Writethrough before mvoing on. It is there to catch any VM's that have a lot of WB data in the cache
# It is Fairly simple, it grabs the VM UUID, gets the time_to_destage value and then sets this to a time out variable. Once the WT policy has been sent it goes into a loop checking the Effective Status
# WHen this is WriteThrough it steps on. It uses a timeout of the Time_to_destage + 10 secs so if the VM does not transition for some reason, the loop will stop. 
        
    Try { 
    
    if($FVPversion -eq "3.1"){$timetodisk = Get-PrnxObjectStats -ObjectIdentifier $VMID -starttime 0 -NumberOfSamples 1}
    else{$timetodisk = Get-PrnxObjectStats -ObjectIdentifier $VMID -NumberOfSamples 1}
      
        writelog $vmid
   
    $timeoutseconds = $timetodisk.time_to_destage
    $timeoutseconds = $timeoutseconds + 10
    writelog $timeoutseconds
   

 $CacheMode = Set-PrnxAccelerationPolicy -uuid $VMID -WriteThrough -ea Stop

        #   timer $timeoutseconds $VMID
        
    }
    Catch {
        Write-Error "Failed to transition $VMName : $($_.Exception.Message)"
        Exit 2
    } 
}



} elseif ($Mode -eq "WriteBack") {

Writelog "Connecting to PernixData FVP Management Server: $fvp_server"

Try {
        import-module prnxcli -ea Stop
        $prnx = Connect-PrnxServer -NameOrIpAddress $fvp_server -credentials $credential -ea Stop > $null
        $licensetype=""
        $license = Get-PrnxObject -Type PrnxMServer
        if($license.licensedFeatures -match "FVP_FEATURE_FAULT_DOMAIN"){$licensetype="Enterprise"}        
    }
Catch {
        Writelog "Error connecting to FVP Management Server: $($_.Exception.Message)"
        Remove-Item -Path $SettingsFile
        exit 1
    }

Writelog "Connected to PernixData Management Server: $fvp_server"

foreach ($vm in $SettingsFileHandle) {
    $VMName            = $vm.split(",")[0]
    $VMID              = $vm.split(",")[1]
    $VMWBPeers         = $vm.split(",")[2]
    $VMWBExternalPeers = $vm.split(",")[3]

    Writelog "Transitioning $VMName into write back mode with $VMWBPeers peers and $VMWBExternalPeers external peers."
        
    Try { 
    if ($licensetype -eq "Enterprise") {
        $CacheMode = Set-PrnxAccelerationPolicy -uuid $VMID -WriteBack -NumWBPeers $VMWBPeers -NumWBExternalPeers $VMWBExternalPeers -ea Stop
         }
         Else{ $CacheMode = Set-PrnxAccelerationPolicy -uuid $VMID -WriteBack -NumWBPeers $VMWBPeers -ea Stop
        }

    }
    Catch {
        Writelog "Failed to transition $VMName : $($_.Exception.Message)"
        Exit 2
    }
}

Remove-Item -Path $SettingsFile
}

Disconnect-PrnxServer -Connection $prnx > $null
if ($vmware) { Disconnect-VIServer -Confirm:$false -server $vcenter > $null }
