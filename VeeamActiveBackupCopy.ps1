# Pseudo version
Add-PSSnapIn VeeamPSSnapIn

# Include Tom's logic to get job name automatically
$job_name = ""

$options = Get-VBRJob -Name $job_name | Get-VBRJobOptions
$restore_points = $options.GenerationPolicy.SimpleRetentionRestorePoints

# Go to this host, if exists... it is the gateway server
$target_host = $options.TargetHostId
# Go to this directory, which will be an SMB path
$target_dir = $options.TargetDir

$files = Get-Path -Path $target_dir
$count = Count items

if ($count -ge $restore_points) {
	# Go to target_host, target_dir

	# Rename target_dir
	$timestamp = (Get-Date -format yyyyddmm-hhmm)
	$new_directory = $timestamp " " $job_name

	Move-Item $target_dir $new_directory
}
