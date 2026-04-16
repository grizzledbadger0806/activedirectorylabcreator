
# ========================================
# 8. CREATE WEAK SERVICE ACCOUNTS
# ========================================
Write-Host ""
Write-Host "[*] Creating weak service accounts..." -ForegroundColor Yellow

try {
    $domain = (Get-ADDomain -ErrorAction SilentlyContinue).DNSRoot
    $base = (Get-ADDomain -ErrorAction SilentlyContinue).DistinguishedName
    
    if ($domain) {
        $svcAccounts = @(
            @{
                SamAccountName = "svc_sql"
                DisplayName = "SQL Service Account"
                Password = "P@ssw0rd123!"
                Enabled = $true
                NeverExpires = $true
            },
            @{
                SamAccountName = "svc_backup"
                DisplayName = "Backup Service Account"  
                Password = "P@ssw0rD456$"
                Enabled = $true
                NeverExpires = $true
            },
            @{
                SamAccountName = "svc_sync"
                DisplayName = "Sync Service Account"
                Password = "P@ssw0Rd789&"
                Enabled = $true
                NeverExpires = $true
            }
        )
        
        $svcOu = "OU=ServiceAccounts,$base"
        $svcOuExists = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$svcOu'" -ErrorAction SilentlyContinue
        
        if ($svcOuExists) {
            foreach ($svc in $svcAccounts) {
                $userExists = Get-ADUser -Filter "SamAccountName -eq '$($svc.SamAccountName)'" -ErrorAction SilentlyContinue
                
                if (-not $userExists) {
                    $securePassword = ConvertTo-SecureString $svc.Password -AsPlainText -Force
                    
                    New-ADUser `
                        -SamAccountName $svc.SamAccountName `
                        -Name $svc.SamAccountName `
                        -DisplayName $svc.DisplayName `
                        -Path $svcOu `
                        -AccountPassword $securePassword `
                        -Enabled $true `
                        -PasswordNeverExpires $svc.NeverExpires `
                        -ErrorAction SilentlyContinue
                    
                    Write-Host "[+] Created service account: $($svc.SamAccountName) with password: $($svc.Password)" -ForegroundColor Green
                } else {
                    Write-Host "[!] Service account already exists: $($svc.SamAccountName)" -ForegroundColor Yellow
                }
            }
        } else {
            Write-Host "[!] ServiceAccounts OU not found" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "[!] Error creating service accounts: $_" -ForegroundColor Yellow
}
