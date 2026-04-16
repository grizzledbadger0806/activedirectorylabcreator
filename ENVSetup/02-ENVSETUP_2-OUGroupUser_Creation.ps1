<#
ENVSETUP_2-CORRECTED.ps1 — Complete Lab Environment Builder with Hierarchical Managers
Creates realistic corporate AD infrastructure:
- Company: "The Bad Badger"
- 5237 Users with Description=Title, Office locations, Contractors
- HIERARCHICAL managers (CEO → C-Suite → VPs → Directors → Managers → Staff)
- 397 realistic security and distribution groups
- 630+ computers (workstations, servers)
- Optional DNS and DHCP
- Addresses, cities, states, and countries per office location
#>

$ErrorActionPreference = "Stop"
Import-Module ActiveDirectory
Import-Module DnsServer   -ErrorAction SilentlyContinue
Import-Module DhcpServer  -ErrorAction SilentlyContinue
Import-Module GroupPolicy -ErrorAction SilentlyContinue

##--------------------------
##DISCOVER DOMAIN CONTEXT
##--------------------------
$adDomain = Get-ADDomain
$domain   = $adDomain.DNSRoot
$base     = $adDomain.DistinguishedName
$dcObj = Get-ADDomainController -Discover
$script:DC = [string]$dcObj.HostName
if ([string]::IsNullOrWhiteSpace($script:DC)) { $script:DC = [string]$dcObj.Name }
Write-Host "Using Domain: $domain"
Write-Host "Base DN:      $base"
Write-Host "DC:           $script:DC"

##--------------------------
##CONFIG
##--------------------------
$userCount  = 5237
$companyName = "The Bad Badger"
$credOut    = "C:\LabUsers.csv"
$DoDNS  = $true
$DoDHCP = $true
$dnsZone = $domain

$nets = @{
  Workstations = @{ ScopeId = "10.10.10.0"; Prefix = "10.10.10."; Start=10; End=250 }
  Servers      = @{ ScopeId = "10.10.20.0"; Prefix = "10.10.20."; Start=10; End=250 }
}

$winServerProfiles = @(
  @{ Prefix = "WSRVUD";  Count = 18 },
  @{ Prefix = "WSRVPRD"; Count = 37 },
  @{ Prefix = "WSRVTST"; Count = 12 }
)

$ouNames = @("CorpUsers","CorpGroups","Workstations","Servers","ServiceAccounts","Finance","HR","Engineering","Legal","Executive","CIRT","Orphaned","Print","NewHire")

##--------------------------
##39 US OFFICE LOCATIONS WITH ADDRESSES
##--------------------------
$offices = @{
    "New York, NY"        = @{ Address = "350 5th Avenue Suite 7500"; City = "New York"; State = "NY"; PostalCode = "10118"; Country = "US" }
    "San Francisco, CA"   = @{ Address = "555 Market Street Suite 3000"; City = "San Francisco"; State = "CA"; PostalCode = "94105"; Country = "US" }
    "Chicago, IL"         = @{ Address = "300 North LaSalle Street Suite 4000"; City = "Chicago"; State = "IL"; PostalCode = "60654"; Country = "US" }
    "Dallas, TX"          = @{ Address = "2100 Ross Avenue Suite 3000"; City = "Dallas"; State = "TX"; PostalCode = "75201"; Country = "US" }
    "Atlanta, GA"         = @{ Address = "191 Peachtree Street NE Suite 3500"; City = "Atlanta"; State = "GA"; PostalCode = "30303"; Country = "US" }
    "Denver, CO"          = @{ Address = "1700 Lincoln Street Suite 2200"; City = "Denver"; State = "CO"; PostalCode = "80203"; Country = "US" }
    "Seattle, WA"         = @{ Address = "1111 Third Avenue Suite 4000"; City = "Seattle"; State = "WA"; PostalCode = "98101"; Country = "US" }
    "Boston, MA"          = @{ Address = "100 Federal Street Suite 3500"; City = "Boston"; State = "MA"; PostalCode = "02110"; Country = "US" }
    "Los Angeles, CA"     = @{ Address = "2049 Century Park East Suite 3200"; City = "Los Angeles"; State = "CA"; PostalCode = "90067"; Country = "US" }
    "Phoenix, AZ"         = @{ Address = "2300 North Central Avenue Suite 1800"; City = "Phoenix"; State = "AZ"; PostalCode = "85004"; Country = "US" }
    "Miami, FL"           = @{ Address = "1111 Brickell Avenue Suite 2500"; City = "Miami"; State = "FL"; PostalCode = "33131"; Country = "US" }
    "Washington, DC"      = @{ Address = "1101 Fifteenth Street NW Suite 2000"; City = "Washington"; State = "DC"; PostalCode = "20005"; Country = "US" }
    "Philadelphia, PA"    = @{ Address = "1701 Market Street Suite 2100"; City = "Philadelphia"; State = "PA"; PostalCode = "19103"; Country = "US" }
    "Houston, TX"         = @{ Address = "713 Louisiana Street Suite 3600"; City = "Houston"; State = "TX"; PostalCode = "77002"; Country = "US" }
    "Detroit, MI"         = @{ Address = "100 Renaissance Center Suite 3400"; City = "Detroit"; State = "MI"; PostalCode = "48243"; Country = "US" }
    "Minneapolis, MN"     = @{ Address = "90 South Seventh Street Suite 4000"; City = "Minneapolis"; State = "MN"; PostalCode = "55402"; Country = "US" }
    "Portland, OR"        = @{ Address = "903 SW Yamhill Street Suite 1800"; City = "Portland"; State = "OR"; PostalCode = "97204"; Country = "US" }
    "Austin, TX"          = @{ Address = "701 Brazos Street Suite 3100"; City = "Austin"; State = "TX"; PostalCode = "78701"; Country = "US" }
    "Nashville, TN"       = @{ Address = "414 Union Street Suite 3500"; City = "Nashville"; State = "TN"; PostalCode = "37219"; Country = "US" }
    "Memphis, TN"         = @{ Address = "100 North Main Street Suite 2700"; City = "Memphis"; State = "TN"; PostalCode = "38103"; Country = "US" }
    "Louisville, KY"      = @{ Address = "401 South Fourth Avenue Suite 3000"; City = "Louisville"; State = "KY"; PostalCode = "40202"; Country = "US" }
    "New Orleans, LA"     = @{ Address = "701 Poydras Street Suite 2500"; City = "New Orleans"; State = "LA"; PostalCode = "70139"; Country = "US" }
    "Sacramento, CA"      = @{ Address = "500 Capitol Mall Suite 3000"; City = "Sacramento"; State = "CA"; PostalCode = "95814"; Country = "US" }
    "Las Vegas, NV"       = @{ Address = "3900 Paradise Road Suite 2000"; City = "Las Vegas"; State = "NV"; PostalCode = "89169"; Country = "US" }
    "Salt Lake City, UT"  = @{ Address = "111 South Main Street Suite 2200"; City = "Salt Lake City"; State = "UT"; PostalCode = "84101"; Country = "US" }
    "Pittsburgh, PA"      = @{ Address = "600 Grant Street Suite 3000"; City = "Pittsburgh"; State = "PA"; PostalCode = "15219"; Country = "US" }
    "Cleveland, OH"       = @{ Address = "1111 Chester Avenue Suite 2300"; City = "Cleveland"; State = "OH"; PostalCode = "44114"; Country = "US" }
    "Columbus, OH"        = @{ Address = "100 South Third Street Suite 2000"; City = "Columbus"; State = "OH"; PostalCode = "43215"; Country = "US" }
    "Indianapolis, IN"    = @{ Address = "111 Monument Circle Suite 4000"; City = "Indianapolis"; State = "IN"; PostalCode = "46204"; Country = "US" }
    "Milwaukee, WI"       = @{ Address = "411 East Wisconsin Avenue Suite 1600"; City = "Milwaukee"; State = "WI"; PostalCode = "53202"; Country = "US" }
    "Kansas City, MO"     = @{ Address = "1000 Main Street Suite 2900"; City = "Kansas City"; State = "MO"; PostalCode = "64105"; Country = "US" }
    "St. Louis, MO"       = @{ Address = "100 South Fourth Street Suite 3000"; City = "St. Louis"; State = "MO"; PostalCode = "63102"; Country = "US" }
    "Charlotte, NC"       = @{ Address = "301 South College Street Suite 3000"; City = "Charlotte"; State = "NC"; PostalCode = "28202"; Country = "US" }
    "Raleigh, NC"         = @{ Address = "421 Fayetteville Street Suite 2500"; City = "Raleigh"; State = "NC"; PostalCode = "27601"; Country = "US" }
    "Richmond, VA"        = @{ Address = "707 Main Street Suite 3000"; City = "Richmond"; State = "VA"; PostalCode = "23219"; Country = "US" }
    "Baltimore, MD"       = @{ Address = "100 Light Street Suite 3000"; City = "Baltimore"; State = "MD"; PostalCode = "21202"; Country = "US" }
    "Hartford, CT"        = @{ Address = "One State Street Suite 2000"; City = "Hartford"; State = "CT"; PostalCode = "06103"; Country = "US" }
    "Buffalo, NY"         = @{ Address = "One Main Place Suite 1600"; City = "Buffalo"; State = "NY"; PostalCode = "14202"; Country = "US" }
    "Providence, RI"      = @{ Address = "148 Orange Street Suite 2200"; City = "Providence"; State = "RI"; PostalCode = "02903"; Country = "US" }
}

