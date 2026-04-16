<#
.SYNOPSIS
    ESC Template Audit and Testing Script
    
.DESCRIPTION
    Audits and tests the created vulnerable certificate templates
    - Enumerates all created templates
    - Tests permissions
    - Validates vulnerabilities
    - Provides exploitation guidance
    
.NOTES
    Requires: ActiveDirectory module, Enterprise Admin or Domain Admin
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$DomainDN,
    
    [Parameter(Mandatory=$false)]
    [switch]$TestExploitation,
    
    [Parameter(Mandatory=$false)]
    [switch]$GenerateReport
)

$ErrorActionPreference = "Continue"

##============================================================================
## FUNCTIONS
##============================================================================

function Get-DomainInfo {
    $domain = Get-ADDomain
    return @{
        Domain = $domain.DNSRoot
        BaseDN = $domain.DistinguishedName
    }
}

function Invoke-TemplateEnumeration {
    param([string]$BaseDN)
    
    Write-Host "`n[*] TEMPLATE ENUMERATION`n" -ForegroundColor Cyan
    
    $templates = Get-ADObject -SearchBase "CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,$BaseDN" `
        -Filter { Name -like "Vuln*" -or Name -like "Secure*" } `
        -Properties * | Sort-Object Name
    
    Write-Host "[+] Found $($templates.Count) test templates`n"
    
    return $templates
}

function Test-TemplateVulnerability {
    param(
        [Parameter(Mandatory=$true)]$Template,
        [Parameter(Mandatory=$false)][string]$BaseDN
    )
    
    $results = @{
        Name = $Template.Name
        DisplayName = $Template.DisplayName
        Vulnerabilities = @()
        Details = @()
    }
    
    # Check ESC1: Overly permissive enrollment + SAN
    $nameFlag = $Template.msPKICertificateNameFlag
    if ($nameFlag -eq 1) {
        $results.Vulnerabilities += "ESC1_SAN_ENABLED"
        $results.Details += "Template allows SAN supply"
    }
    
    # Check enrollment rights
    try {
        $templateDN = $Template.DistinguishedName
        $acl = Get-ACL "AD:\$templateDN" -ErrorAction SilentlyContinue
        
        $authUserRule = $acl.Access | Where-Object { 
            $_.IdentityReference -like "*Authenticated Users*" -or 
            $_.IdentityReference -like "*Domain Users*"
        }
        
        if ($authUserRule) {
            if ($nameFlag -eq 1) {
                $results.Vulnerabilities += "ESC1_LOW_PRIV_ENROLLMENT"
                $results.Details += "Low-privilege users can enroll with SAN enabled"
            }
        }
        
        # Check write/modify permissions
        $writeRule = $acl.Access | Where-Object { 
            $_.ActiveDirectoryRights -like "*WriteProperty*" -and
            ($_.IdentityReference -like "*Domain Users*" -or
             $_.IdentityReference -like "*Authenticated Users*")
        }
        
        if ($writeRule) {
            $results.Vulnerabilities += "ESC4_MODIFY_TEMPLATE"
            $results.Details += "Low-privilege users can modify template"
        }
    } catch {
        $results.Details += "Could not check ACLs: $_"
    }
    
    # Check for enrollment agent
    $ekuList = $Template.pKIExtendedKeyUsage
    if ($ekuList) {
        if ($ekuList -contains "1.3.6.1.4.1.311.20.2") {
            $results.Vulnerabilities += "ESC2_ENROLLMENT_AGENT"
            $results.Details += "Template is an Enrollment Agent"
        }
    }
    
    # Check enrollment flags
    $enrollFlag = $Template.msPKIEnrollmentFlag
    if ($enrollFlag) {
        if ($enrollFlag -band 0x00000001) {
            $results.Details += "Published to DS"
        }
        if ($enrollFlag -band 0x00000002) {
            $results.Details += "Includes symmetric algorithms"
        }
    }
    
    return $results
}

function Get-TemplateACLs {
    param([Parameter(Mandatory=$true)]$Template)
    
    $templateDN = $Template.DistinguishedName
    
    try {
        $acl = Get-ACL "AD:\$templateDN" -ErrorAction SilentlyContinue
        $access = $acl.Access | Select-Object IdentityReference, ActiveDirectoryRights, AccessControlType, @{
            Name="IsInherited"
            Expression={$_.IsInherited}
        }
        
        return $access
    } catch {
        Write-Warning "Could not retrieve ACL for $($Template.Name): $_"
        return $null
    }
}

function Test-EnrollmentPermissions {
    param([Parameter(Mandatory=$true)]$Template)
    
    Write-Host "  [*] Checking enrollment permissions..."
    
    $templateDN = $Template.DistinguishedName
    
    try {
        $acl = Get-ACL "AD:\$templateDN"
        
        $enrollmentGUID = "0e10c968-78fb-11d2-90d4-00c04f79dc61"
        $enrollRules = $acl.Access | Where-Object { 
            $_.ObjectType -eq $enrollmentGUID
        }
        
        if ($enrollRules) {
            foreach ($rule in $enrollRules) {
                $principal = $rule.IdentityReference
                $access = $rule.ActiveDirectoryRights
                Write-Host "      - $principal : $access"
            }
            return $enrollRules.Count
        } else {
            Write-Host "      - No enrollment-specific rules found"
            return 0
        }
    } catch {
        Write-Warning "Could not check enrollment rules: $_"
        return -1
    }
}

