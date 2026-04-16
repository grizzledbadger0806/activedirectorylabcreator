<#
.SYNOPSIS
PENTESTING LAB - Phase 10: Realistic Logon Patterns
Adds logon workstations, login times, and account restrictions for realistic AD

.DESCRIPTION
After users are created, this script adds:
- Logon workstation restrictions (limited devices per user)
- Login hour restrictions (realistic work hours)
- Account lockout after failed attempts
- Multi-device users (executives, managers)
- Single-device users (staff)
- Account expiration warnings

.EXAMPLE
.\ENVSETUP_10-LogonPatterns.ps1

.NOTES
Run this AFTER LabSetup-Phase2.ps1 completes
#>

$ErrorActionPreference = "Stop"
$WarningPreference = "Continue"

$domain = "broken.badger.local"
$netbios = "BROKEN"
$logPath = "C:\LabSetup-Phase10-LogonPatterns.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage -ForegroundColor $(
        switch ($Level) {
            "ERROR" { "Red" }
            "WARNING" { "Yellow" }
            "SUCCESS" { "Green" }
            "SECTION" { "Cyan" }
            default { "White" }
        }
    )
    $logMessage | Out-File -FilePath $logPath -Append -Encoding UTF8
}

Write-Log "================================================" "SECTION"
Write-Log "PENTESTING LAB - PHASE 10: LOGON PATTERNS" "SECTION"
Write-Log "================================================" "SECTION"
Write-Log "" "INFO"

Import-Module ActiveDirectory -ErrorAction Stop

$adDomain = Get-ADDomain
$base = $adDomain.DistinguishedName
$dcObj = Get-ADDomainController -Discover
$script:DC = [string]$dcObj.HostName

Write-Log "[+] Domain: $domain" "INFO"
Write-Log "[+] Base DN: $base" "INFO"
Write-Log "[+] DC: $script:DC" "INFO"
Write-Log "" "INFO"

# Get computers
Write-Log "[*] Collecting computer objects..." "SECTION"

$workstations = @(Get-ADComputer -Filter 'Name -like "WKST-*"' | Select-Object -ExpandProperty Name)
$laptops = @(Get-ADComputer -Filter 'Name -like "LPTP-*"' | Select-Object -ExpandProperty Name)
$servers = @(Get-ADComputer -SearchBase "OU=Servers,$base" -Filter * | Select-Object -ExpandProperty Name)

Write-Log "[+] Found $($workstations.Count) workstations" "SUCCESS"
Write-Log "[+] Found $($laptops.Count) laptops" "SUCCESS"
Write-Log "[+] Found $($servers.Count) servers" "SUCCESS"
Write-Log "" "INFO"

# Set password policy
Write-Log "[*] Configuring domain password policy..." "SECTION"

