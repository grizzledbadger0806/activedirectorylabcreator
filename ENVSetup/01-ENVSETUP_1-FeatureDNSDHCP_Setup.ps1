#############################################
##BROKEN.BADGER LAB
##DOMAIN CONTROLLER + DHCP/DNS SETUP (2-PHASE)
#############################################
##---------- VARIABLES ----------
$domain    = "broken.badger.local"
$netbios   = "BROKEN"
$dcIP      = "10.10.10.5"
##Scopes (edit routers as needed)
$scopes = @(
    @{ Name="Workstations"; Network="10.10.10.0"; Mask="255.255.255.0"; Start="10.10.10.10"; End="10.10.10.250"; Router="10.10.10.1" },
    @{ Name="Servers";      Network="10.10.20.0"; Mask="255.255.255.0"; Start="10.10.20.10"; End="10.10.20.250"; Router="10.10.20.1" },
    @{ Name="Printers";     Network="10.10.30.0"; Mask="255.255.255.0"; Start="10.10.30.10"; End="10.10.30.200"; Router="10.10.30.1" },
    @{ Name="Phones";       Network="10.10.40.0"; Mask="255.255.255.0"; Start="10.10.40.10"; End="10.10.40.200"; Router="10.10.40.1" },
    @{ Name="LinuxServers"; Network="10.10.50.0"; Mask="255.255.255.0"; Start="10.10.50.10"; End="10.10.50.200"; Router="10.10.50.1" }
)
##---------- HELPERS ----------
function Test-IsDomainController {
    try {
        $null = Get-Item "HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters" -ErrorAction Stop
        return $true
    } catch { return $false }
}
function Wait-ForAD {
    Import-Module ActiveDirectory -ErrorAction SilentlyContinue
    $deadline = (Get-Date).AddMinutes(10)
    while ((Get-Date) -lt $deadline) {
        try {
            Get-ADDomain -ErrorAction Stop | Out-Null
            return $true
        } catch {
            Start-Sleep -Seconds 10
        }
    }
    throw "AD did not become available within timeout."
}
##---------- PHASE 2 SCRIPT CONTENT ----------
$phase2Path = "C:\LabSetup-Phase2.ps1"
$phase2 = @"
`$ErrorActionPreference = 'Stop'
`$domain = '$domain'
`$dcIP   = '$dcIP'
`$hostname = `$env:COMPUTERNAME
`$fqdn = "`$hostname.`$domain"
Import-Module DhcpServer
Import-Module DnsServer
Import-Module ActiveDirectory
##Wait for AD to be online
`$deadline = (Get-Date).AddMinutes(10)
while ((Get-Date) -lt `$deadline) {
    try { Get-ADDomain -ErrorAction Stop | Out-Null; break } catch { Start-Sleep 10 }
}
##Ensure DHCP service is running
Start-Service DHCPServer -ErrorAction SilentlyContinue
##Authorize DHCP in AD (safe if already authorized)
try {
    Add-DhcpServerInDC -DnsName `$fqdn -IPAddress `$dcIP -ErrorAction Stop
} catch {
    ##If it's already authorized, ignore. Otherwise rethrow.
    if (`$_.Exception.Message -notmatch "exists|already") { throw }
}
##Create scopes + per-scope options
`$scopes = @(
$(($scopes | ForEach-Object {
    "    @{ Name='$($_.Name)'; Network='$($_.Network)'; Mask='$($_.Mask)'; Start='$($_.Start)'; End='$($_.End)'; Router='$($_.Router)' }"
}) -join ",`r`n")
)
foreach (`$s in `$scopes) {
    `$scopeId = `$s.Network
    ##Create scope if missing
    if (-not (Get-DhcpServerv4Scope -ScopeId `$scopeId -ErrorAction SilentlyContinue)) {
        Add-DhcpServerv4Scope -Name `$s.Name -StartRange `$s.Start -EndRange `$s.End -SubnetMask `$s.Mask -State Active
    }
    ##Set scope options
    Set-DhcpServerv4OptionValue -ScopeId `$scopeId -DnsServer `$dcIP -DnsDomain `$domain -Router `$s.Router
}
##Enable secure dynamic updates on the AD-integrated zone (if present)
try {
    Set-DnsServerPrimaryZone -Name `$domain -DynamicUpdate Secure -ErrorAction Stop
} catch {
    ##If zone is AD-integrated already, this may fail or be unnecessary on some builds
}
##Cleanup the scheduled task (run-once)
schtasks /Delete /TN "LabSetupPhase2" /F | Out-Null
"@
##---------- PHASE 1 ----------
$ErrorActionPreference = "Stop"
Write-Host "=== Phase 1: Installing roles/features ==="
Install-WindowsFeature `
    AD-Domain-Services, DNS, DHCP, GPMC, RSAT-AD-PowerShell, RSAT-DNS-Server, RSAT-DHCP, RSAT-AD-Tools `
    -IncludeManagementTools
##If not yet a DC, promote and reboot into Phase 2
if (-not (Test-IsDomainController)) {
    Write-Host "=== Writing Phase 2 script to $phase2Path ==="
    Set-Content -Path $phase2Path -Value $phase2 -Encoding UTF8
    Write-Host "=== Scheduling Phase 2 to run once at startup ==="
    schtasks /Create /TN "LabSetupPhase2" /SC ONSTART /RL HIGHEST /F `
        /TR "PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File `"$phase2Path`""
    Write-Host "=== Promoting to Domain Controller (this will reboot) ==="
    Install-ADDSForest `
        -DomainName $domain `
        -DomainNetbiosName $netbios `
        -InstallDNS `
        -Force
    ##If Install-ADDSForest doesn't auto-reboot for some reason:
    Restart-Computer -Force
}
else {
    Write-Host "This machine is already a Domain Controller. Run Phase 2 tasks directly:"
    Write-Host "PowerShell.exe -ExecutionPolicy Bypass -File `"$phase2Path`""
}