#############################################
## PHASE 12 - VULNERABLE GPO SETUP (REAL)
#############################################

Import-Module ActiveDirectory
Import-Module GroupPolicy

$ErrorActionPreference = "SilentlyContinue"

$domain = (Get-ADDomain).DNSRoot
$base   = (Get-ADDomain).DistinguishedName
$dc     = (Get-ADDomainController -Discover).HostName

#############################################
## HELPER: CREATE GPO IF NOT EXISTS
#############################################

function New-LabGPO {
    param($Name, $Comment, $Link)

    $gpo = Get-GPO -Name $Name -ErrorAction SilentlyContinue

    if (-not $gpo) {
        $gpo = New-GPO -Name $Name -Comment $Comment
        New-GPLink -Name $Name -Target $Link -LinkEnabled Yes
        Write-Host "[+] Created GPO: $Name"
    }

    return $gpo
}

#############################################
## 1. WEAK PERMISSIONS GPO (REAL DACL ABUSE)
#############################################

$gpo1 = New-LabGPO `
    "LAB-WeakPermissions" `
    "Users can modify this GPO" `
    "OU=Workstations,$base"

# 🔥 ACTUAL VULN: Domain Users can edit GPO
Set-GPPermission `
    -Name $gpo1.DisplayName `
    -TargetName "Domain Users" `
    -TargetType Group `
    -PermissionLevel GpoEdit `
    -Replace

#############################################
## 2. POWERSHELL BYPASS
#############################################

$gpo2 = New-LabGPO `
    "LAB-PowerShell-Bypass" `
    "ExecutionPolicy Bypass" `
    "OU=Servers,$base"

Set-GPRegistryValue `
    -Name $gpo2.DisplayName `
    -Key "HKLM\Software\Policies\Microsoft\Windows\PowerShell" `
    -ValueName "ExecutionPolicy" `
    -Type String `
    -Value "Bypass"

#############################################
## 3. RDP WEAK CONFIG
#############################################

$gpo3 = New-LabGPO `
    "LAB-RDP-Weak" `
    "Weak RDP config" `
    "OU=Workstations,$base"

# Enable RDP
Set-GPRegistryValue `
    -Name $gpo3.DisplayName `
    -Key "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" `
    -ValueName "fDenyTSConnections" `
    -Type DWord `
    -Value 0

# Disable NLA
Set-GPRegistryValue `
    -Name $gpo3.DisplayName `
    -Key "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" `
    -ValueName "UserAuthentication" `
    -Type DWord `
    -Value 0

#############################################
## 4. DISABLE DEFENDER
#############################################

$gpo4 = New-LabGPO `
    "LAB-Security-Disabled" `
    "Disable Defender" `
    "OU=Workstations,$base"

Set-GPRegistryValue `
    -Name $gpo4.DisplayName `
    -Key "HKLM\Software\Policies\Microsoft\Windows Defender" `
    -ValueName "DisableAntiSpyware" `
    -Type DWord `
    -Value 1

#############################################
## 5. LOGON SCRIPT (SYSVOL ABUSE)
#############################################

$gpo5 = New-LabGPO `
    "LAB-LogonScripts" `
    "Logon persistence" `
    "OU=CorpUsers,$base"

$gpo5Obj = Get-GPO -Name "LAB-LogonScripts"
$guid = $gpo5Obj.Id

$scriptPath = "\\$dc\SYSVOL\$domain\Policies\{$guid}\User\Scripts\Logon"
New-Item -ItemType Directory -Path $scriptPath -Force | Out-Null

# Drop script
$scriptFile = "$scriptPath\logon.bat"
Set-Content $scriptFile @"
whoami > C:\Windows\Temp\logon.txt
"@

# Link script in GPO
Set-GPRegistryValue `
    -Name $gpo5.DisplayName `
    -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Group Policy\Scripts\Logon\0\0" `
    -ValueName "Script" `
    -Type String `
    -Value "logon.bat"

#############################################
## 6. LOCAL ADMIN VIA GPP (SIMULATED)
#############################################

$gpo6 = New-LabGPO `
    "LAB-LocalAdmin" `
    "Adds local admin (weak)" `
    "OU=Servers,$base"

# 🔥 Simulate via registry (real labs often use GPP XML)
Set-GPRegistryValue `
    -Name $gpo6.DisplayName `
    -Key "HKLM\Software\Microsoft\Windows NT\CurrentVersion\Winlogon" `
    -ValueName "DefaultUserName" `
    -Type String `
    -Value "labadmin"

#############################################
## 7. FIREWALL WEAKNESS
#############################################

$gpo7 = New-LabGPO `
    "LAB-Firewall-Exceptions" `
    "Firewall disabled" `
    "$base"

Set-GPRegistryValue `
    -Name $gpo7.DisplayName `
    -Key "HKLM\Software\Policies\Microsoft\WindowsFirewall\DomainProfile" `
    -ValueName "EnableFirewall" `
    -Type DWord `
    -Value 0

#############################################
## OUTPUT
#############################################

Write-Host ""
Write-Host "=== CREATED GPOs ==="
Get-GPO -All | Where DisplayName -like "LAB-*" |
Select DisplayName, Id