function Get-CATemplates {
    param([Parameter(Mandatory=$false)][string]$CAName)
    
    Write-Host "`n[*] PUBLISHED CA TEMPLATES`n" -ForegroundColor Cyan
    
    try {
        if ($CAName) {
            $caArray = @($CAName)
        } else {
            # Find all CAs
            $caArray = (Get-ADObject -Filter { objectClass -eq "pKIEnrollmentService" } -Properties dNSHostName).dNSHostName
        }
        
        foreach ($ca in $caArray) {
            Write-Host "[+] Checking CA: $ca"
            
            # This would require PSPKI module
            # For now, just list what we can query from AD
            Get-ADObject -SearchBase "CN=$ca,CN=Enrollment Services,CN=Public Key Services,CN=Services,CN=Configuration,DC=*" `
                -Filter { objectClass -eq "pKICertificateTemplate" } `
                -Properties * -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
        }
    } catch {
        Write-Warning "Could not enumerate CA templates: $_"
    }
}

function Get-CAEditFlags {
    Write-Host "`n[*] CA EDIT FLAGS (ESC6 Detection)`n" -ForegroundColor Cyan
    
    Write-Host "[!] To check CA registry flags, run on CA or with CA admin access:`n"
    Write-Host "    certutil -getreg policy\EditFlags`n"
    Write-Host "    Look for: EDITF_ATTRIBUTESUBJECTALTNAMEFORCESUPPLIED (0x00040000)`n"
}

function Invoke-ExploitationTest {
    param([Parameter(Mandatory=$true)]$Template)
    
    Write-Host "`n[*] EXPLOITATION SIMULATION`n" -ForegroundColor Yellow
    
    $vulns = @()
    
    # Simulate ESC1
    if ($Template.msPKICertificateNameFlag -eq 1) {
        Write-Host "[SIMULATING] ESC1 Exploitation"
        Write-Host "  Step 1: Request certificate for template"
        Write-Host "    certreq -new request.inf request.req"
        Write-Host "  Step 2: Submit with Administrator SAN"
        Write-Host '    certreq -submit -attrib "SAN=upn=Administrator@domain.com" request.req'
        Write-Host "  Step 3: Use certificate for authentication`n"
        $vulns += "ESC1"
    }
    
    # Simulate ESC4
    if (Test-ModifyPermissions $Template) {
        Write-Host "[SIMULATING] ESC4 Exploitation"
        Write-Host "  Step 1: Modify template to enable SAN"
        Write-Host '    Set-ADObject -Identity "CN=$($Template.Name),..." -Replace @{msPKICertificateNameFlag = 1}'
        Write-Host "  Step 2: Request certificate with SAN`n"
        $vulns += "ESC4"
    }
    
    return $vulns
}

function Test-ModifyPermissions {
    param([Parameter(Mandatory=$true)]$Template)
    
    try {
        $templateDN = $Template.DistinguishedName
        $acl = Get-ACL "AD:\$templateDN"
        
        $writeRule = $acl.Access | Where-Object { 
            $_.ActiveDirectoryRights -like "*Write*" -or
            $_.ActiveDirectoryRights -like "*Modify*"
        }
        
        return [bool]$writeRule
    } catch {
        return $false
    }
}

function Generate-AuditReport {
    param(
        [Parameter(Mandatory=$true)]$Templates,
        [Parameter(Mandatory=$false)][string]$OutputPath
    )
    
    Write-Host "`n[*] GENERATING AUDIT REPORT`n" -ForegroundColor Cyan
    
    $report = @()
    $report += "# ESC Vulnerability Audit Report"
    $report += "Generated: $(Get-Date)"
    $report += ""
    $report += "## Summary"
    $report += "Total Templates: $($Templates.Count)"
    
    $vulnCount = 0
    $secureCount = 0
    
    foreach ($template in $Templates) {
        $vuln = Test-TemplateVulnerability -Template $template
        if ($vuln.Vulnerabilities.Count -gt 0) {
            $vulnCount++
        } elseif ($template.Name -like "Secure*") {
            $secureCount++
        }
    }
    
    $report += "Vulnerable Templates: $vulnCount"
    $report += "Secure Templates: $secureCount"
    $report += ""
    
    $report += "## Vulnerable Templates Detected"
    $report += ""
    
    foreach ($template in $Templates) {
        $vuln = Test-TemplateVulnerability -Template $template
        
        if ($vuln.Vulnerabilities.Count -gt 0) {
            $report += "### $($template.Name)"
            $report += "**Display Name:** $($template.DisplayName)"
            $report += "**Vulnerabilities:** $($vuln.Vulnerabilities -join ', ')"
            $report += ""
            
            foreach ($detail in $vuln.Details) {
                $report += "- $detail"
            }
            $report += ""
        }
    }
    
    $report += "## Remediation"
    $report += ""
    $report += "1. Restrict enrollment to specific groups"
    $report += "2. Disable SAN supply (set msPKICertificateNameFlag = 0)"
    $report += "3. Remove low-privilege write permissions"
    $report += "4. Require manager approval for enrollment"
    $report += "5. Audit CA for dangerous registry flags"
    $report += ""
    
    if ($OutputPath) {
        $report | Out-File -FilePath $OutputPath -Encoding UTF8
        Write-Host "[+] Report saved to: $OutputPath"
    } else {
        $report | Out-Host
    }
    
    return $report
}

