#############################################
## PHASE 13 - LAPS MISCONFIG (FUNCTIONAL)
#############################################

Import-Module ActiveDirectory

$ErrorActionPreference = "SilentlyContinue"

$domain = (Get-ADDomain).DNSRoot
$base   = (Get-ADDomain).DistinguishedName

Write-Host "[*] Starting LAPS misconfig setup..."

#############################################
## 1. CHECK IF LAPS ATTR EXISTS
#############################################

$lapsAttrExists = $false

try {
    Get-ADObject -LDAPFilter "(name=ms-Mcs-AdmPwd)" -ErrorAction Stop | Out-Null
    $lapsAttrExists = $true
    Write-Host "[+] LAPS schema detected"
} catch {
    Write-Host "[!] LAPS schema NOT present - using fallback vulns"
}

#############################################
## 2. SET LAPS PASSWORDS (IF POSSIBLE)
#############################################

$computers = Get-ADComputer -Filter * | Select-Object -First 50
$lapsCount = 0

foreach ($comp in $computers) {
    try {
        $pwd = "LabAdmin!$(Get-Random -Minimum 1000 -Maximum 9999)"

        if ($lapsAttrExists) {
            Set-ADComputer -Identity $comp -Replace @{
                "ms-Mcs-AdmPwd" = $pwd
            }
        }

        # ALWAYS add description vuln (guaranteed exploitable)
        Set-ADComputer -Identity $comp -Description "LAPS:$pwd"

        $lapsCount++
    } catch {}
}

Write-Host "[+] LAPS-style passwords set on $lapsCount computers"

#############################################
## 3. REAL MISCONFIG: DOMAIN USERS CAN READ LAPS
#############################################

if ($lapsAttrExists) {
    Write-Host "[*] Applying weak ACLs to computers..."

    foreach ($comp in $computers) {
        try {
            $acl = Get-Acl "AD:$($comp.DistinguishedName)"

            $identity = New-Object System.Security.Principal.NTAccount("Domain Users")
            $adRights = [System.DirectoryServices.ActiveDirectoryRights]"ReadProperty"
            $type = [System.Security.AccessControl.AccessControlType]::Allow

            $guid = [Guid]"bf967a86-0de6-11d0-a285-00aa003049e2" # generic property GUID fallback

            $rule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule `
                ($identity, $adRights, $type, $guid)

            $acl.AddAccessRule($rule)
            Set-Acl -Path "AD:$($comp.DistinguishedName)" -AclObject $acl

        } catch {}
    }

    Write-Host "[!] Domain Users now have read access to LAPS attributes"
}

#############################################
## 4. CREATE WEAK SHARE WITH PASSWORD BACKUPS
#############################################

$sharePath = "C:\LAPS_Dump"
New-Item -ItemType Directory -Path $sharePath -Force | Out-Null

$dumpFile = "$sharePath\laps.txt"

$dump = @()

foreach ($comp in $computers) {
    $pwd = "LabAdmin!$(Get-Random -Minimum 1000 -Maximum 9999)"
    $dump += "$($comp.Name),$pwd"
}

$dump | Out-File $dumpFile

# 🔥 Make it world-readable
icacls $sharePath /grant "Everyone:(OI)(CI)F" /T | Out-Null

# Create SMB share (real attack surface)
if (-not (Get-SmbShare -Name "LAPS" -ErrorAction SilentlyContinue)) {
    New-SmbShare -Name "LAPS" -Path $sharePath -FullAccess "Everyone"
}

Write-Host "[!] LAPS passwords exposed via SMB share: \\$env:COMPUTERNAME\LAPS"

#############################################
## 5. OPTIONAL: NO PASSWORD ROTATION
#############################################

# Simulate stale passwords
foreach ($comp in $computers) {
    try {
        Set-ADComputer -Identity $comp -Replace @{
            "pwdLastSet" = 0
        }
    } catch {}
}

#############################################
## 6. OUTPUT ATTACK PATHS
#############################################

Write-Host ""
Write-Host "=== LAPS ATTACK PATHS ==="

Write-Host "1. LDAP Query:"
Write-Host "   Get-ADComputer -Filter * -Properties Description"

if ($lapsAttrExists) {
    Write-Host "2. Real LAPS Query:"
    Write-Host "   Get-ADComputer -Filter * -Properties ms-Mcs-AdmPwd"
}

Write-Host "3. SMB Dump:"
Write-Host "   \\$env:COMPUTERNAME\LAPS\laps.txt"

Write-Host ""
Write-Host "[+] Phase 13 complete"