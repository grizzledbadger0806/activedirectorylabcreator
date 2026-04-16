<#
.SYNOPSIS
PENTESTING LAB - Phase 11: Advanced Login Configuration
Enhanced logon patterns, RDP access, and remote access restrictions

.NOTES
Run AFTER ENVSETUP_10-LogonPatterns.ps1
FIXED: PSObject issues with Set-ADUser
#>

$ErrorActionPreference = "Continue"
$WarningPreference = "Continue"

$domain = "broken.badger.local"
$netbios = "BROKEN"
$logPath = "C:\LabSetup-Phase11-AdvancedLogin.log"

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
Write-Log "PENTESTING LAB - PHASE 11: ADVANCED LOGIN CONFIG" "SECTION"
Write-Log "================================================" "SECTION"
Write-Log "" "INFO"

Import-Module ActiveDirectory -ErrorAction Stop

$adDomain = Get-ADDomain
$base = $adDomain.DistinguishedName
$dcObj = Get-ADDomainController -Discover
$script:DC = [string]$dcObj.HostName

Write-Log "[+] Domain: $domain" "INFO"
Write-Log "[+] DC: $script:DC" "INFO"
Write-Log "" "INFO"

# 1. DISABLE PROTECTED USERS GROUP
Write-Log "[*] Configuring Protected Users group..." "SECTION"

try {
    $protectedGroup = Get-ADGroup -Filter "Name -eq 'Protected Users'" -ErrorAction SilentlyContinue
    if ($protectedGroup) {
        Write-Log "[!] Protected Users group exists (leaving empty - no admin protection)" "WARNING"
        Write-Log "    This means admins are vulnerable to credential dumping" "WARNING"
    } else {
        Write-Log "[+] Protected Users group doesn't exist (good for lab - weaker)" "SUCCESS"
    }
} catch {
    Write-Log "[!] Error checking Protected Users: $_" "WARNING"
}

Write-Log "" "INFO"

# 2. DISABLE ACCOUNT DELEGATION RESTRICTIONS
Write-Log "[*] Configuring account delegation (for Kerberos attacks)..." "SECTION"

$delegationSet = 0

try {
    $daGroup = Get-ADGroupMember -Identity "Domain Admins" | Select-Object -ExpandProperty SamAccountName
    $eaGroup = Get-ADGroupMember -Identity "Enterprise Admins" | Select-Object -ExpandProperty SamAccountName
    
    $allToDelegate = @($daGroup + $eaGroup | Get-Random -Count ([Math]::Min(5, ($daGroup.Count + $eaGroup.Count))))
    
    foreach ($member in $allToDelegate) {
        try {
            Set-ADAccountControl -Identity $member -TrustedForDelegation $true -ErrorAction SilentlyContinue
            Write-Log "[+] Enabled delegation on: $member" "SUCCESS"
            $delegationSet++
        } catch {
            Write-Log "[!] Error setting delegation: $_" "WARNING"
        }
    }
} catch {
    Write-Log "[!] Error configuring delegation: $_" "WARNING"
}

Write-Log "[+] Set delegation on $delegationSet privileged accounts" "SUCCESS"
Write-Log "" "INFO"

# 3. ENABLE SENSITIVE ACCOUNT NOT DELEGATED (some only)
Write-Log "[*] Setting 'Account is Sensitive and cannot be delegated' (selectively)..." "SECTION"

$sensitiveSet = 0

try {
    $daGroup = Get-ADGroupMember -Identity "Domain Admins" | Select-Object -ExpandProperty SamAccountName
    
    foreach ($member in $daGroup) {
        try {
            Set-ADAccountControl -Identity $member -AccountNotDelegated $true -ErrorAction SilentlyContinue
            $sensitiveSet++
        } catch {}
    }
} catch {
    Write-Log "[!] Error: $_" "WARNING"
}

Write-Log "[+] Marked $sensitiveSet admin accounts as not delegatable" "SUCCESS"
Write-Log "" "INFO"

