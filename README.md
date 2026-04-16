# Active Directory Pentesting Lab — `broken.badger.local`

A fully scripted Windows Active Directory lab environment purpose-built for penetration testing practice. The lab deploys a realistic corporate AD forest populated with thousands of users, intentional misconfigurations, and a vulnerable ADCS (Active Directory Certificate Services) tier.

---

## Lab Overview

| Property | Value |
|---|---|
| Domain | `broken.badger.local` |
| NetBIOS Name | `BROKEN` |
| Domain Controller IP | `10.10.10.5` |
| Company Name (fictitious) | The Bad Badger |
| CA Name | `LAB-CA` |

---

## Network Layout

| Subnet | DHCP Scope | Purpose |
|---|---|---|
| `10.10.10.0/24` | `10.10.10.10 – .250` | Workstations |
| `10.10.20.0/24` | `10.10.20.10 – .250` | Servers |
| `10.10.30.0/24` | `10.10.30.10 – .200` | Printers |
| `10.10.40.0/24` | `10.10.40.10 – .200` | Phones |
| `10.10.50.0/24` | `10.10.50.10 – .200` | Linux Servers |

All scopes are served by the Domain Controller. Gateway addresses are at `.1` of each subnet.

---

## Directory Structure

```
ADLabSetup/
├── ENVSetup/                   # Core AD environment build scripts (run in order)
│   ├── 01-ENVSETUP_1-FeatureDNSDHCP_Setup.ps1
│   ├── 02-ENVSETUP_2-OUGroupUser_Creation.ps1
│   ├── 03-ENVSETUP_3-SetupShare.ps1
│   ├── 04-ENVSETUP_9-WeakSVCAccts.ps1
│   ├── 05-ENVSETUP_10-LogonPatterns.ps1
│   ├── 06-ENVSETUP_11-AdvancedLoginConfig.ps1
│   ├── 07-ENVSETUP_12-GroupPolicies.ps1
│   ├── 08-ENVSETUP_13-LAPSMisconfiguration.ps1
│   └── 09-ENVSETUP_14-ScheduledTasksVulnerabilities.ps1
│
└── CATempSetup/                # ADCS / Certificate Authority setup
    ├── CAAuthSetup.ps1
    ├── CACertTemps.ps1
    ├── DeleteBadTemplates.ps1
    └── Audit-CertTemplates.ps1
```

---

## Prerequisites

- Windows Server 2019 or 2022 (clean install, not yet promoted)
- PowerShell 5.1+
- Internet access for Windows Feature installation
- Run all scripts as **Domain Admin** (or local Administrator before promotion)
- The following PowerShell modules will be used (installed automatically where noted):
  - `ActiveDirectory`
  - `DnsServer`
  - `DhcpServer`
  - `GroupPolicy`
  - `ScheduledTasks`
  - `SmbShare`

---

## Setup Instructions

### Phase 1 — ENVSetup (Core Environment)

Run scripts in the numbered order from an **elevated PowerShell session** on the Domain Controller.

#### Script 01 — DC Promotion + DNS/DHCP
**`01-ENVSETUP_1-FeatureDNSDHCP_Setup.ps1`**

Promotes the server to a Domain Controller for `broken.badger.local`, then configures DNS and five DHCP scopes. The script is two-phase — it detects whether it is running pre- or post-promotion and acts accordingly. A reboot is required between phases.

```powershell
.\01-ENVSETUP_1-FeatureDNSDHCP_Setup.ps1
# Reboot when prompted, then run again to complete DHCP phase
```

#### Script 02 — OUs, Groups, Users, and Computers
**`02-ENVSETUP_2-OUGroupUser_Creation.ps1`**

Builds the full corporate AD structure:
- ~5,237 user accounts with realistic names, titles, office locations, and descriptions
- Hierarchical manager chain: CEO → C-Suite → VPs → Directors → Managers → Staff
- 397 security and distribution groups
- 630+ computer objects (workstations and servers)
- Contractor accounts
- Multi-site OU structure

```powershell
.\02-ENVSETUP_2-OUGroupUser_Creation.ps1
```
> ⚠️ This script is large and may take 10–20 minutes to complete.

#### Script 03 — SMB Shares
**`03-ENVSETUP_3-SetupShare.ps1`**

Creates `C:\CorpShares` with department-level subdirectories and intentionally weak or misconfigured ACLs. Creates associated security groups (`sec_finance`, `sec_helpdesk`, `sec_backup_ops`, `sec_executive`).

```powershell
.\03-ENVSETUP_3-SetupShare.ps1
```

#### Script 04 — Weak Service Accounts
**`04-ENVSETUP_9-WeakSVCAccts.ps1`**

Creates Kerberoastable service accounts with weak, guessable passwords:

| Account | Password | Purpose |
|---|---|---|
| `svc_sql` | `P@ssw0rd123!` | SQL Service |
| `svc_backup` | `P@ssw0rD456$` | Backup Service |
| `svc_sync` | *(see script)* | Sync Service |

All accounts are set to `PasswordNeverExpires`. These are intentional targets for Kerberoasting attacks.

```powershell
.\04-ENVSETUP_9-WeakSVCAccts.ps1
```

#### Script 05 — Logon Patterns
**`05-ENVSETUP_10-LogonPatterns.ps1`**

Adds realistic logon restrictions to user accounts:
- Workstation restrictions (limited devices per user)
- Login hour restrictions (business hours)
- Account lockout policy configuration
- Executives and managers get multi-device access; staff get single-device

```powershell
.\05-ENVSETUP_10-LogonPatterns.ps1
```
> Logged to `C:\LabSetup-Phase10-LogonPatterns.log`

#### Script 06 — Advanced Login Configuration
**`06-ENVSETUP_11-AdvancedLoginConfig.ps1`**

