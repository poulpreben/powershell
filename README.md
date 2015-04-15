# Veeam Script Repository
This is a repository for mixed PowerShell scripts I have created over time.

## Veeam/PernixData Cache Control

This script enables integration between Veeam Backup & Replication and PernixData FVP to allow FVP write back enabled VMs associated with the Veeam backup or replication job to be transitioned to write through before the job runs. Conversely, it also will transition the VMs back to the previous write back state with the correct number of peers.

### Usage

* Download zip file or clone this repository to your machine.
* Edit VeeamPrnxCacheControl.ps1 to include the username and password for connecting to vCenter and the PernixData management server.
* Temporary files will be stored in c:\temp. Change this if necessary.
* Edit each Veeam Backup & Replication job, select Storage, Advanced, then Advanced again.
* In the pre-job script field, enter C:\windows\system32\WindowsPowerShell\v1.0\powershell.exe -Command C:\<FOLDER_WHERE_YOU_STORED_SCRIPT>\VeeamPrnxCacheControl.ps1 -JobName 'Your Veeam Job Name Here' -Mode WriteThrough
* In the post-job script field, enter C:\windows\system32\WindowsPowerShell\v1.0\powershell.exe -Command C:\<FOLDER_WHERE_YOU_STORED_SCRIPT>\VeeamPrnxCacheControl.ps1 -JobName 'Your Veeam Job Name Here' -Mode WriteBack

## Veeam Active Backup Copy

TBD