$wfhLocations = @(
    "Remote - California","Remote - Texas","Remote - Florida","Remote - New York","Remote - Washington","Remote - Colorado","Remote - Massachusetts","Remote - Pennsylvania","Remote - Arizona","Remote - Georgia",
    "Remote - North Carolina","Remote - Illinois","Remote - Ohio","Remote - Michigan","Remote - Tennessee","Remote - Virginia","Remote - Oregon","Remote - Minnesota","Remote - Missouri","Remote - Nevada"
)

$wfhStates = @{
    "Remote - California"      = @{ State = "CA"; Country = "US" }
    "Remote - Texas"           = @{ State = "TX"; Country = "US" }
    "Remote - Florida"         = @{ State = "FL"; Country = "US" }
    "Remote - New York"        = @{ State = "NY"; Country = "US" }
    "Remote - Washington"      = @{ State = "WA"; Country = "US" }
    "Remote - Colorado"        = @{ State = "CO"; Country = "US" }
    "Remote - Massachusetts"   = @{ State = "MA"; Country = "US" }
    "Remote - Pennsylvania"    = @{ State = "PA"; Country = "US" }
    "Remote - Arizona"         = @{ State = "AZ"; Country = "US" }
    "Remote - Georgia"         = @{ State = "GA"; Country = "US" }
    "Remote - North Carolina"  = @{ State = "NC"; Country = "US" }
    "Remote - Illinois"        = @{ State = "IL"; Country = "US" }
    "Remote - Ohio"            = @{ State = "OH"; Country = "US" }
    "Remote - Michigan"        = @{ State = "MI"; Country = "US" }
    "Remote - Tennessee"       = @{ State = "TN"; Country = "US" }
    "Remote - Virginia"        = @{ State = "VA"; Country = "US" }
    "Remote - Oregon"          = @{ State = "OR"; Country = "US" }
    "Remote - Minnesota"       = @{ State = "MN"; Country = "US" }
    "Remote - Missouri"        = @{ State = "MO"; Country = "US" }
    "Remote - Nevada"          = @{ State = "NV"; Country = "US" }
}

$contractingFirms = @(
    @{ Name = "AccelTech Solutions"; Departments = @("Engineering", "IT", "Architecture", "Development") },
    @{ Name = "GlobalStaff Partners"; Departments = @("Operations", "Support", "Administration", "Finance") },
    @{ Name = "TechNova Outsourcing"; Departments = @("QA", "Testing", "Support", "Analysts") },
    @{ Name = "InGen Genetic Research"; Departments = @("Engineering", "Project Management", "Consulting", "Design") },
    @{ Name = "CyberGuard Security"; Departments = @("Security", "Compliance", "Risk Management", "Auditing") },
    @{ Name = "DataMinds Analytics"; Departments = @("Data Science", "Analytics", "Business Intelligence", "Consulting") }
)

##Title hierarchy levels
$ceoTitles = @("CEO")
$cSuiteTitles = @("CFO","COO","CTO","CIO","CSO","CMO","CHRO")
$vpTitles = @("VP of Finance","VP of Operations","VP of Technology","VP of Sales")
$directorTitles = @("Director of Finance","Director of Operations","Director of Technology","Director of Sales")
$managerTitles = @("Manager of Finance","Manager of Operations","Manager of Technology","Manager of Sales","Manager","Supervisor","Project Manager","Product Manager","Social Media Manager","Risk Manager","Innovation Manager","Facilities Manager")

##--------------------------
##SAFE WRAPPERS
##--------------------------
function Get-ADObjectSafe {
    param([Parameter(Mandatory)][string]$DN)
    try { Get-ADObject -Server $script:DC -Identity $DN -ErrorAction Stop } catch { $null }
}

function Get-ADUserSafe {
    param([Parameter(Mandatory)][string]$Sam)
    try { Get-ADUser -Server $script:DC -Identity $Sam -ErrorAction Stop }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] { $null }
}

function Get-ADComputerSafe {
    param([Parameter(Mandatory)][string]$Name)
    try { Get-ADComputer -Server $script:DC -Identity $Name -ErrorAction Stop }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] { $null }
}

##--------------------------
##HELPERS
##--------------------------
function Ensure-OU {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$BaseDn)
    $cnDn = "CN=$Name,$BaseDn"
    if (Get-ADObjectSafe -DN $cnDn) { return $cnDn }
    $ouDn = "OU=$Name,$BaseDn"
    if (Get-ADObjectSafe -DN $ouDn) { return $ouDn }
    New-ADOrganizationalUnit -Server $script:DC -Name $Name -Path $BaseDn | Out-Null
    return $ouDn
}

function Ensure-Group {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Path, [switch]$MailEnabled)
    $existing = Get-ADGroup -Server $script:DC -LDAPFilter "(sAMAccountName=$Name)" -SearchBase $Path -ErrorAction SilentlyContinue
    if (-not $existing) {
        if ($MailEnabled) {
            New-ADGroup -Server $script:DC -Name $Name -SamAccountName $Name -GroupScope Global -GroupCategory Distribution -Path $Path | Out-Null
        } else {
            New-ADGroup -Server $script:DC -Name $Name -SamAccountName $Name -GroupScope Global -GroupCategory Security -Path $Path | Out-Null
        }
    }
}