# 6. CREATE SHARED ACCOUNTS
Write-Log "[*] Creating shared accounts (bad practice)..." "SECTION"

$sharedAccounts = @(
    @{Name="admin_shared"; Desc="Shared admin account - Finance team"},
    @{Name="support_shared"; Desc="Shared support account - IT helpdesk"},
    @{Name="backup_admin"; Desc="Backup admin account - Emergency access"},
    @{Name="contractor_acc"; Desc="Shared contractor account"},
    @{Name="guest_account"; Desc="Guest account for vendors"}
)

$sharedCreated = 0

try {
    $svcOuDn = "OU=ServiceAccounts,$base"
    
    foreach ($shared in $sharedAccounts) {
        try {
            $userExists = Get-ADUser -Filter "SamAccountName -eq '$($shared.Name)'" -ErrorAction SilentlyContinue
            
            if (-not $userExists) {
                $password = ConvertTo-SecureString "Shared@$(Get-Random -Minimum 1000 -Maximum 9999)!" -AsPlainText -Force
                
                New-ADUser -SamAccountName $shared.Name `
                    -Name $shared.Name `
                    -DisplayName $shared.Name `
                    -Description $shared.Desc `
                    -Path $svcOuDn `
                    -AccountPassword $password `
                    -Enabled $true `
                    -PasswordNeverExpires $true `
                    -ErrorAction SilentlyContinue
                
                Write-Log "[+] Created shared account: $($shared.Name)" "SUCCESS"
                $sharedCreated++
            }
        } catch {
            Write-Log "[!] Error creating $($shared.Name) : $_" "WARNING"
        }
    }
} catch {
    Write-Log "[!] Error: $_" "WARNING"
}

Write-Log "[+] Created $sharedCreated shared accounts" "SUCCESS"
Write-Log "" "INFO"

# 7. CONFIGURE REMOTE ACCESS PERMISSIONS
Write-Log "[*] Configuring remote access permissions..." "SECTION"

try {
    $rdpGroup = Get-ADGroup -Filter "Name -eq 'Remote Desktop Users'" -ErrorAction SilentlyContinue
    
    if ($rdpGroup) {
        $usersOuDn = "OU=CorpUsers,$base"
        $rdpUsers = @(Get-ADUser -SearchBase $usersOuDn -Filter * | Get-Random -Count 50)
        
        foreach ($user in $rdpUsers) {
            try {
                Add-ADGroupMember -Identity $rdpGroup -Members $user.SamAccountName -ErrorAction SilentlyContinue
            } catch {}
        }
        
        Write-Log "[+] Added 50 users to Remote Desktop Users group" "SUCCESS"
    }
} catch {
    Write-Log "[!] Error: $_" "WARNING"
}

Write-Log "" "INFO"

# 8. SET UP REMOTE ASSISTANCE
Write-Log "[*] Enabling Remote Assistance (weak security)..." "SECTION"

Write-Log "[+] Remote Assistance can be enabled for rapid credential capture" "SUCCESS"
Write-Log "    Scenario: Social engineer user to enable remote assistance" "INFO"
Write-Log "    Result: Full session access without credentials" "INFO"

Write-Log "" "INFO"

# 9. CREATE PRINTERS WITH CREDENTIALS
Write-Log "[*] Creating printer accounts (with stored credentials)..." "SECTION"

$printerAccounts = @(
    @{Name="PRINT01"; User="print_user_01"; Pass="HP123Print!"},
    @{Name="PRINT02"; User="print_user_02"; Pass="Xerox456Print!"},
    @{Name="LPSRV01"; User="lpsrv_admin"; Pass="Admin789Print!"},
    @{Name="MAILROOM_SCAN"; User="scan_user"; Pass="Scan123Copy!"}
)

$printersCreated = 0