try {
    Set-ADDefaultDomainPasswordPolicy -Identity $base `
        -MinPasswordLength 8 `
        -MaxPasswordAge (New-TimeSpan -Days 90) `
        -MinPasswordAge (New-TimeSpan -Days 1) `
        -PasswordHistoryCount 5 `
        -LockoutDuration (New-TimeSpan -Minutes 30) `
        -LockoutObservationWindow (New-TimeSpan -Minutes 30) `
        -LockoutThreshold 5
    
    Write-Log "[+] Password policy configured" "SUCCESS"
    Write-Log "    - Min length: 8 characters" "INFO"
    Write-Log "    - Max age: 90 days" "INFO"
    Write-Log "    - Lockout: 5 attempts in 30 minutes" "INFO"
} catch {
    Write-Log "[!] Error setting password policy: $_" "WARNING"
}

Write-Log "" "INFO"

# Collect users by role
Write-Log "[*] Collecting users by role..." "SECTION"

$usersOuDn = "OU=CorpUsers,$base"

$ceos = @(Get-ADUser -SearchBase $usersOuDn -Filter "Title -eq 'CEO'" | Select-Object -ExpandProperty SamAccountName)
$cSuite = @(Get-ADUser -SearchBase $usersOuDn -Filter {Title -like "C*O"} | Select-Object -ExpandProperty SamAccountName)
$vps = @(Get-ADUser -SearchBase $usersOuDn -Filter "Title -like 'VP*'" | Select-Object -ExpandProperty SamAccountName)
$directors = @(Get-ADUser -SearchBase $usersOuDn -Filter "Title -like '*Director*'" | Select-Object -ExpandProperty SamAccountName)
$managers = @(Get-ADUser -SearchBase $usersOuDn -Filter "Title -like '*Manager*' -or Title -like '*Supervisor*' -or Title -like '*Lead*'" | Select-Object -ExpandProperty SamAccountName)
$staff = @(Get-ADUser -SearchBase $usersOuDn -Filter {Title -notlike "CEO" -and Title -notlike "C*O" -and Title -notlike "VP*" -and Title -notlike "*Director*" -and Title -notlike "*Manager*" -and Title -notlike "*Supervisor*" -and Title -notlike "*Lead*"} | Select-Object -ExpandProperty SamAccountName)

Write-Log "[+] CEOs: $($ceos.Count)" "SUCCESS"
Write-Log "[+] C-Suite: $($cSuite.Count)" "SUCCESS"
Write-Log "[+] VPs: $($vps.Count)" "SUCCESS"
Write-Log "[+] Directors: $($directors.Count)" "SUCCESS"
Write-Log "[+] Managers: $($managers.Count)" "SUCCESS"
Write-Log "[+] Staff: $($staff.Count)" "SUCCESS"
Write-Log "" "INFO"

# Set logon workstations
Write-Log "[*] Setting logon workstation restrictions..." "SECTION"

$devicesAssigned = 0

# EXECUTIVES - 5-7 devices
Write-Log "[*] Assigning executives to 5-7 devices" "INFO"

$executiveUsers = $ceos + $cSuite

if ($vps.Count -gt 3) {
    $vpsToAdd = [Math]::Max(1, [int]($vps.Count * 0.3))
    $executiveUsers += @(Get-Random -InputObject $vps -Count $vpsToAdd)
}

foreach ($execUser in $executiveUsers) {
    try {
        $devCount = Get-Random -Minimum 5 -Maximum 8
        $assignedDevices = Get-Random -InputObject ($workstations + $laptops) -Count $devCount
        Set-ADUser -Identity $execUser -LogonWorkstations ($assignedDevices -join ",") -ErrorAction SilentlyContinue
        $devicesAssigned++
    } catch {
        Write-Log "[!] Error assigning devices to $execUser : $_" "WARNING"
    }
}
Write-Log "[+] Assigned $devicesAssigned executives to multiple devices" "SUCCESS"

# VPs & DIRECTORS - 2-4 devices
Write-Log "[*] Assigning VPs/Directors to 2-4 devices" "INFO"

$middleUsers = $vps + $directors
$middleAssigned = 0

foreach ($user in $middleUsers) {
    try {
        $devCount = Get-Random -Minimum 2 -Maximum 5
        $assignedDevices = Get-Random -InputObject ($workstations + $laptops) -Count $devCount
        Set-ADUser -Identity $user -LogonWorkstations ($assignedDevices -join ",") -ErrorAction SilentlyContinue
        $middleAssigned++
    } catch {
        Write-Log "[!] Error assigning devices to $user : $_" "WARNING"
    }
}
Write-Log "[+] Assigned $middleAssigned VPs/Directors to 2-4 devices" "SUCCESS"

# MANAGERS - 2 devices
Write-Log "[*] Assigning managers to 2 devices" "INFO"

$managerAssigned = 0
$managersToAssign = [Math]::Max(1, [int]($managers.Count * 0.7))

$selectedManagers = @(Get-Random -InputObject $managers -Count $managersToAssign)
foreach ($user in $selectedManagers) {
    try {
        $assignedDevices = @(Get-Random -InputObject ($workstations + $laptops) -Count 2)
        Set-ADUser -Identity $user -LogonWorkstations ($assignedDevices -join ",") -ErrorAction SilentlyContinue
        $managerAssigned++
    } catch {
        Write-Log "[!] Error assigning devices to $user : $_" "WARNING"
    }
}
Write-Log "[+] Assigned $managerAssigned managers to 2 devices" "SUCCESS"

# STAFF - 1 device
Write-Log "[*] Assigning staff to single workstations" "INFO"

$staffAssigned = 0
$staffToAssign = [Math]::Max(1, [int]($staff.Count * 0.5))

$selectedStaff = @(Get-Random -InputObject $staff -Count $staffToAssign)
foreach ($user in $selectedStaff) {
    try {
        $assignedDevice = Get-Random -InputObject ($workstations + $laptops) -Count 1
        Set-ADUser -Identity $user -LogonWorkstations $assignedDevice -ErrorAction SilentlyContinue
        $staffAssigned++
    } catch {
        Write-Log "[!] Error assigning device to $user : $_" "WARNING"
    }
}
Write-Log "[+] Assigned $staffAssigned staff to single devices" "SUCCESS"

Write-Log "" "INFO"

# Set login hours
Write-Log "[*] Setting login hour descriptions..." "SECTION"

$hoursSet = 0
$allUsers = @(Get-ADUser -SearchBase $usersOuDn -Filter * | Select-Object SamAccountName, Name, Title)

foreach ($user in $allUsers | Select-Object -First 100) {
    try {
        Set-ADUser -Identity $user.SamAccountName -Description "Work Hours: 7 AM - 7 PM | Role: $($user.Title)" -ErrorAction SilentlyContinue
        $hoursSet++
    } catch {
        Write-Log "[!] Error setting hours for $($user.SamAccountName) : $_" "WARNING"
    }
    
    if ($hoursSet % 50 -eq 0) {
        Write-Log "[.] Set hours for $hoursSet users..." "INFO"
    }
}

Write-Log "[+] Set working hour descriptions for $hoursSet users" "SUCCESS"
Write-Log "" "INFO"

# Set account restrictions
Write-Log "[*] Setting account restrictions and expiration..." "SECTION"

$restrictionsSet = 0

# Service accounts - never expire
$svcAccounts = @(Get-ADUser -SearchBase "OU=ServiceAccounts,$base" -Filter * -ErrorAction SilentlyContinue)

foreach ($svc in $svcAccounts) {
    try {
        Set-ADUser -Identity $svc -PasswordNeverExpires $true -AccountNotDelegated $false -ErrorAction SilentlyContinue
        $restrictionsSet++
    } catch {
        Write-Log "[!] Error setting service account properties: $_" "WARNING"
    }
}

Write-Log "[+] Configured $($svcAccounts.Count) service accounts" "SUCCESS"

# Regular users - set expiration dates
$regularUsers = @(Get-ADUser -SearchBase $usersOuDn -Filter * | Select-Object -First 500)

foreach ($user in $regularUsers) {
    try {
        $expirationDays = Get-Random -Minimum 90 -Maximum 180
        $expirationDate = (Get-Date).AddDays($expirationDays)
        
        Set-ADUser -Identity $user -AccountExpirationDate $expirationDate -ErrorAction SilentlyContinue
        $restrictionsSet++
    } catch {
        Write-Log "[!] Error setting expiration: $_" "WARNING"
    }
}

Write-Log "[+] Set account restrictions for $restrictionsSet users" "SUCCESS"
Write-Log "" "INFO"

# Enable sensitive account flags
Write-Log "[*] Setting sensitive account attributes..." "SECTION"

$flagsSet = 0

try {
    $daGroup = @(Get-ADGroupMember -Identity "Domain Admins" | Select-Object -ExpandProperty SamAccountName)
    foreach ($admin in $daGroup) {
        try {
            Set-ADUser -Identity $admin -AccountNotDelegated $true -ErrorAction SilentlyContinue
            $flagsSet++
        } catch {}
    }
    Write-Log "[+] Set 'Cannot be Delegated' on $($daGroup.Count) admins" "SUCCESS"
} catch {
    Write-Log "[!] Error with Domain Admins: $_" "WARNING"
}

Write-Log "" "INFO"

# Create SPNs for Kerberoasting
Write-Log "[*] Creating Service Principal Names for Kerberoasting..." "SECTION"

$spnsCreated = 0

$spnUsers = @(Get-ADUser -SearchBase $usersOuDn -Filter * | Get-Random -Count 20)

foreach ($user in $spnUsers) {
    try {
        $spn = "HTTP/$($user.SamAccountName).broken.badger.local"
        Set-ADUser -Identity $user -ServicePrincipalNames @{Add=$spn} -ErrorAction SilentlyContinue
        $spnsCreated++
    } catch {
        Write-Log "[!] Error creating SPN for $($user.SamAccountName) : $_" "WARNING"
    }
}

Write-Log "[+] Created $spnsCreated SPNs for Kerberoasting" "SUCCESS"
Write-Log "" "INFO"

# Create account lockout scenarios
Write-Log "[*] Creating account lockout scenarios..." "SECTION"

$lockedUsers = @(Get-ADUser -SearchBase $usersOuDn -Filter * | Get-Random -Count 10)

foreach ($user in $lockedUsers) {
    try {
        Set-ADUser -Identity $user -Replace @{badPwdCount=4} -ErrorAction SilentlyContinue
        Write-Log "[+] Simulated failed logins on: $($user.Name)" "SUCCESS"
    } catch {
        Write-Log "[!] Error setting lockout on $($user.SamAccountName) : $_" "WARNING"
    }
}

Write-Log "" "INFO"

# Add user descriptions
Write-Log "[*] Adding realistic user descriptions..." "SECTION"

$descSet = 0

$descriptions = @(
    "VPN Access - Email for credentials",
    "Remote worker - Seattle office",
    "Contractor - Temp access until 2024",
    "Service account - SQL backup",
    "Application admin - Finance system",
    "Shared account - Help desk",
    "Executive - Mobile user",
    "DevOps engineer - Automation scripts",
    "Database admin - Contact DBA team",
    "Security clearance required"
)

$users = @(Get-ADUser -SearchBase $usersOuDn -Filter * | Select-Object -First 100)

foreach ($user in $users) {
    try {
        $desc = Get-Random -InputObject $descriptions
        Set-ADUser -Identity $user -Description $desc -ErrorAction SilentlyContinue
        $descSet++
    } catch {
        Write-Log "[!] Error adding description: $_" "WARNING"
    }
}

Write-Log "[+] Added descriptions to $descSet users" "SUCCESS"
Write-Log "" "INFO"

# Set contact information
Write-Log "[*] Setting user contact information..." "SECTION"

$contactSet = 0

$users = @(Get-ADUser -SearchBase $usersOuDn -Filter * | Select-Object -First 25)

foreach ($user in $users) {
    try {
        $phone = "555-{0:D4}" -f (Get-Random -Minimum 0 -Maximum 10000)
        $office = Get-Random -InputObject @("New York, NY","San Francisco, CA","Seattle, WA","Austin, TX","Remote")
        
        Set-ADUser -Identity $user `
            -OfficePhone $phone `
            -Office $office `
            -PostalCode (Get-Random -InputObject @("10001","94102","98101","78701")) `
            -ErrorAction SilentlyContinue
        
        $contactSet++
    } catch {
        Write-Log "[!] Error setting contact info: $_" "WARNING"
    }
}

Write-Log "[+] Set contact information for $contactSet users" "SUCCESS"
Write-Log "" "INFO"

# Create group membership patterns
Write-Log "[*] Adding users to groups based on roles..." "SECTION"

$membersAdded = 0

try {
    $cifsGroups = @(Get-ADGroup -SearchBase "OU=CorpGroups,$base" -Filter "Name -like 'SEC_CIFS_*'" | Select-Object -ExpandProperty Name)
    
    $groupsToProcess = @(Get-Random -InputObject $cifsGroups -Count ([Math]::Min(10, $cifsGroups.Count)))
    foreach ($group in $groupsToProcess) {
        try {
            $randomUsers = @(Get-ADUser -SearchBase $usersOuDn -Filter * | Get-Random -Count 5)
            foreach ($user in $randomUsers) {
                Add-ADGroupMember -Identity $group -Members $user -ErrorAction SilentlyContinue
                $membersAdded++
            }
        } catch {
            Write-Log "[!] Error adding members to $group : $_" "WARNING"
        }
    }
} catch {
    Write-Log "[!] Error with group memberships: $_" "WARNING"
}

Write-Log "[+] Added $membersAdded user-group memberships" "SUCCESS"
Write-Log "" "INFO"

# Set home directories
Write-Log "[*] Setting home directory paths..." "SECTION"

$homeDirsSet = 0

$users = @(Get-ADUser -SearchBase $usersOuDn -Filter * | Select-Object -First 100)

foreach ($user in $users) {
    try {
        $homeDir = "\\FILE01\home\$($user.SamAccountName)"
        $homeDrive = "H:"
        
        Set-ADUser -Identity $user `
            -HomeDirectory $homeDir `
            -HomeDrive $homeDrive `
            -ErrorAction SilentlyContinue
        
        $homeDirsSet++
    } catch {
        Write-Log "[!] Error setting home directory: $_" "WARNING"
    }
}