function New-ComplexPassword {
    param([int]$Length = 24, [switch]$NoAmbiguous)
    $lower = "abcdefghijkmnopqrstuvwxyz"
    $upper = "ABCDEFGHJKLMNPQRSTUVWXYZ"
    $digits = "23456789"
    $special = "!@#$%^&*()-_=+[]{}:,.?"
    if (-not $NoAmbiguous) { $lower = "abcdefghijklmnopqrstuvwxyz"; $upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"; $digits = "0123456789" }
    if ($Length -lt 14) { $Length = 14 }
    $chars = @($lower[(Get-Random -Maximum $lower.Length)], $upper[(Get-Random -Maximum $upper.Length)], $digits[(Get-Random -Maximum $digits.Length)], $special[(Get-Random -Maximum $special.Length)])
    $all = $lower + $upper + $digits + $special
    1..($Length - 4) | ForEach-Object { $chars += $all[(Get-Random -Maximum $all.Length)] }
    -join ($chars | Sort-Object { Get-Random })
}

function New-RandomMac {
    ("00-15-5D-{0:X2}-{1:X2}-{2:X2}" -f (Get-Random -Minimum 0 -Maximum 256), (Get-Random -Minimum 0 -Maximum 256), (Get-Random -Minimum 0 -Maximum 256))
}

function New-RandomAddress {
    param([Parameter(Mandatory)][string]$State)
    $streetNumbers = @(100, 200, 300, 400, 500, 600, 700, 800, 900, 1000, 1100, 1200, 1300, 1400, 1500, 1600, 1700, 1800, 1900, 2000, 2100, 2200, 2300, 2400, 2500)
    $streetNames = @("Oak Street", "Maple Avenue", "Elm Court", "Pine Drive", "Birch Lane", "Cedar Boulevard", "Walnut Road", "Oak Park Drive", "Forest Avenue", "Garden Lane", "Main Street", "Park Avenue", "Spring Street", "Valley Drive", "Hill Street", "Riverside Drive", "Sunset Boulevard", "Broadway", "Sunset Lane", "Highland Drive")
    $streetSuffixes = @("Suite 100", "Suite 200", "Suite 300", "Floor 2", "Floor 3", "Building A", "Building B", "#200", "#300", "#400")
    
    $number = $streetNumbers | Get-Random
    $name = $streetNames | Get-Random
    $suffix = $streetSuffixes | Get-Random
    
    return "$number $name $suffix"
}

function New-RandomCity {
    param([Parameter(Mandatory)][string]$State)
    $citiesByState = @{
        "CA" = @("San Francisco", "Los Angeles", "San Diego", "Sacramento", "San Jose", "Oakland", "Long Beach", "Fresno", "Bakersfield", "Anaheim")
        "TX" = @("Houston", "Dallas", "Austin", "San Antonio", "Fort Worth", "Corpus Christi", "Plano", "Arlington", "Lubbock", "Amarillo")
        "FL" = @("Miami", "Tampa", "Orlando", "Jacksonville", "Fort Lauderdale", "Tallahassee", "West Palm Beach", "Gainesville", "Pensacola", "Daytona Beach")
        "NY" = @("New York", "Buffalo", "Rochester", "Yonkers", "Syracuse", "Albany", "New Rochelle", "Mount Vernon", "Schenectady", "Watertown")
        "WA" = @("Seattle", "Spokane", "Tacoma", "Bellevue", "Everett", "Renton", "Bremerton", "Kirkland", "Sammamish", "Redmond")
        "CO" = @("Denver", "Colorado Springs", "Aurora", "Fort Collins", "Lakewood", "Thornton", "Arvada", "Broomfield", "Pueblo", "Westminster")
        "MA" = @("Boston", "Worcester", "Springfield", "Cambridge", "Lowell", "Brockton", "New Bedford", "Quincy", "Somerville", "Waltham")
        "PA" = @("Philadelphia", "Pittsburgh", "Allentown", "Erie", "Reading", "Scranton", "Bethlehem", "Lancaster", "Altoona", "Harrisburg")
        "AZ" = @("Phoenix", "Mesa", "Chandler", "Scottsdale", "Glendale", "Gilbert", "Tempe", "Peoria", "Surprise", "Tucson")
        "GA" = @("Atlanta", "Augusta", "Savannah", "Columbus", "Macon", "Athens", "Sandy Springs", "Roswell", "Dunwoody", "Alpharetta")
        "NC" = @("Charlotte", "Raleigh", "Greensboro", "Durham", "Winston-Salem", "Fayetteville", "Cary", "Wilmington", "High Point", "Greenville")
        "IL" = @("Chicago", "Aurora", "Rockford", "Joliet", "Naperville", "Springfield", "Peoria", "Elgin", "Waukegan", "Cicero")
        "OH" = @("Cleveland", "Columbus", "Cincinnati", "Toledo", "Akron", "Dayton", "Parma", "Canton", "Youngstown", "Lorain")
        "MI" = @("Detroit", "Grand Rapids", "Warren", "Sterling Heights", "Lansing", "Ann Arbor", "Flint", "Dearborn", "Livonia", "Westland")
        "TN" = @("Nashville", "Memphis", "Knoxville", "Chattanooga", "Clarksville", "Murfreesboro", "Jackson", "Hendersonville", "Johnson City", "Cleveland")
        "VA" = @("Richmond", "Arlington", "Alexandria", "Virginia Beach", "Roanoke", "Blacksburg", "Falls Church", "Charlottesville", "Leesburg", "Winchester")
        "OR" = @("Portland", "Eugene", "Salem", "Gresham", "Hillsboro", "Beaverton", "Bend", "Medford", "Springfield", "Corvallis")
        "MN" = @("Minneapolis", "Saint Paul", "Rochester", "Duluth", "Bloomington", "Plymouth", "St. Cloud", "Mankato", "Minnetonka", "Eden Prairie")
        "MO" = @("Kansas City", "St. Louis", "Springfield", "Independence", "Columbia", "Lee's Summit", "Saint Peters", "O'Fallon", "Joplin", "Cape Girardeau")
        "NV" = @("Las Vegas", "Henderson", "Reno", "North Las Vegas", "Sparks", "Mesquite", "Pahrump", "Boulder City", "Fallon", "Ely")
    }
    
    if ($citiesByState.ContainsKey($State)) {
        return $citiesByState[$State] | Get-Random
    } else {
        return "Springfield"
    }
}

function Ensure-DnsARecord {
    param([string]$Zone,[string]$Name,[string]$IPv4)
    if (-not (Get-Module DnsServer -ListAvailable)) { return }
    $existing = Get-DnsServerResourceRecord -ZoneName $Zone -Name $Name -RRType "A" -ErrorAction SilentlyContinue
    if (-not $existing) { Add-DnsServerResourceRecordA -ZoneName $Zone -Name $Name -IPv4Address $IPv4 | Out-Null }
}

function Ensure-DhcpReservation {
    param([string]$ScopeId,[string]$IPv4,[string]$ClientId,[string]$Name)
    if (-not (Get-Module DhcpServer -ListAvailable)) { return }
    $existing = Get-DhcpServerv4Reservation -ScopeId $ScopeId -IPAddress $IPv4 -ErrorAction SilentlyContinue
    if (-not $existing) { Add-DhcpServerv4Reservation -ScopeId $ScopeId -IPAddress $IPv4 -ClientId $ClientId -Name $Name | Out-Null }
}

##--------------------------
##1) CREATE OUs
##--------------------------
foreach ($n in $ouNames) { Ensure-OU -Name $n -BaseDn $base | Out-Null }
$usersOuDn  = "OU=CorpUsers,$base"
$groupsOuDn = "OU=CorpGroups,$base"
$wsOuDn     = "OU=Workstations,$base"
$svOuDn     = "OU=Servers,$base"

##--------------------------
##2) GROUPS
##--------------------------
Write-Host "Creating 397 groups..."
$cifsShares = @("Finance","HR","Engineering","Legal","Executive","Operations","Sales","Marketing","IT","Security","Archive","Backup","Shared","Public","Templates","Reports","Compliance","Audit","Internal","External","Procurement","Vendor","Contracts","Projects","Development","Testing","Production","Staging","Database","Logs","Config","Scripts","Tools","Media","Documents")
foreach ($share in $cifsShares) { Ensure-Group -Name "SEC_CIFS_$share" -Path $groupsOuDn }

$appNames = @("Salesforce","ServiceNow","Jira","Confluence","GitHub","GitLab","Jenkins","Docker","Kubernetes","Terraform","Ansible","Puppet","Chef","ELK","Prometheus","Grafana","NewRelic","DataDog","Splunk","Elastic","SAP","Oracle","SQL_Server","PostgreSQL","MongoDB","Cassandra","Redis","RabbitMQ","Kafka","ActiveMQ","Office365","Exchange","Teams","Sharepoint","OneDrive","Box","Dropbox","AWS","Azure","GCP","Okta","Duo","LastPass","1Password","Vault","Slack","Zoom","Webex","Mattermost","Rocket")
foreach ($app in $appNames) { Ensure-Group -Name "SEC_APP_$app" -Path $groupsOuDn }

$dbNames = @("SQL_Prod_Read","SQL_Prod_Write","SQL_Prod_Admin","SQL_Dev_Read","SQL_Dev_Write","SQL_Dev_Admin","SQL_Test_Read","SQL_Test_Write","SQL_Test_Admin","Oracle_Prod_Read","Oracle_Prod_Write","Oracle_Prod_Admin","Oracle_Dev_Read","Oracle_Dev_Write","Oracle_Dev_Admin","Postgres_Prod_Read","Postgres_Prod_Write","Postgres_Prod_Admin","Postgres_Dev_Read","Postgres_Dev_Write","Postgres_Dev_Admin","MongoDB_Prod","MongoDB_Dev","Cassandra_Prod","Cassandra_Dev","Redis_Prod","Redis_Dev","InfluxDB")
foreach ($db in $dbNames) { Ensure-Group -Name "SEC_DB_$db" -Path $groupsOuDn }

$execResources = @("FinanceSystem","HRSystem","LegalSystem","BoardReports","ExecutiveDrive","StrategicPlan","Budget","Payroll","Contracts","CLevel","VPAccess","DirectorAccess","ManagerAccess","LeadershipPortal","ExecutiveEmail","BoardMeeting","SensitiveData","Compliance","Audit","Annual_Report","Strategic_Initiative","Executive_Dashboard")
foreach ($resource in $execResources) { Ensure-Group -Name "SEC_${resource}_EXEC" -Path $groupsOuDn }

$deptDists = @("Finance","Finance_Leadership","Finance_Analysts","Finance_Operations","Finance_Managers","HR","HR_Leadership","HR_Recruitment","HR_Operations","HR_Payroll","HR_Benefits","Engineering","Engineering_Leadership","Engineering_Backend","Engineering_Frontend","Engineering_DevOps","Engineering_QA","Sales","Sales_Leadership","Sales_EMEA","Sales_AMER","Sales_APAC","Sales_Enterprise","Sales_Mid","Sales_SMB","Marketing","Marketing_Leadership","Marketing_Content","Marketing_Digital","Marketing_Events","Marketing_Brand","Operations","Operations_Leadership","Operations_Logistics","Operations_Facilities","Operations_Procurement","IT","IT_Leadership","IT_Desktop","IT_Server","IT_Network","IT_Security","IT_Help","Legal","Legal_Leadership","Legal_Contracts","Legal_Compliance","Legal_Intellectual","Executive","Executive_Leadership","Board_Directors","All_Staff","All_Teams","Marketing_Partners","Sales_Partners","Tech_Partners","Vendor_Partners","Contractor_Partners","AllCompany","Marketing_List","Sales_List")
foreach ($dist in $deptDists) { Ensure-Group -Name "DIST_$dist" -Path $groupsOuDn -MailEnabled }

$collectionNames = @("AllUsers","AllEmployees","AllManagement","AllLeadership","AllTechnical","AllNonTechnical","FullTime","PartTime","Contractors","Temps","Interns","NewHires","Executives","Directors","Managers","Supervisors","Engineers","Architects","Analysts","Specialists","Administrators","Support","Sales","Marketing","Finance","HR","Legal","Operations","IT","Security","Development","Test")
foreach ($col in $collectionNames) { Ensure-Group -Name "COL_$col" -Path $groupsOuDn }

$teamNames = @("CloudMigration","DigitalTransformation","SecurityHardening","DataGovernance","MLPlatform","MobileApp","WebPortal","APIGateway","DataPipeline","Analytics","Dashboard","Reporting","DisasterRecovery","HighAvailability","Performance","Scalability","Monitoring","Automation","Integration","Migration","Consolidation","Modernization","Innovation","Research","Pilot")
foreach ($team in $teamNames) { Ensure-Group -Name "SEC_TEAM_$team" -Path $groupsOuDn }

$roleNames = @("Executives","Directors","Managers","Supervisors","TeamLeads","Architects","Engineers","SeniorEngineers","Developers","QA","DevOps","SysAdmin","DBAdmin","NetworkAdmin","SecurityAdmin","HelpDesk","Analysts","BusinessAnalysts","DataAnalysts","FinancialAnalysts","SecurityAnalysts","SalesAnalysts","Specialists","Coordinators","Administrators","Assistants","Support","Contractors","Consultants","Interns","Apprentices","Trainees","Partners","Vendors","Customers","Auditors","Compliance","Legal","Finance","HR","Executive")
foreach ($role in $roleNames) { Ensure-Group -Name "SEC_ROLE_$role" -Path $groupsOuDn }

$geoNames = @("AMER_North","AMER_Central","AMER_South","AMER_All","EMEA_North","EMEA_Central","EMEA_South","EMEA_All","APAC_Northeast","APAC_Southeast","APAC_South","APAC_All","HQ_Primary","Remote_All","Hybrid_All","OnSite_All","Satellite_Offices","Global")
foreach ($geo in $geoNames) { Ensure-Group -Name "SEC_GEO_$geo" -Path $groupsOuDn }

$deptNames = @("Finance","HR","Legal","Operations","IT","Engineering","Sales","Marketing","Executive","Board","Security","Compliance","Audit","Procurement","Facilities","Communications","Training","Research","Strategy","Admin")
foreach ($dept in $deptNames) { Ensure-Group -Name "SEC_DEPT_$dept" -Path $groupsOuDn }

$infraNames = @("Networks","Firewall","LoadBalancer","VPN","WAF","DDoS","DNS","DHCP","Datacenters","CloudServices","VirtualMachines","Containers","Kubernetes","Storage","Backup_Restore","DisasterRecovery","Monitoring","Logging","SIEM","SOAR")
foreach ($infra in $infraNames) { Ensure-Group -Name "SEC_INFRA_$infra" -Path $groupsOuDn }

$totalGroups = $cifsShares.Count + $appNames.Count + $dbNames.Count + $execResources.Count + $deptDists.Count + $collectionNames.Count + $teamNames.Count + $roleNames.Count + $geoNames.Count + $deptNames.Count + $infraNames.Count
Write-Host "Created $totalGroups groups"

##--------------------------
##3) USERS
##--------------------------
Write-Host "Creating $userCount users..."
"SamAccountName,UserPrincipalName,Password,Manager" | Out-File $credOut -Encoding utf8

$first = @("Peter","Bruce","Clark","Tony","Natasha","Barry","Diana","Logan","Steve","Wanda","Scott","Arthur","Selina","Jean","Ororo","Victor","Pamela","Aiden","Liam","Noah","Oliver","Elijah","James","William","Benjamin","Lucas","Henry","Harley","Theodore","Jack","Levi","Alexander","Jackson","Mateo","Daniel","Michael","Mason","Sebastian","Ethan","Owen","Samuel","Jacob","Asher","Avery","Wyatt","Carter","Julian","Grayson","Leo","Jayden","Gabriel","Isaac","Lincoln","Anthony","Hudson","Dylan","Ezra","Thomas","Charles","Christopher","Jaxon","Maverick","Josiah","Isaiah","Andrew","Elias","Joshua","Nathan","Caleb","Ryan","Adrian","Miles","Eli","Nolan","Christian","Aaron","Cameron","Ezekiel","Colton","Luca","Landon","Hunter","Jonathan","Santiago","Axel","Easton","Cooper","Jeremiah","Angel","Roman","Connor","Jameson","Robert","Greyson","Jordan","Ian","Carson","Jaxson","Leonardo","Nicholas","Dominic","Austin","Everett","Brooks","Xavier","Kai","Jose","Parker","Adam","Jace","Wesley","Kayden","Silas","Bennett","Declan","Waylon","Weston","Evan","Emmett","Micah","Ryder","Beau","Damien","Sawyer","Kingston","Jason","Brandon","Zane","Orion","Atlas","Phoenix","Bodhi","Caspian","Ronan","Kairo","Arlo","Soren","Knox","Ledger","Thane","Iker","Elio","Jasper","Lennox","Briar","Koa","Ash","River","Stone","Hugo","Otto","Remy","Clyde","Fletcher","Magnus","Alaric","Tobias","Callum","Reid","Vaughn","Wilder","Crew","Salem","Milo","Dario","Quincy","Rocco","Jett","Briggs","Zephyr","Nico","Lyle","Cormac","Indigo","Fox","Peregrine","Cairo","Onyx","Ridge","Basil","Kellen","Archer","Noel","Santino","Lucian","Vito","Marlon","Enzo","Talon","Rhett","Blaise","Jovan","Harlan","Iskander","Pax","Zion","Eero")

$last = @("Parker","Wayne","Kent","Stark","Romanoff","Allen","Prince","Howlett","Rogers","Maximoff","Lang","Curry","Kyle","Grey","Munroe","Stone","Isley","Quinn","Smith","Johnson","Williams","Brown","Jones","Garcia","Miller","Davis","Rodriguez","Martinez","Hernandez","Lopez","Gonzalez","Wilson","Anderson","Thomas","Taylor","Moore","Jackson","Martin","Lee","Perez","Thompson","White","Harris","Sanchez","Clark","Ramirez","Lewis","Robinson","Walker","Young","King","Wright","Scott","Torres","Nguyen","Hill","Flores","Green","Adams","Nelson","Baker","Hall","Rivera","Campbell","Mitchell","Carter","Roberts","Gomez","Phillips","Evans","Turner","Diaz","Cruz","Edwards","Collins","Reyes","Stewart","Morris","Morales","Murphy","Cook","Gutierrez","Ortiz","Morgan","Cooper","Peterson","Bailey","Reed","Kelly","Howard","Ramos","Kim","Cox","Ward","Richardson","Watson","Brooks","Chavez","Wood","James","Bennett","Gray","Mendoza","Ruiz","Hughes","Price","Alvarez","Castillo","Sanders","Patel","Myers","Long","Ross","Foster","Jimenez","Powell","Jenkins","Perry","Russell","Sullivan","Bell","Coleman","Butler","Henderson","Barnes","Gonzales","Fisher","Vasquez","Simmons","Romero","Jordan","Patterson","Alexander","Hamilton","Graham","Blackwood","Hawthorne","Whitaker","Montoya","Delgado","Archer","Donovan","Kensington","Navarro","Rutherford","Callahan","Bishop","Caldwell","Vaughn","Sterling","Montgomery","Quintero","Fitzgerald","Olsen","McAllister","Thornton","Redmond","Pacheco","Lockwood","Holloway","Wainwright","Prescott","Salazar","Moriarty","Trevino","Beaumont","Kincaid","Langston","Serrano","Alcott","Winslow","Marquez","Huxley","Fairchild","Boudreaux","Grimaldi","Corbett","Dunlap","Santiago","Everhart","Lombardi","Rivers","Pendleton","Ibarra","Stone","Zamora","Cavanaugh","Ortega","Valencia","Crowley","Nakamura","Bennings","Foxworth","Rinaldi","Hargreaves","Moreno","Tolliver","Sinclair","Devereaux","Kowalski","Petrov","Yamamoto","Ivanov","Khalil","Okafor","Mensah","Haddad","Farouk","Abdel","Rahman","El-Amin","Basri","Qureshi","Malik","Azizi")

$titles = @("CEO","CFO","COO","CTO","CIO","CSO","CMO","CHRO","VP of Finance","VP of Operations","VP of Technology","VP of Sales","Director of Finance","Director of Operations","Director of Technology","Director of Sales","Manager of Finance","Manager of Operations","Manager of Technology","Manager of Sales","Senior Analyst","Analyst","Specialist","Coordinator","Administrator","Engineer","Architect","Consultant","Technician","Support Specialist","Intern","Contractor","Temp","Assistant","Associate","Manager","Supervisor","Office Assistant","Executive Assistant","HR Specialist","Recruiter","Accountant","Financial Analyst","Marketing Specialist","Sales Representative","Customer Service Rep","IT Support","Network Engineer","Systems Administrator","Database Administrator","Security Analyst","Project Manager","Business Analyst","Product Manager","Graphic Designer","Content Creator","Social Media Manager","Data Scientist","Researcher","Legal Counsel","Compliance Officer","Facilities Manager","Executive Chef","Event Planner","Public Relations Specialist","Communications Coordinator","Training Specialist","Health and Safety Officer","Logistics Coordinator","Procurement Specialist","Quality Assurance Analyst","Risk Manager","Innovation Manager")

##Title mappings
$titleToSecRole = @{"CEO" = "SEC_ROLE_Executives";"CFO" = "SEC_ROLE_Executives";"COO" = "SEC_ROLE_Executives";"CTO" = "SEC_ROLE_Executives";"CIO" = "SEC_ROLE_Executives";"CSO" = "SEC_ROLE_Executives";"CMO" = "SEC_ROLE_Executives";"CHRO" = "SEC_ROLE_Executives";"VP of Finance" = "SEC_ROLE_Executives";"VP of Operations" = "SEC_ROLE_Executives";"VP of Technology" = "SEC_ROLE_Executives";"VP of Sales" = "SEC_ROLE_Executives";"Director of Finance" = "SEC_ROLE_Directors";"Director of Operations" = "SEC_ROLE_Directors";"Director of Technology" = "SEC_ROLE_Directors";"Director of Sales" = "SEC_ROLE_Directors";"Manager of Finance" = "SEC_ROLE_Managers";"Manager of Operations" = "SEC_ROLE_Managers";"Manager of Technology" = "SEC_ROLE_Managers";"Manager of Sales" = "SEC_ROLE_Managers";"Senior Analyst" = "SEC_ROLE_Analysts";"Analyst" = "SEC_ROLE_Analysts";"Specialist" = "SEC_ROLE_Specialists";"Coordinator" = "SEC_ROLE_Coordinators";"Administrator" = "SEC_ROLE_Administrators";"Engineer" = "SEC_ROLE_Engineers";"Architect" = "SEC_ROLE_Architects";"Consultant" = "SEC_ROLE_Consultants";"Technician" = "SEC_ROLE_Engineers";"Support Specialist" = "SEC_ROLE_Support";"Intern" = "SEC_ROLE_Interns";"Contractor" = "SEC_ROLE_Contractors";"Temp" = "SEC_ROLE_Trainees";"Assistant" = "SEC_ROLE_Coordinators";"Associate" = "SEC_ROLE_Specialists";"Manager" = "SEC_ROLE_Managers";"Supervisor" = "SEC_ROLE_Managers";"Office Assistant" = "SEC_ROLE_Support";"Executive Assistant" = "SEC_ROLE_Support";"HR Specialist" = "SEC_ROLE_Specialists";"Recruiter" = "SEC_ROLE_Specialists";"Accountant" = "SEC_ROLE_Analysts";"Financial Analyst" = "SEC_ROLE_Analysts";"Marketing Specialist" = "SEC_ROLE_Specialists";"Sales Representative" = "SEC_ROLE_Specialists";"Customer Service Rep" = "SEC_ROLE_Support";"IT Support" = "SEC_ROLE_Support";"Network Engineer" = "SEC_ROLE_Engineers";"Systems Administrator" = "SEC_ROLE_Administrators";"Database Administrator" = "SEC_ROLE_Administrators";"Security Analyst" = "SEC_ROLE_Analysts";"Project Manager" = "SEC_ROLE_Managers";"Business Analyst" = "SEC_ROLE_Analysts";"Product Manager" = "SEC_ROLE_Managers";"Graphic Designer" = "SEC_ROLE_Specialists";"Content Creator" = "SEC_ROLE_Specialists";"Social Media Manager" = "SEC_ROLE_Managers";"Data Scientist" = "SEC_ROLE_Analysts";"Researcher" = "SEC_ROLE_Analysts";"Legal Counsel" = "SEC_ROLE_Specialists";"Compliance Officer" = "SEC_ROLE_Administrators";"Facilities Manager" = "SEC_ROLE_Managers";"Executive Chef" = "SEC_ROLE_Specialists";"Event Planner" = "SEC_ROLE_Coordinators";"Public Relations Specialist" = "SEC_ROLE_Specialists";"Communications Coordinator" = "SEC_ROLE_Coordinators";"Training Specialist" = "SEC_ROLE_Specialists";"Health and Safety Officer" = "SEC_ROLE_Administrators";"Logistics Coordinator" = "SEC_ROLE_Coordinators";"Procurement Specialist" = "SEC_ROLE_Specialists";"Quality Assurance Analyst" = "SEC_ROLE_Analysts";"Risk Manager" = "SEC_ROLE_Managers";"Innovation Manager" = "SEC_ROLE_Managers"}

$titleToDept = @{"CEO" = "SEC_DEPT_Executive";"CFO" = "SEC_DEPT_Finance";"COO" = "SEC_DEPT_Operations";"CTO" = "SEC_DEPT_Engineering";"CIO" = "SEC_DEPT_IT";"CSO" = "SEC_DEPT_Security";"CMO" = "SEC_DEPT_Marketing";"CHRO" = "SEC_DEPT_HR";"VP of Finance" = "SEC_DEPT_Finance";"VP of Operations" = "SEC_DEPT_Operations";"VP of Technology" = "SEC_DEPT_IT";"VP of Sales" = "SEC_DEPT_Sales";"Director of Finance" = "SEC_DEPT_Finance";"Director of Operations" = "SEC_DEPT_Operations";"Director of Technology" = "SEC_DEPT_IT";"Director of Sales" = "SEC_DEPT_Sales";"Manager of Finance" = "SEC_DEPT_Finance";"Manager of Operations" = "SEC_DEPT_Operations";"Manager of Technology" = "SEC_DEPT_IT";"Manager of Sales" = "SEC_DEPT_Sales";"Senior Analyst" = "SEC_DEPT_IT";"Analyst" = "SEC_DEPT_IT";"Specialist" = "SEC_DEPT_Operations";"Coordinator" = "SEC_DEPT_HR";"Administrator" = "SEC_DEPT_IT";"Engineer" = "SEC_DEPT_Engineering";"Architect" = "SEC_DEPT_Engineering";"Consultant" = "SEC_DEPT_Operations";"Technician" = "SEC_DEPT_Engineering";"Support Specialist" = "SEC_DEPT_IT";"Intern" = "SEC_DEPT_HR";"Contractor" = "SEC_DEPT_Operations";"Temp" = "SEC_DEPT_Operations";"Assistant" = "SEC_DEPT_HR";"Associate" = "SEC_DEPT_Operations";"Manager" = "SEC_DEPT_Operations";"Supervisor" = "SEC_DEPT_Operations";"Office Assistant" = "SEC_DEPT_HR";"Executive Assistant" = "SEC_DEPT_Executive";"HR Specialist" = "SEC_DEPT_HR";"Recruiter" = "SEC_DEPT_HR";"Accountant" = "SEC_DEPT_Finance";"Financial Analyst" = "SEC_DEPT_Finance";"Marketing Specialist" = "SEC_DEPT_Marketing";"Sales Representative" = "SEC_DEPT_Sales";"Customer Service Rep" = "SEC_DEPT_Sales";"IT Support" = "SEC_DEPT_IT";"Network Engineer" = "SEC_DEPT_IT";"Systems Administrator" = "SEC_DEPT_IT";"Database Administrator" = "SEC_DEPT_IT";"Security Analyst" = "SEC_DEPT_Security";"Project Manager" = "SEC_DEPT_Operations";"Business Analyst" = "SEC_DEPT_Operations";"Product Manager" = "SEC_DEPT_Operations";"Graphic Designer" = "SEC_DEPT_Marketing";"Content Creator" = "SEC_DEPT_Marketing";"Social Media Manager" = "SEC_DEPT_Marketing";"Data Scientist" = "SEC_DEPT_Engineering";"Researcher" = "SEC_DEPT_Engineering";"Legal Counsel" = "SEC_DEPT_Legal";"Compliance Officer" = "SEC_DEPT_Compliance";"Facilities Manager" = "SEC_DEPT_Operations";"Executive Chef" = "SEC_DEPT_Operations";"Event Planner" = "SEC_DEPT_Operations";"Public Relations Specialist" = "SEC_DEPT_Marketing";"Communications Coordinator" = "SEC_DEPT_Marketing";"Training Specialist" = "SEC_DEPT_HR";"Health and Safety Officer" = "SEC_DEPT_Operations";"Logistics Coordinator" = "SEC_DEPT_Operations";"Procurement Specialist" = "SEC_DEPT_Operations";"Quality Assurance Analyst" = "SEC_DEPT_Engineering";"Risk Manager" = "SEC_DEPT_Compliance";"Innovation Manager" = "SEC_DEPT_Engineering"}

##Track by hierarchy
$ceos = @()
$cSuite = @()
$vps = @()
$directors = @()
$managers = @()
$staff = @()

for ($i=1; $i -le $userCount; $i++) {
    $fn = Get-Random $first
    $ln = Get-Random $last
    $phone = "{0:D3}-{1:D3}-{2:D4}" -f (Get-Random -Minimum 100 -Maximum 999), (Get-Random -Minimum 100 -Maximum 999), (Get-Random -Minimum 1000 -Maximum 9999)
    $title = Get-Random $titles
    $emplNum = "{0:D5}" -f (Get-Random -Minimum 100000 -Maximum 999999)
    
    if ($title -in @("CEO","CFO","COO","CTO","CIO","CSO","CMO","CHRO", "VP of Finance","VP of Operations","VP of Technology","VP of Sales","Director of Finance","Director of Operations","Director of Technology","Director of Sales")) {
        $titles = $titles | Where-Object { $_ -ne $title }
    }
    
    $usrnum = Get-Random -Minimum 0 -Maximum 20 
    $username = ($fn.Substring(0,1) + $ln + $usrnum).ToLower()
    
    if (Get-ADUserSafe -Sam $username) { continue }
    
    $pass = New-ComplexPassword -Length (Get-Random -Minimum 8 -Maximum 24) -NoAmbiguous
    $secure = ConvertTo-SecureString $pass -AsPlainText -Force
    
    New-ADUser -Server $script:DC -Name $username -DisplayName "$fn $ln" -GivenName $fn -Surname $ln -SamAccountName $username -UserPrincipalName "$username@$domain" -AccountPassword $secure -Enabled $true -Path $usersOuDn | Out-Null
    
    ##Determine office and address
    $isWFH = (Get-Random -Minimum 1 -Maximum 101) -le 20
    $userAddress = ""
    $userCity = ""
    $userState = ""
    $userPostalCode = ""
    
    if ($isWFH) {
        $userOffice = $wfhLocations | Get-Random
        $wfhState = $wfhStates[$userOffice]
        $userState = $wfhState.State
        $userAddress = New-RandomAddress -State $userState
        $userCity = New-RandomCity -State $userState
        $userPostalCode = "{0:D5}" -f (Get-Random -Minimum 10000 -Maximum 99999)
    } else {
        $userOffice = $offices.Keys | Get-Random
        $officeInfo = $offices[$userOffice]
        $userAddress = $officeInfo.Address
        $userCity = $officeInfo.City
        $userState = $officeInfo.State
        $userPostalCode = $officeInfo.PostalCode
    }
    
    ##Determine if contractor
    $isContractor = (Get-Random -Minimum 1 -Maximum 101) -le 10
    $userDescription = $title
    if ($isContractor) {
        $contractorFirm = $contractingFirms | Get-Random
        $userDescription = "$title (Contractor: $($contractorFirm.Name))"
    }
    
    ##Add to groups
    if ($titleToSecRole.ContainsKey($title)) {
        Add-ADGroupMember -Server $script:DC -Identity $titleToSecRole[$title] -Members $username -ErrorAction SilentlyContinue
    }
    if ($titleToDept.ContainsKey($title)) {
        Add-ADGroupMember -Server $script:DC -Identity $titleToDept[$title] -Members $username -ErrorAction SilentlyContinue
    }
    1..(Get-Random -Minimum 1 -Maximum 4) | ForEach-Object {
        Add-ADGroupMember -Server $script:DC -Identity "SEC_CIFS_$($cifsShares | Get-Random)" -Members $username -ErrorAction SilentlyContinue
    }
    1..(Get-Random -Minimum 2 -Maximum 6) | ForEach-Object {
        Add-ADGroupMember -Server $script:DC -Identity "SEC_APP_$($appNames | Get-Random)" -Members $username -ErrorAction SilentlyContinue
    }
    
    ##Collections
    Add-ADGroupMember -Server $script:DC -Identity "COL_AllUsers" -Members $username -ErrorAction SilentlyContinue
    Add-ADGroupMember -Server $script:DC -Identity "COL_AllEmployees" -Members $username -ErrorAction SilentlyContinue
    
    if ($title -in @("CEO","CFO","COO","CTO","CIO","CSO","CMO","CHRO","VP of Finance","VP of Operations","VP of Technology","VP of Sales","Director of Finance","Director of Operations","Director of Technology","Director of Sales","Manager of Finance","Manager of Operations","Manager of Technology","Manager of Sales")) {
        Add-ADGroupMember -Server $script:DC -Identity "COL_AllManagement" -Members $username -ErrorAction SilentlyContinue
        Add-ADGroupMember -Server $script:DC -Identity "COL_AllLeadership" -Members $username -ErrorAction SilentlyContinue
    }
    
    if ($title -in @("Engineer","Architect","Technician","Network Engineer","Systems Administrator","Database Administrator","IT Support","Data Scientist")) {
        Add-ADGroupMember -Server $script:DC -Identity "COL_AllTechnical" -Members $username -ErrorAction SilentlyContinue
    } else {
        Add-ADGroupMember -Server $script:DC -Identity "COL_AllNonTechnical" -Members $username -ErrorAction SilentlyContinue
    }
    
    if ($title -in @("Contractor","Temp")) {
        Add-ADGroupMember -Server $script:DC -Identity "COL_Contractors" -Members $username -ErrorAction SilentlyContinue
    } else {
        Add-ADGroupMember -Server $script:DC -Identity "COL_FullTime" -Members $username -ErrorAction SilentlyContinue
    }
    
    ##Set properties (now including address attributes)
    Set-ADUser $username -Replace @{
        Company = $companyName
        Description = $userDescription
        physicalDeliveryOfficeName = $userOffice
        streetAddress = $userAddress
        l = $userCity
        st = $userState
        postalCode = $userPostalCode
        c = "US"
        proxyAddresses = @("SMTP:$($fn).$($ln)@badger.local","smtp:$username@$domain","smtp:$($fn).$($ln)@$domain")
        mail = "$($fn).$($ln)@badger.local"
        telephoneNumber = $phone
        title = $title
        employeeID = $emplNum
    }
    
    ##Categorize by hierarchy
    if ($title -in $ceoTitles) { $ceos += @{Name = $username; Title = $title} }
    elseif ($title -in $cSuiteTitles) { $cSuite += @{Name = $username; Title = $title} }
    elseif ($title -in $vpTitles) { $vps += @{Name = $username; Title = $title} }
    elseif ($title -in $directorTitles) { $directors += @{Name = $username; Title = $title} }
    elseif ($title -in $managerTitles) { $managers += @{Name = $username; Title = $title} }
    else { $staff += @{Name = $username; Title = $title} }
    
    "$username,$username@$domain,$pass," | Out-File $credOut -Append -Encoding utf8
    
    if ($i % 500 -eq 0) {
        Write-Host "Created $i users"
    }
}

##HIERARCHICAL MANAGER ASSIGNMENT
Write-Host "Assigning hierarchical managers..."
$managerAssignments = 0

##C-Suite reports to CEO
if ($ceos.Count -gt 0) {
    $ceoUser = $ceos[0]
    foreach ($cSuiteUser in $cSuite) {
        try {
            Set-ADUser -Server $script:DC -Identity $cSuiteUser.Name -Manager $ceoUser.Name -ErrorAction SilentlyContinue
            $managerAssignments++
        } catch {}
    }
}

##VPs report to C-Suite
$vpIndex = 0
foreach ($vpUser in $vps) {
    if ($cSuite.Count -gt 0) {
        $manager = $cSuite[$vpIndex % $cSuite.Count]
        try {
            Set-ADUser -Server $script:DC -Identity $vpUser.Name -Manager $manager.Name -ErrorAction SilentlyContinue
            $managerAssignments++
        } catch {}
        $vpIndex++
    }
}

##Directors report to VPs
$directorIndex = 0
$dirManagerArray = if ($vps.Count -gt 0) { $vps } else { $cSuite }
foreach ($directorUser in $directors) {
    if ($dirManagerArray.Count -gt 0) {
        $manager = $dirManagerArray[$directorIndex % $dirManagerArray.Count]
        try {
            Set-ADUser -Server $script:DC -Identity $directorUser.Name -Manager $manager.Name -ErrorAction SilentlyContinue
            $managerAssignments++
        } catch {}
        $directorIndex++
    }
}

##Managers report to Directors
$managerIndex = 0
$manManagerArray = if ($directors.Count -gt 0) { $directors } else { $dirManagerArray }
foreach ($managerUser in $managers) {
    if ($manManagerArray.Count -gt 0) {
        $manager = $manManagerArray[$managerIndex % $manManagerArray.Count]
        try {
            Set-ADUser -Server $script:DC -Identity $managerUser.Name -Manager $manager.Name -ErrorAction SilentlyContinue
            $managerAssignments++
        } catch {}
        $managerIndex++
    }
}

##Staff report to Managers
$staffIndex = 0
$staffManagerArray = if ($managers.Count -gt 0) { $managers } else { $manManagerArray }
foreach ($staffUser in $staff) {
    if ($staffManagerArray.Count -gt 0) {
        $manager = $staffManagerArray[$staffIndex % $staffManagerArray.Count]
        try {
            Set-ADUser -Server $script:DC -Identity $staffUser.Name -Manager $manager.Name -ErrorAction SilentlyContinue
            $managerAssignments++
        } catch {}
        $staffIndex++
    }
}

##--------------------------
##4) COMPUTERS
##--------------------------
Write-Host "Creating computer objects..."
1..379 | ForEach-Object { $name = "WKST-{0:D3}" -f $_; if (-not (Get-ADComputerSafe -Name $name)) { New-ADComputer -Server $script:DC -Name $name -SamAccountName "$name$" -Path $wsOuDn | Out-Null } }
1..252 | ForEach-Object { $name = "LPTP-{0:D3}" -f $_; if (-not (Get-ADComputerSafe -Name $name)) { New-ADComputer -Server $script:DC -Name $name -SamAccountName "$name$" -Path $wsOuDn | Out-Null } }

$servers = @("SQL01","FILE01","APP01","PRINT01","BACKUP01","PrintColor01","DivPrintBW01","AcctDB01","AcctDB02","SECSUP01","DOORAccessCTLR01","HRAPP01","HRAPP02","HRDB01","HRDB02","ENGAPP01","ENGAPP02","ENGDB01","ENGDB02","LEGALAPP01","LEGALDB01","EXECAPP01","EXECDB01")
foreach ($s in $servers) { if (-not (Get-ADComputerSafe -Name $s)) { New-ADComputer -Server $script:DC -Name $s -Path $svOuDn | Out-Null } }

1..45 | ForEach-Object { $name = "LPSRV-{0:D2}" -f $_; if (-not (Get-ADComputerSafe -Name $name)) { New-ADComputer -Server $script:DC -Name $name -Path $svOuDn | Out-Null } }

foreach ($p in $winServerProfiles) {
    1..$p.Count | ForEach-Object {
        $name = "{0}-{1:D3}" -f $p.Prefix, $_
        if (-not (Get-ADComputerSafe -Name $name)) { New-ADComputer -Server $script:DC -Name $name -Path $svOuDn | Out-Null }
    }
}

##--------------------------
##5) DNS + DHCP (optional)
##--------------------------
if ($DoDNS -or $DoDHCP) {
    $wsComputers = Get-ADComputer -Server $script:DC -SearchBase $wsOuDn -Filter * | Sort-Object Name
    if ($wsComputers) {
        $n = $nets["Workstations"]
        $ip = $n.Start
        foreach ($c in $wsComputers) {
            if ($ip -gt $n.End) { break }
            $addr = "$($n.Prefix)$ip"
            if ($DoDNS) { Ensure-DnsARecord -Zone $dnsZone -Name $c.Name -IPv4 $addr }
            if ($DoDHCP) { Ensure-DhcpReservation -ScopeId $n.ScopeId -IPv4 $addr -ClientId (New-RandomMac) -Name $c.Name }
            $ip++
        }
    }
    
    $svComputers = Get-ADComputer -Server $script:DC -SearchBase $svOuDn -Filter * | Sort-Object Name
    if ($svComputers) {
        $n = $nets["Servers"]
        $ip = $n.Start
        foreach ($c in $svComputers) {
            if ($ip -gt $n.End) { break }
            $addr = "$($n.Prefix)$ip"
            if ($DoDNS) { Ensure-DnsARecord -Zone $dnsZone -Name $c.Name -IPv4 $addr }
            if ($DoDHCP) { Ensure-DhcpReservation -ScopeId $n.ScopeId -IPv4 $addr -ClientId (New-RandomMac) -Name $c.Name }
            $ip++
        }
    }
}

Write-Host ""
Write-Host "====== SUCCESS: Lab Environment Complete ======"
Write-Host "Company: $companyName"
Write-Host "Total Groups: $totalGroups"
Write-Host "Total Users: $($i-1)"
Write-Host "CEO: $($ceos.Count) | C-Suite: $($cSuite.Count) | VPs: $($vps.Count) | Directors: $($directors.Count) | Managers: $($managers.Count) | Staff: $($staff.Count)"
Write-Host "Manager Assignments: $managerAssignments"
Write-Host "Office Locations: $($offices.Count) + $($wfhLocations.Count) WFH"
Write-Host "Contracting Firms: $($contractingFirms.Count)"
Write-Host "Credentials: $credOut"
Write-Host ""
Write-Host "Ready for pentest lab exercises!"