##============================================================================
## MAIN EXECUTION
##============================================================================

Write-Host @"
╔════════════════════════════════════════════════════════════════════════════╗
║                  ESC CERTIFICATE TEMPLATE AUDIT TOOL                       ║
║                     Vulnerable Template Testing                            ║
╚════════════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

# Get domain info
$domainInfo = Get-DomainInfo
Write-Host "`n[+] Domain: $($domainInfo.Domain)"
Write-Host "[+] Base DN: $DomainDN`n"

# Enumerate templates
$templates = Invoke-TemplateEnumeration -BaseDN $DomainDN

if ($templates.Count -eq 0) {
    Write-Host "[-] No test templates found. Run Create-VulnerableCertTemplates.ps1 first."
    exit 1
}

# Analyze each template
Write-Host "`n[*] ANALYZING TEMPLATES`n" -ForegroundColor Cyan

$vulnerabilityMatrix = @()

foreach ($template in $templates) {
    Write-Host "Analyzing: $($template.Name)"
    
    $vuln = Test-TemplateVulnerability -Template $template
    $acls = Get-TemplateACLs -Template $template
    
    $vulnerabilityMatrix += $vuln
    
    # Display results
    if ($vuln.Vulnerabilities.Count -gt 0) {
        Write-Host "  [!] Vulnerabilities: $($vuln.Vulnerabilities -join ', ')" -ForegroundColor Red
    } else {
        Write-Host "  [✓] No known vulnerabilities" -ForegroundColor Green
    }
    
    # Show details
    foreach ($detail in $vuln.Details) {
        Write-Host "      - $detail"
    }
    
    Write-Host ""
}

# Summary
Write-Host "`n[*] VULNERABILITY SUMMARY`n" -ForegroundColor Cyan

$escCounts = @{
    ESC1 = 0
    ESC2 = 0
    ESC3 = 0
    ESC4 = 0
    ESC6 = 0
}

foreach ($vuln in $vulnerabilityMatrix) {
    foreach ($v in $vuln.Vulnerabilities) {
        foreach ($key in $escCounts.Keys) {
            if ($v -like "*$key*") {
                $escCounts[$key]++
                break
            }
        }
    }
}

Write-Host "ESC1 (Overly Permissive Enrollment): $($escCounts.ESC1) templates"
Write-Host "ESC2 (Enrollment Agent):              $($escCounts.ESC2) templates"
Write-Host "ESC3 (Agent + App Policy):            $($escCounts.ESC3) templates"
Write-Host "ESC4 (Template Modification):         $($escCounts.ESC4) templates"
Write-Host "ESC6 (Forced SAN):                    $($escCounts.ESC6) templates"
Write-Host ""

# CA Flags
Get-CAEditFlags

# Optional: Exploitation testing
if ($TestExploitation) {
    Write-Host "`n[*] EXPLOITATION TESTING`n" -ForegroundColor Yellow
    
    foreach ($template in $templates) {
        $vuln = Test-TemplateVulnerability -Template $template
        
        if ($vuln.Vulnerabilities.Count -gt 0) {
            Write-Host "Template: $($template.Name)"
            Invoke-ExploitationTest -Template $template
        }
    }
}

# Optional: Generate report
if ($GenerateReport) {
    $reportPath = ".\ESC-Audit-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').md"
    Generate-AuditReport -Templates $templates -OutputPath $reportPath
}

Write-Host @"
╔════════════════════════════════════════════════════════════════════════════╗
║                           AUDIT COMPLETE                                   ║
╚════════════════════════════════════════════════════════════════════════════╝

NEXT STEPS:

1. For detailed vulnerability information:
   - Review: ESC-VULNERABILITIES-DOCUMENTATION.md
   - Review: ESC-QUICK-START-GUIDE.md

2. To test exploitation:
   - Run script with -TestExploitation flag
   - Download Certify.exe or Certipy for advanced testing

3. To harden:
   - Review vulnerable template ACLs
   - Restrict enrollment to specific groups
   - Disable SAN supply on production templates
   - Review CA registry flags

"@ -ForegroundColor Cyan
