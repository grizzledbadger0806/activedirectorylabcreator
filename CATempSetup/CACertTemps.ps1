$ErrorActionPreference="Stop"
Import-Module ActiveDirectory
if (-not (Get-PSDrive AD -ErrorAction SilentlyContinue)) {
    New-PSDrive -Name AD -PSProvider ActiveDirectory -Root "" | Out-Null
}
##Detect DC
$dc = (Get-ADDomainController -Discover -Service ADWS | Select-Object -ExpandProperty HostName -First 1)
$config = (Get-ADRootDSE -Server $dc).configurationNamingContext
$tplBase = "CN=Certificate Templates,CN=Public Key Services,CN=Services,$config"
##Reliable CA detection
function Get-CAName {
    $cas = certutil -config - -ping 2>$null
    foreach($line in $cas){
        if($line -match "\\"){
            return $line.Trim()
        }
    }
}
$CA = Get-CAName
if(!$CA){
    Write-Host "ERROR: Could not detect CA"
    exit
}
Write-Host "Detected CA:" $CA
function PublishTemplate($name){
    Start-Sleep 2
    certutil -config "$CA" -setcatemplates +$name | Out-Null
    Write-Host "[+] Published $name"
}
function CreateTemplate($name,$attributes){
    $dn="CN=$name,$tplBase"
    if(Get-ADObject -LDAPFilter "(cn=$name)" -SearchBase $tplBase -ErrorAction SilentlyContinue){
        Write-Host "[!] Template already exists: $name"
        return
    }
    $base=@{
        displayName=$name
        revision=100
        "msPKI-Template-Schema-Version"=1
        "msPKI-Template-Minor-Revision"=1
        pKIDefaultKeySpec=1
        "msPKI-Private-Key-Flag"=16
        flags=66106
    }
    $merged = $base + $attributes
    New-ADObject `
        -Server $dc `
        -Name $name `
        -Type pKICertificateTemplate `
        -Path $tplBase `
        -OtherAttributes $merged
    Write-Host "[+] Created $name"
    PublishTemplate $name
}
function AddDangerousACL($name){
    $dn="CN=$name,$tplBase"
    $acl = Get-Acl ("AD:\"+$dn)
    $users = New-Object System.Security.Principal.NTAccount("Domain Users")
    $rights = [System.DirectoryServices.ActiveDirectoryRights]"GenericAll"
    $rule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
        $users,
        $rights,
        "Allow"
    )
    $acl.AddAccessRule($rule)
    Set-Acl ("AD:\"+$dn) $acl
    Write-Host "[!] Added vulnerable ACL to $name"
}
function EnableAutoenroll($name){
    $dn="CN=$name,$tplBase"
    $acl = Get-Acl ("AD:\"+$dn)
    
    # Autoenroll GUID
    $enrollGUID = [System.Guid]"0e10c968-78fb-11d2-90d4-00c04f79dc61"
    
    # Add to Authenticated Users
    $authUsers = New-Object System.Security.Principal.NTAccount("Authenticated Users")
    $rule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
        $authUsers,
        [System.DirectoryServices.ActiveDirectoryRights]"ExtendedRight",
        "Allow",
        $enrollGUID
    )
    $acl.AddAccessRule($rule)
    Set-Acl ("AD:\"+$dn) $acl
    Write-Host "[+] Enabled autoenroll on $name"
}
Write-Host ""
Write-Host "==== Creating Secure Templates ===="
Write-Host ""
CreateTemplate "SecureUserAuth" @{
"pKIExtendedKeyUsage"="1.3.6.1.5.5.7.3.2"
}
CreateTemplate "SecureWebServer" @{
"pKIExtendedKeyUsage"="1.3.6.1.5.5.7.3.1"
}
CreateTemplate "SecureSmartCard" @{
"pKIExtendedKeyUsage"="1.3.6.1.4.1.311.20.2.2"
}
CreateTemplate "SecureIPSEC" @{
"pKIExtendedKeyUsage"="1.3.6.1.5.5.7.3.5"
}
CreateTemplate "SecureCodeSigning" @{
"pKIExtendedKeyUsage"="1.3.6.1.5.5.7.3.3"
}
CreateTemplate "SecureEmail" @{
"pKIExtendedKeyUsage"="1.3.6.1.5.5.7.3.4"
}
Write-Host ""
Write-Host "==== Creating Vulnerable ESC Templates ===="
Write-Host ""
CreateTemplate "ESC1-Lab" @{
"msPKI-Certificate-Name-Flag"=1
"pKIExtendedKeyUsage"="1.3.6.1.5.5.7.3.2"
}
CreateTemplate "ESC2-Lab" @{
"pKIExtendedKeyUsage"="2.5.29.37.0"
}
CreateTemplate "ESC3-Lab" @{
"pKIExtendedKeyUsage"="1.3.6.1.4.1.311.20.2.1"
"msPKI-RA-Signature"=0
}
CreateTemplate "ESC4-Lab" @{
"pKIExtendedKeyUsage"="1.3.6.1.5.5.7.3.2"
}
AddDangerousACL "ESC4-Lab"
CreateTemplate "ESC5-Lab" @{
"pKIExtendedKeyUsage"="1.3.6.1.5.2.3.4"
}
CreateTemplate "ESC6-Lab" @{
"pKIExtendedKeyUsage"="2.5.29.37.0"
"msPKI-Certificate-Name-Flag"=1
}
CreateTemplate "ESC7-Lab" @{
"msPKI-Enrollment-Flag"=0
}
CreateTemplate "ESC8-Lab" @{}
Write-Host ""
Write-Host "==== Enabling Autoenroll ===="
Write-Host ""
EnableAutoenroll "ESC1-Lab"
EnableAutoenroll "ESC2-Lab"
EnableAutoenroll "ESC3-Lab"
EnableAutoenroll "ESC4-Lab"
EnableAutoenroll "ESC6-Lab"
Write-Host ""
Write-Host "======================================"
Write-Host " ADCS Lab Templates Created"
Write-Host " Secure Templates: 6"
Write-Host " Vulnerable Templates: 8"
Write-Host " Autoenroll: Enabled"
Write-Host "======================================"
##Enable SAN abuse needed for ESC1/ESC6
certutil -setreg policy\EditFlags +EDITF_ATTRIBUTESUBJECTALTNAME2 | Out-Null
Restart-Service certsvc
certutil -config "$CA" -catemplates