try {
    $svcOuDn = "OU=ServiceAccounts,$base"
    
    foreach ($printer in $printerAccounts) {
        try {
            $userExists = Get-ADUser -Filter "SamAccountName -eq '$($printer.User)'" -ErrorAction SilentlyContinue
            
            if (-not $userExists) {
                $password = ConvertTo-SecureString $printer.Pass -AsPlainText -Force
                
                New-ADUser -SamAccountName $printer.User `
                    -Name "$($printer.Name) Printer User" `
                    -DisplayName "$($printer.Name) Printer" `
                    -Description "Printer: $($printer.Name) - Default Credentials: $($printer.User)" `
                    -Path $svcOuDn `
                    -AccountPassword $password `
                    -Enabled $true `
                    -PasswordNeverExpires $true `
                    -ErrorAction SilentlyContinue
                
                Write-Log "[+] Created printer account: $($printer.User)" "SUCCESS"
                $printersCreated++
            }
        } catch {
            Write-Log "[!] Error: $_" "WARNING"
        }
    }
} catch {
    Write-Log "[!] Error: $_" "WARNING"
}

Write-Log "[+] Created $printersCreated printer accounts with weak passwords" "SUCCESS"
Write-Log "" "INFO"

# 10. CONFIGURE WEB APPLICATION ACCOUNTS
Write-Log "[*] Creating web application accounts (vulnerable patterns)..." "SECTION"

$webAccounts = @(
    @{Name="app_user_web"; App="Web App"; Pass="WebApp123!"},
    @{Name="sql_app_user"; App="SQL App"; Pass="SQLPass2024"},
    @{Name="db_connect"; App="Database"; Pass="dbConnect99!"},
    @{Name="api_service"; App="API"; Pass="APIKey_2024"}
)

$webCreated = 0

try {
    $svcOuDn = "OU=ServiceAccounts,$base"
    
    foreach ($web in $webAccounts) {
        try {
            $userExists = Get-ADUser -Filter "SamAccountName -eq '$($web.Name)'" -ErrorAction SilentlyContinue
            
            if (-not $userExists) {
                $password = ConvertTo-SecureString $web.Pass -AsPlainText -Force
                
                New-ADUser -SamAccountName $web.Name `
                    -Name "$($web.App) Service Account" `
                    -DisplayName "$($web.App)" `
                    -Description "Application: $($web.App) - DO NOT SHARE - Password in web.config" `
                    -Path $svcOuDn `
                    -AccountPassword $password `
                    -Enabled $true `
                    -PasswordNeverExpires $true `
                    -ErrorAction SilentlyContinue
                
                Write-Log "[+] Created web app account: $($web.Name)" "SUCCESS"
                $webCreated++
            }
        } catch {
            Write-Log "[!] Error: $_" "WARNING"
        }
    }
} catch {
    Write-Log "[!] Error: $_" "WARNING"
}

Write-Log "[+] Created $webCreated web application accounts" "SUCCESS"
Write-Log "" "INFO"

# 11. ADD SENSITIVE DATA TO NOTES - FIXED PSObject issue
Write-Log "[*] Adding sensitive information to account attributes..." "SECTION"

$sensitiveNotes = @(
    "Legacy password: Summer2024!",
    "Recovery email: backup@personal.com",
    "PIN: 1234",
    "Security answer: Dogs",
    "Emergency contact: Wife - 555-0100",
    "Shared password with team: TempAccess99!",
    "VPN token: ABCD1234",
    "API key: sk-1234567890abcdefg"
)

$notesAdded = 0

try {
    $usersOuDn = "OU=CorpUsers,$base"
    $users = @(Get-ADUser -SearchBase $usersOuDn -Filter * -Properties SamAccountName | Get-Random -Count 20)
    
    foreach ($user in $users) {
        try {
            $note = Get-Random -InputObject $sensitiveNotes
            Set-ADUser -Identity $user.SamAccountName -Replace @{notes=$note} -ErrorAction SilentlyContinue
            $notesAdded++
        } catch {
            Write-Log "[!] Error: $_" "WARNING"
        }
    }
} catch {
    Write-Log "[!] Error: $_" "WARNING"
}

Write-Log "[+] Added sensitive notes to $notesAdded accounts" "SUCCESS"
Write-Log "" "INFO"

