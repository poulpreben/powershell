# Veeam Script Repository
This is a repository for mixed PowerShell scripts I have created over time.

## Veeam/PernixData Cache Control
* Contributors
  * James Smith - PernixData
  * Andy Daniel - PernixData
* Created: 11/02/2015
* Last Updated: v9.1 - 01/28/2016
* v9.1 Update - Documentation changes and script cleanup. No new functionality.

**Note:** This script will transition VMs being backed up by Veeam into WT mode
before backup and transition them back to WB mode when done.

### Usage
1.  Create a Directory on the Veeam Server called `c:\veeamprnx`
2.  Copy the two script file into that directory
3.  Edit `VeeamPrnxCacheControl.ps1` and edit the following lines:

        $fvp_server = "FVP_SERVER_NAME"
        $vcenter = "VCENTER_NAME"
        $username = "domain\logon"

4.  Enter the correct values for these items. Remember the `$username` needs to
    be the logon you created for PernixData to install / run
5.  Save the file.
6.  Use the Powershell line below to create the $passwordfile credential to be
    used later.

    **NOTE THAT THE KEY TO THIS FILE IS CONTAINED IN THE SCRIPT AND CAN BE EASILY
    DECRYPTED BY USERS WITH ACCESS TO BOTH THE SCRIPT AND THE PASSWORD FILE. IT
    IS RECOMMENDED TO RUN THE VSC SERVICE AS A NAMED USER AND USE NTFS ACCESS
    CONTROLS TO LIMIT ACCESS TO THE FILES:**

    `Read-Host -AsSecureString -prompt "Enter password" | ConvertFrom-SecureString -key $([Byte[]](1..16))| Out-File fvp_enc_pass.txt `

7.  A new file called `fvp_enc_pass.txt` will be created. This contains an
    encrypted copy of the password and will be used by the script to run.
8.  Next, open Veeam and edit the backup job.
9.  Go to the section on pre and post scripts and enter the following strings
    in the boxes:
    - Pre Job:
        `C:\windows\system32\WindowsPowerShell\v1.0\powershell.exe -Command
        C:\veeamprnx\backup-veeam.ps1 -Mode WriteThrough`
    - Post Job:
        `C:\windows\system32\WindowsPowerShell\v1.0\powershell.exe -Command
        C:\veeamprnx\backup-veeam.ps1 -Mode WriteBack`

## Veeam Active Backup Copy

TBD
