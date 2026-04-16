#############################################
## SMB SHARE SETUP (PENTEST LAB)
#############################################

Import-Module ActiveDirectory
Import-Module SmbShare

$domain = (Get-ADDomain).NetBIOSName
$base   = (Get-ADDomain).DistinguishedName

$sharesRoot = "C:\CorpShares"

#############################################
## CREATE REQUIRED SECURITY GROUPS
#############################################

$groups = @{
    "sec_finance"     = "Finance Share Access"
    "sec_helpdesk"    = "Helpdesk Script Access"
    "sec_backup_ops"  = "Backup Operators"
    "sec_executive"   = "Executive Data Access"
}

foreach ($g in $groups.Keys) {
    if (-not (Get-ADGroup -Filter "Name -eq '$g'" -ErrorAction SilentlyContinue)) {
        Write-Host "[+] Creating group $g"
        New-ADGroup `
            -Name $g `
            -GroupScope Global `
            -GroupCategory Security `
            -Description $groups[$g] `
            -Path "CN=Users,$base"
    }
}

#############################################
## CREATE ROOT DIRECTORY
#############################################

New-Item -ItemType Directory -Path $sharesRoot -Force | Out-Null

#############################################
## FUNCTION: CREATE SHARE CLEANLY
#############################################

function New-LabShare {
    param(
        [string]$Name,
        [string]$Path,
        [array]$FullAccess = @(),
        [array]$ChangeAccess = @(),
        [array]$ReadAccess = @()
    )

    New-Item -ItemType Directory -Path $Path -Force | Out-Null

    if (-not (Get-SmbShare -Name $Name -ErrorAction SilentlyContinue)) {
        Write-Host "[+] Creating share $Name"

        New-SmbShare -Name $Name -Path $Path `
            -FullAccess "Administrators"
    }

    # Remove overly broad access (if re-run)
    @("Everyone", "Domain Users") | ForEach-Object {
        Revoke-SmbShareAccess -Name $Name -AccountName $_ -Force -ErrorAction SilentlyContinue
    }

    # Apply permissions
    foreach ($acct in $FullAccess) {
        Grant-SmbShareAccess -Name $Name -AccountName $acct -AccessRight Full -Force
    }

    foreach ($acct in $ChangeAccess) {
        Grant-SmbShareAccess -Name $Name -AccountName $acct -AccessRight Change -Force
    }

    foreach ($acct in $ReadAccess) {
        Grant-SmbShareAccess -Name $Name -AccountName $acct -AccessRight Read -Force
    }
}

#############################################
## CREATE SHARES
#############################################

# FINANCE (semi-secure)
New-LabShare `
    -Name "Finance" `
    -Path "$sharesRoot\Finance" `
    -FullAccess "$domain\sec_finance"

# IT SCRIPTS (INTENTIONALLY WEAK)
New-LabShare `
    -Name "ITScripts" `
    -Path "$sharesRoot\ITScripts" `
    -ChangeAccess "$domain\sec_helpdesk"

# BACKUPS (common lateral movement target)
New-LabShare `
    -Name "Backups" `
    -Path "$sharesRoot\Backups" `
    -FullAccess "$domain\sec_backup_ops"

# EXECUTIVE (sensitive data)
New-LabShare `
    -Name "Executive" `
    -Path "$sharesRoot\Executive" `
    -FullAccess "$domain\sec_executive"

# PUBLIC (INTENTIONALLY WEAK)
New-LabShare `
    -Name "Public" `
    -Path "$sharesRoot\Public" `
    -ReadAccess "Domain Users"

#############################################
## INTENTIONAL MISCONFIGURATIONS (LAB VALUE)
#############################################

# Add weak access back intentionally
Grant-SmbShareAccess -Name "Public" -AccountName "Everyone" -AccessRight Read -Force

# Slightly over-permission IT scripts (realistic mistake)
Grant-SmbShareAccess -Name "ITScripts" -AccountName "Domain Users" -AccessRight Read -Force

#############################################
## SAMPLE FILES
#############################################

Set-Content "$sharesRoot\Finance\Payroll.xlsx" "Sensitive payroll data"
Set-Content "$sharesRoot\Backups\backup-script.ps1" "Backup script with creds?"
Set-Content "$sharesRoot\ITScripts\deploy.ps1" "Deployment script"
Set-Content "$sharesRoot\Public\readme.txt" "Public share"
Set-Content "$sharesRoot\Executive\board-notes.txt" "Confidential executive notes"

#############################################
## OUTPUT FINAL PERMISSIONS
#############################################

Write-Host ""
Write-Host "Final Share Permissions:"
Write-Host ""

Get-SmbShare | Where-Object Name -in @("Finance","ITScripts","Backups","Executive","Public") |
ForEach-Object {
    Write-Host "---- $($_.Name) ----"
    Get-SmbShareAccess $_.Name
    Write-Host ""
}