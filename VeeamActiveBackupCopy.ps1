Param ( 
    [Parameter(Mandatory=$false)]$DeleteOldChain,
    [Parameter(Mandatory=$false)]$DeleteIncremental
)

Add-PSSnapIn VeeamPSSnapIn

# Thanks to Tom Sightler for these lines!
$parentpid = (Get-WmiObject Win32_Process -Filter "processid='$pid'").parentprocessid.ToString()
$parentcmd = (Get-WmiObject Win32_Process -Filter "processid='$parentpid'").CommandLine
$job = Get-VBRJob | ?{$parentcmd -like "*"+$_.Id.ToString()+"*"}

if (-Not $job) {
    Write-Host "Could not find backup job."
    Exit 2
}

$backup = Get-VBRBackup -Name $job.Name
$target = $backup.DirPath

$options = $job.GetOptions()
$restore_points = $options.GenerationPolicy.SimpleRetentionRestorePoints

$files = (Get-ChildItem $target |Where-Object { $_.Name -match ".vbk" -or $_.Name -match ".vib" })
$files_count = $files.Count

if ($files_count -ge $restore_points) {

	$new_directory = "Archive_" + $job.TargetFile
    $new_directory = $job.TargetDir+"\"+$new_directory

    Try {        
        # Create the archive path if it does not exist
        if (-Not (Test-Path -Path $new_directory)) {
            Write-Host ("Creating directory {0}" -f $new_directory)
            New-Item $new_directory -Type Directory
        }

        # Create list of existing files before moving anything - to be used for cleaning up afterwards
        $target_files = (Get-ChildItem $new_directory |Where-Object { $_.Name -match ".vbk" -or $_.Name -match ".vib" })

        # Move new files
        foreach ($file in ($backup.GetStorages())) {
            Write-Host ("Moving file {0}" -f $file.FilePath)
            Move-Item $file.FilePath $new_directory
        }

        # Move the VBM file
        Move-Item ("{0}\{1}" -f $target, $backup.MetaFileName) $new_directory -Force

    } Catch [System.Exception] {
        "An error occured!"
        Exit 2
    } Finally {
        # Clean up the original directory to trigger the new active full
        Write-Host ("Removing the empty folder {0}" -f $target)
        Remove-Item -Path $target -Recurse

        # DeleteOldChain will only preserve the new copied chain
        # Everything else will be deleted
        if ($DeleteOldChain -eq $true) {
            foreach ($f in $target_files) {
                Write-Host ("Removing old chain files: {$0}" -f $f.Name)
                Remove-Item $f.FullName
            }
        }

        # DeleteIncremental will remove incremental restore points from previous backup chains
        # basically GFS style.
        if ($DeleteIncremental -eq $true) {
            foreach ($f in $target_files) {
                if ($f.Name -match ".vib") {
                    Write-Host ("Removing incremental: {$0}" -f $f.Name)
                    Remove-Item $f.FullName
                }
            }
        }

        # Next version - update VBM file to include all full backups.

    }
}