# 12. CREATE DISABLED ACCOUNTS - FIXED PSObject issue
Write-Log "[*] Creating disabled accounts (recovery/testing)..." "SECTION"

$disabledCount = 0

try {
    $usersOuDn = "OU=CorpUsers,$base"
    $users = @(Get-ADUser -SearchBase $usersOuDn -Filter * -Properties SamAccountName | Get-Random -Count 15)
    
    foreach ($user in $users) {
        try {
            Disable-ADAccount -Identity $user.SamAccountName -ErrorAction SilentlyContinue
            Set-ADUser -Identity $user.SamAccountName -Description "DISABLED - To be removed $((Get-Date).AddDays(60).ToShortDateString())" -ErrorAction SilentlyContinue
            $disabledCount++
        } catch {}
    }
} catch {
    Write-Log "[!] Error: $_" "WARNING"
}

Write-Log "[+] Disabled $disabledCount accounts (simulates inactive users)" "SUCCESS"
Write-Log "" "INFO"

# 13. CREATE ACCOUNTS WITH OUTDATED PASSWORDS
Write-Log "[*] Creating accounts with old passwords (for cracking)..." "SECTION"

$oldPasswords = @(
    "Welcome123",
    "Password1",
    "Admin2023",
    "Company123",
    "Letmein2023"
)

$oldPassSet = 0

try {
    $svcOuDn = "OU=ServiceAccounts,$base"
    
    foreach ($pass in $oldPasswords) {
        try {
            $username = "olduser_$([DateTime]::Now.Ticks % 10000)"
            $securePass = ConvertTo-SecureString $pass -AsPlainText -Force
            
            New-ADUser -SamAccountName $username `
                -Name "Old User - $pass" `
                -Path $svcOuDn `
                -AccountPassword $securePass `
                -Enabled $true `
                -PasswordNeverExpires $true `
                -ErrorAction SilentlyContinue
            
            $oldPassSet++
        } catch {
            Write-Log "[!] Error: $_" "WARNING"
        }
    }
} catch {
    Write-Log "[!] Error: $_" "WARNING"
}

Write-Log "[+] Created $oldPassSet accounts with weak/common passwords" "SUCCESS"
Write-Log "" "INFO"

# Completion
Write-Log "================================================" "SECTION"
Write-Log "PHASE 11 COMPLETE - ADVANCED LOGIN CONFIG" "SECTION"
Write-Log "================================================" "SECTION"
Write-Log "" "INFO"

Write-Log "VULNERABILITIES ADDED:" "INFO"
Write-Log "  [+] Delegation enabled on some privileged accounts (Kerberos attack)" "INFO"
Write-Log "  [+] No Protected Users group enforcement" "INFO"
Write-Log "  [+] Shared accounts (credential stuffing)" "INFO"
Write-Log "  [+] Printer accounts with weak passwords" "INFO"
Write-Log "  [+] Web app accounts with default credentials" "INFO"
Write-Log "  [+] Sensitive data in account notes" "INFO"
Write-Log "  [+] Disabled accounts (recovery targets)" "INFO"
Write-Log "  [+] Accounts with old/weak passwords" "INFO"
Write-Log "  [+] Remote Desktop access for many users" "INFO"
Write-Log "" "INFO"

Write-Log "EXPLOITATION PATHS NOW AVAILABLE:" "INFO"
Write-Log "  [*] Credential theft from shared accounts" "INFO"
Write-Log "  [*] Printer account compromise → network access" "INFO"
Write-Log "  [*] Web application credential dumping" "INFO"
Write-Log "  [*] Account recovery via disabled accounts" "INFO"
Write-Log "  [*] Dictionary attacks with weak passwords" "INFO"
Write-Log "  [*] RDP access via group membership" "INFO"
Write-Log "  [*] Kerberos delegation attacks" "INFO"
Write-Log "" "INFO"

Write-Log "[+] Phase 11 complete! Log: $logPath" "SUCCESS"