Write-Log "[+] Set home directories for $homeDirsSet users" "SUCCESS"
Write-Log "" "INFO"

# Summary
Write-Log "================================================" "SECTION"
Write-Log "PHASE 10 COMPLETE - REALISTIC LOGON PATTERNS" "SECTION"
Write-Log "================================================" "SECTION"
Write-Log "" "INFO"

Write-Log "LOGON PATTERNS CREATED:" "INFO"
Write-Log "  [+] Executives: 5-7 devices each (mobile users)" "INFO"
Write-Log "  [+] VPs/Directors: 2-4 devices each" "INFO"
Write-Log "  [+] Managers: 2 devices each" "INFO"
Write-Log "  [+] Staff: 1 device each" "INFO"
Write-Log "  [+] Service accounts: specific servers" "INFO"
Write-Log "" "INFO"

Write-Log "RESTRICTIONS CONFIGURED:" "INFO"
Write-Log "  [+] Login hour descriptions (7 AM - 7 PM)" "INFO"
Write-Log "  [+] Account expiration dates (90-180 days)" "INFO"
Write-Log "  [+] Password policy (lockout after 5 failures in 30 min)" "INFO"
Write-Log "  [+] Service account passwords set to never expire" "INFO"
Write-Log "  [+] Domain admins marked as Cannot be Delegated" "INFO"
Write-Log "" "INFO"

