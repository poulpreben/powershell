cls
Add-PsSnapinVeeamPSSnapIn
Add-PsSnapinVMware.VimAutomation.Core

$JobSize= $null
$ProvisionedSize= $null
$JobNumber= 1

$vCenterServer = "vcenter.local"

$JobText    = "Backup-Prefix-"
$Datacenter = "VMware Datacenter Name"

$EmailFrom  = "veeam@example.com"
$EmailTo    = @("backupadmin@example.com")
$SMTPServer = ""

Connect-VIServer -Server $vCenterServer

$Repo = Get-VBRBackupRepository -Name "Repository Name"
$TagExclude = Get-VM -Tag "Backup - Exclude from Veeam Backup"

$List= @()



 
#Job Status:
$JobList= Get-VBRJob | Where-Object { $_.IsBackup }

[Array]$AvailableJobs= $null
foreach ($JobName in ($JobList.Name -like ("{0}*" -f $JobText) | Sort-Object) ) {
    
    $job = Get-VBRJob -Name $JobName
    
    $jobsize = 0
    
    ForEach ($VM in $($job.GetObjectsInJob()) ) {
        if (($VM.ApproxSizeString) -like "*MB*") {$jobsize= $jobsize+ ([decimal]($VM.ApproxSizeString -replace " MB")/100)}
        if (($VM.ApproxSizeString) -like "*GB*") {$jobsize= $jobsize+ ([decimal]($VM.ApproxSizeString -replace " GB")/10)}
    }
    
    if ($Jobsize-le 5000) {
        "$JobName have space ( $jobsize GB)"
        $FreeJobs = $true
    } else {
        "$JobName full ( $jobsize GB)"
    }
    
    [int]$GLOBAL:end= $JobName.substring($JobName.length - 1,1)
}
 
#Function finding next Job with less than 5 TB usage
Function Get-VBRJobNameList {
    $JobList= Get-VBRJob | Where-Object { $_.IsBackup }
    [Array]$AvailableJobs= $null
    $FreeJobs= $false
    
    foreach ($JobNamein ($JobList.Name -like ("{0}*" -f $JobText)| Sort-Object) ) {
        $job= Get-VBRJob -Name "$JobName"
        $jobsize= 0
        ForEach ($VMin $($job.GetObjectsInJob())) {
        
            if (($VM.ApproxSizeString) -like "*MB*") {
                $jobsize= $jobsize+ ([decimal]($VM.ApproxSizeString -replace " MB")/100)
            }
            
            if (($VM.ApproxSizeString) -like "*GB*") {
                $jobsize= $jobsize+ ([decimal]($VM.ApproxSizeString -replace " GB")/10)
            }
        }

        #"$JobName - $jobsize"
        if ($Jobsize-le 5000) {
            $FreeJobs= $true #"$JobName have space"
            return $JobName
        }
        
            #if ($Jobsize -ge 5000) {"$JobName full" }
            [int]$GLOBAL:end= $JobName.substring($JobName.length - 1,1)
            $JobName= $JobName.Substring(0,$JobName.Length-1)
    }
        
    if ($FreeJobs-eq $false) {
        return "CreateNewJob"
    }
}
 
#Function adding client to a job!
Function AddToCurrentJob ([String]$JobToAddTo= $null,[String]$ServerName= $null) {
    "Job Name - $JobToAddTo"
    "ServerName - $ServerName"
    
    $Entity= Find-VBRViEntity-Name $ServerName
    Add-VBRViJobObject-Job $JobToAddTo-Entities $Entity
    
    $Job= Get-VBRJob -Name $JobToAddTo
    
    $Job|Get-VBRJobObject|ForEach-Object {
        $ObjOptions =Get-VbrJobObjectVssOptions -ObjectInJob $_
        $ObjOptions.SqlBackupOptions.TransactionLogsProcessing = "Never"
        $ObjOptions.VssSnapshotOptions.IsCopyOnly = $true
        $ObjOptions.IgnoreErrors = $true
        $ObjOptions.ApproxSizeString
        $ObjOptions=Set-VBRJobObjectVssOptions -Object $_ -Options $ObjOptions
    }
    
    $message= new-object System.Net.Mail.MailMessage
    $message.From = $EmailFrom
    foreach($address in $EmailTo) {
        $message.To.Add($address)
    }

    $message.IsBodyHtml = $True
    $message.Subject = "$ServerName added to $JobName"
    $message.body = "$ServerName added to $JobName with 'AutoAddVMToVeeamBackup.ps1' script"
    $smtp= new-object Net.Mail.SmtpClient($SMTPServer)
    $smtp.Send($message)
}
 
