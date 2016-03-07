Add-PSSnapin VeeamPSSnapIn -ErrorAction SilentlyContinue

$source_job_name    = "backup-bfss-3par"
$source_vm          = "demo-SQLandSP"
$source_db_name     = "VeeamTest"

$target_vm          = "dcvbrsql1.democenter.int"
$target_credentials = Get-VBRCredentials -Name "DEMOCENTER\svcveeamse"
$target_instance    = " "

$target_database    = "{0}-{1}" -f $source_db_name, (Get-Date -Format yyyyMMdd)

$restore_point = Get-VBRRestorePoint -Backup $source_job_name | ? VmName -match "^$source_vm" | Sort-Object creationtime -Descending | Select-Object -First 1

try {
    $database = Get-VBRSQLDatabase -ApplicationRestorePoint $restore_point -Name $source_db_name
} catch {
    "Couldnt find database" 
    break
}

$restore_session = Start-VBRSQLDatabaseRestore -Database $database -ServerName $target_vm -InstanceName $target_instance -DatabaseName $target_database -GuestCredentials $target_credentials -SqlCredentials $target_credentials