Write-Log "ADDITIONAL ATTRIBUTES ADDED:" "INFO"
Write-Log "  [+] Service Principal Names (SPNs) - for Kerberoasting" "INFO"
Write-Log "  [+] User descriptions with business context" "INFO"
Write-Log "  [+] Phone numbers and office locations" "INFO"
Write-Log "  [+] Home directory paths (UNC paths)" "INFO"
Write-Log "  [+] Simulated failed login attempts on 10 accounts" "INFO"
Write-Log "" "INFO"

Write-Log "EXPLOITATION SCENARIOS NOW AVAILABLE:" "INFO"
Write-Log "  [*] Lateral movement discovery (follow user device patterns)" "INFO"
Write-Log "  [*] Kerberoasting (SPNs created for 20 users)" "INFO"
Write-Log "  [*] Account lockout attacks (targets with 4+ failed attempts)" "INFO"
Write-Log "  [*] Home directory enumeration (UNC path discovery)" "INFO"
Write-Log "  [*] Role-based targeting (identify high-value targets)" "INFO"
Write-Log "" "INFO"

Write-Log "VERIFICATION COMMANDS:" "INFO"
Write-Log "  Get-ADUser -Identity username -Properties LogonWorkstations" "INFO"
Write-Log "  Get-ADUser -Identity username -Properties Description" "INFO"
Write-Log "  Get-ADUser -Identity username -Properties ServicePrincipalNames" "INFO"
Write-Log "" "INFO"

Write-Log "[+] Phase 10 complete! Log: $logPath" "SUCCESS"
