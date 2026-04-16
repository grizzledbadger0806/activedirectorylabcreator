$ErrorActionPreference="Continue"
Import-Module ActiveDirectory

$tplBase = "CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,DC=broken,DC=badger,DC=local"

$toDelete = @(
    "ESC1-Lab","ESC2-Lab","ESC3-Lab","ESC4-Lab","ESC5-Lab","ESC6-Lab","ESC7-Lab","ESC8-Lab",
    "SecureUserAuth","SecureWebServer","SecureSmartCard","SecureIPSEC","SecureCodeSigning","SecureEmail"
)

Write-Host "Deleting bad templates..." -ForegroundColor Yellow
Write-Host ""

foreach($name in $toDelete) {
    try {
        Remove-ADObject -Identity "CN=$name,$tplBase" -Confirm:$false -ErrorAction Stop
        Write-Host "[-] Deleted $name" -ForegroundColor Green
    } catch {
        Write-Host "[!] Could not delete $name : $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Done. Now run CACertTemps-FIXED.ps1" -ForegroundColor Cyan