Extends logon configuration with RDP access controls and remote access restrictions. Builds on Phase 10 — must run after it.

```powershell
.\06-ENVSETUP_11-AdvancedLoginConfig.ps1
```
> Logged to `C:\LabSetup-Phase11-AdvancedLogin.log`

#### Script 07 — Vulnerable GPOs
**`07-ENVSETUP_12-GroupPolicies.ps1`**

Creates intentionally misconfigured Group Policy Objects linked to OUs. These introduce realistic GPO-based attack surfaces (e.g., script paths with weak ACLs, autologon settings, mapped drives with credentials).

```powershell
.\07-ENVSETUP_12-GroupPolicies.ps1
```

#### Script 08 — LAPS Misconfiguration
**`08-ENVSETUP_13-LAPSMisconfiguration.ps1`**

Detects whether the LAPS schema is present and either:
- Configures LAPS with overly permissive ACLs (too many users can read `ms-Mcs-AdmPwd`), or
- Falls back to equivalent vulnerabilities if LAPS is not installed

```powershell
.\08-ENVSETUP_13-LAPSMisconfiguration.ps1
```

#### Script 09 — Scheduled Task Vulnerabilities
**`09-ENVSETUP_14-ScheduledTasksVulnerabilities.ps1`**

Creates `C:\Tasks` with subdirectories (`Backups`, `Maintenance`, `Updates`) that have intentionally weak ACLs. Scheduled tasks are created referencing scripts in these directories, enabling privilege escalation via writable task paths.

```powershell
.\09-ENVSETUP_14-ScheduledTasksVulnerabilities.ps1
```
> Logged to `C:\LabSetup-Phase14.log`

---

### Phase 2 — CATempSetup (ADCS / Certificate Authority)

Run from an **elevated PowerShell session** on the server designated as the CA (can be the same DC).

#### Step 1 — Install and Configure the CA
**`CAAuthSetup.ps1`**

Installs `ADCS-Cert-Authority` and `ADCS-Web-Enrollment`, then configures an Enterprise Root CA named `LAB-CA` with a 2048-bit RSA key and SHA256.

```powershell
.\CAAuthSetup.ps1
```

#### Step 2 — (Optional) Remove Default Templates
**`DeleteBadTemplates.ps1`**

Removes any previously created lab templates (ESC1–ESC8 and a set of "Secure*" templates) to allow a clean re-deployment. Use this if re-running `CACertTemps.ps1`.

```powershell
.\DeleteBadTemplates.ps1
```

#### Step 3 — Deploy Vulnerable Certificate Templates
**`CACertTemps.ps1`**

Auto-detects the CA and creates and publishes a set of intentionally vulnerable certificate templates covering the ESC1–ESC8 attack classes:

| Template | ESC Class | Vulnerability |
|---|---|---|
| `ESC1-Lab` | ESC1 | Enrollee supplies Subject, any user can enroll |
| `ESC2-Lab` | ESC2 | Any Purpose EKU |
| `ESC3-Lab` | ESC3 | Certificate Request Agent abuse |
| `ESC4-Lab` | ESC4 | Weak template ACLs (WriteDACL) |
| `ESC5-Lab` | ESC5 | Weak CA ACLs |
| `ESC6-Lab` | ESC6 | EDITF_ATTRIBUTESUBJECTALTNAME2 |
| `ESC7-Lab` | ESC7 | Vulnerable CA officer/manager rights |
| `ESC8-Lab` | ESC8 | NTLM relay to HTTP enrollment endpoint |

```powershell
.\CACertTemps.ps1
```

#### Step 4 — Audit and Validate Templates
**`Audit-CertTemplates.ps1`**

Enumerates all deployed templates, validates permissions, confirms vulnerabilities are in place, and optionally generates an exploitation guidance report. Requires Domain Admin or Enterprise Admin.

```powershell
# Basic audit
.\Audit-CertTemplates.ps1 -DomainDN "DC=broken,DC=badger,DC=local"

# With exploitation guidance
.\Audit-CertTemplates.ps1 -DomainDN "DC=broken,DC=badger,DC=local" -TestExploitation -GenerateReport
```

---

## Intended Attack Surface Summary

| Category | Technique |
|---|---|
| Credential Access | Kerberoasting (`svc_sql`, `svc_backup`, `svc_sync`) |
| Lateral Movement | Weak SMB share ACLs, RDP misconfigs |
| Privilege Escalation | Writable scheduled task paths, LAPS ACL abuse |
| Domain Escalation | Misconfigured GPOs, ADCS ESC1–ESC8 |
| Enumeration | 5,000+ realistic users/groups, hierarchical org structure |

---

## Log Files

| Log | Location |
|---|---|
| Phase 10 (Logon Patterns) | `C:\LabSetup-Phase10-LogonPatterns.log` |
| Phase 11 (Advanced Login) | `C:\LabSetup-Phase11-AdvancedLogin.log` |
| Phase 14 (Scheduled Tasks) | `C:\LabSetup-Phase14.log` |

---

## Notes & Warnings

> **⚠️ For lab/isolated network use only.** This environment contains intentionally weak credentials, misconfigured services, and exploitable vulnerabilities. Never deploy on a production network or expose it to the internet.

- Scripts are idempotent where noted — most use `-ErrorAction SilentlyContinue` and check for existing objects before creating them.
- If Script 02 fails mid-run due to a transient AD replication issue, wait 30 seconds and re-run; it will skip already-created objects.
- The CA setup requires ADCS to be available in Windows Server roles — this is not available on Windows Server Core without GUI tools.
- `DeleteBadTemplates.ps1` is hardcoded to the `broken.badger.local` DN — update it if you change the domain name.