Function CreateJob ([String]$JobName= $null,[String]$VMName= $null) {
    $List= Find-VBRViEntity-Name $VMName
    $Job= Add-VBRViBackupJob-Name $JobName-BackupRepository $Repo-Entity $List
    "Job "+ $JobName+" added"
    "Adjusting job settings"
    $Job= Get-VBRJob -Name $JobName
    $JobOptions=$Job | Get-VBRJobOptions
    $JobOptions.BackupStorageOptions.RetainCycles = 28
    $JobOptions.BackupTargetOptions.Algorithm = "Syntethic"
    $JobOptions.NotificationOptions.SendEmailNotification2AdditionalAddresses = $true
    $JobOptions.NotificationOptions.EmailNotificationAdditionalAddresses = $EmailTo[0]
    $JobOptions.ViSourceOptions.VmAttributeName = "Last Backup"
    $JobOptions.ViSourceOptions.SetResultsToVmNotes = $true
    $JobOptions.ViSourceOptions.VmNotesAppend = $false
     
    $Job=Set-VBRJobOptions -Options$JobOptions -Job$Job
    "Enabling VSS for job"
    $JobVSSOptions=$Job | Get-VBRJobVssOptions
    $JobVSSOptions.Enabled = $true
     
        $Credentials =Get-VBRCredentials -Name"Global\VeeamService"
    $JobVSSOptions=$Job | Set-VBRJobVssOptions -Options $JobVSSOptions
    $JobVSSOptions=$Job | Set-VBRJobVssOptions -Credentials $Credentials
    "Adjusting VSS settings for job object"
    $Job|Get-VBRJobObject|ForEach-Object {
        $ObjOptions =Get-VbrJobObjectVssOptions -ObjectInJob $_
        $ObjOptions.SqlBackupOptions.TransactionLogsProcessing = "Never"
        $ObjOptions.VssSnapshotOptions.IsCopyOnly = $true
        $ObjOptions.IgnoreErrors = $true
        $ObjOptions.ApproxSizeString
        $ObjOptions=Set-VBRJobObjectVssOptions -Object $_ -Options$ObjOptions
    }
    "Total Job Size for '$JobName': $JobSize"
    $message= new-object System.Net.Mail.MailMessage
    $message= new-object System.Net.Mail.MailMessage
    
    $message.From = $EmailFrom
    foreach($address in $EmailTo) {
        $message.To.Add($address)
    }
    
    $message.IsBodyHtml = $True
    $message.Subject = "NEW VEEAM JOB - $JobName"
    $message.body = "New Job, please check setting and schedule - $JobName"
    $smtp= new-object Net.Mail.SmtpClient($SMTPServer)
    $smtp.Send($message)
}
 
[array]$backupsessions = $null
foreach ($job in (Get-VBRJob| Where-Object {$_.IsBackup})) {
    Write-Host "Job: ", $job.Name
    $job.GetObjectsInJob() | foreach {
        $_.Name $backupsessions += $_.Name
    }
}
 
ForEach ( $i in $(Get-VM -Location $Datacenter).Name ) {
    
    $JobName = $JobText + $JobNumber
    $VMName =$i #+ ".global.chgroup.net"
    if ($TagExclude.Name -contains "$VMName") { } #"$VMName excluded from backup in vcenter" }
    else
    {
        if ($backupsessions -contains "$VMName") {  } #"$VMName already in a backup job" }
        else {
            $AvailableJob = Get-VBRJobNameList $VMName
            if ($AvailableJob -ne "CreateNewJob") {
                AddToCurrentJob $AvailableJob $VMName
            }
            if ($AvailableJob -eq "CreateNewJob") {
                $NewJobName = $JobText+$($End+1)
                CreateJob $NewJobName $VMName
            }
           
        }
    }
 
}
 
"Total Job size for '$JobName': $JobSize"
"Total Provisioned Job size for '$JobName': $ProvisionedSize"
"Total Job size for '$JobName': $JobSize"| Out-file "D:\temp\PS\Job-Logs\$($JobName).log" -append
"Total Provisioned Job size for '$JobName': $ProvisionedSize"| Out-file "D:\temp\PS\Job-Logs\$($JobName).log" -append

Disconnect-VIServer -Server $vCenterServer