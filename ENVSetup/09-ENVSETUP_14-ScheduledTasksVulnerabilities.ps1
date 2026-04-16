#############################################
## PHASE 14 - REAL SCHEDULED TASK VULNS
#############################################

Import-Module ScheduledTasks

$ErrorActionPreference = "SilentlyContinue"

$root = "C:\Tasks"
$log  = "C:\LabSetup-Phase14.log"

#############################################
## LOG FUNCTION
#############################################

function Log {
    param($msg)
    $msg | Tee-Object -FilePath $log -Append
}

#############################################
## CREATE TASK DIRECTORIES (WEAK ACLs)
#############################################

$folders = @(
    "$root\Backups",
    "$root\Maintenance",
    "$root\Updates"
)

foreach ($f in $folders) {
    New-Item -ItemType Directory -Path $f -Force | Out-Null

    # Weak permissions (Users can modify)
    icacls $f /grant "Users:(OI)(CI)M" /T | Out-Null

    Log "[+] Created weak folder: $f"
}

#############################################
## DROP VULNERABLE BINARIES
#############################################

# Backup binary (replaceable → SYSTEM)
$backupExe = "$root\Backups\backup.bat"
Set-Content $backupExe @"
@echo off
echo Running backup...
whoami > C:\Tasks\whoami.txt
"@

# Update binary (unquoted path abuse)
$updatePath = "C:\Program Files\Lab App"
New-Item -ItemType Directory -Path $updatePath -Force | Out-Null

$updateExe = "$updatePath\update.bat"
Set-Content $updateExe @"
@echo off
echo Updating system...
"@

# Weak permissions
icacls $backupExe /grant "Users:(M)" | Out-Null
icacls $updatePath /grant "Users:(OI)(CI)M" | Out-Null

#############################################
## CREATE SCHEDULED TASKS (REAL VULNS)
#############################################

# 1. BACKUP TASK (PRIV ESC)
$action1 = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c $backupExe"
$trigger1 = New-ScheduledTaskTrigger -Daily -At 2am

Register-ScheduledTask `
    -TaskName "LabBackup" `
    -Action $action1 `
    -Trigger $trigger1 `
    -User "SYSTEM" `
    -RunLevel Highest `
    -Force

Log "[+] Created vulnerable task: LabBackup (modifiable binary)"

#############################################

# 2. UNQUOTED PATH TASK
# NOTE: intentionally NOT quoting path
$action2 = New-ScheduledTaskAction -Execute "C:\Program Files\Lab App\update.bat"
$trigger2 = New-ScheduledTaskTrigger -AtLogOn

Register-ScheduledTask `
    -TaskName "LabUpdater" `
    -Action $action2 `
    -Trigger $trigger2 `
    -User "SYSTEM" `
    -RunLevel Highest `
    -Force

Log "[+] Created vulnerable task: LabUpdater (unquoted path)"

#############################################

# 3. DLL HIJACK SIMULATION
$toolPath = "C:\Tools"
New-Item -ItemType Directory -Path $toolPath -Force | Out-Null

$exe = "$toolPath\security.bat"
Set-Content $exe @"
@echo off
echo Security check...
"@

# Weak dir perms → drop DLL/binary
icacls $toolPath /grant "Users:(OI)(CI)M" | Out-Null

$action3 = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c $exe"
$trigger3 = New-ScheduledTaskTrigger -AtStartup

Register-ScheduledTask `
    -TaskName "SecurityCheck" `
    -Action $action3 `
    -Trigger $trigger3 `
    -User "SYSTEM" `
    -RunLevel Highest `
    -Force

Log "[+] Created vulnerable task: SecurityCheck (writable execution path)"

#############################################
## OPTIONAL: DROP ATTACK PAYLOAD PLACEHOLDER
#############################################

Set-Content "$root\Backups\README.txt" @"
Replace backup.bat with your payload.
This task runs as SYSTEM.
"@

#############################################
## OUTPUT
#############################################

Log ""
Log "=== CREATED VULNERABLE TASKS ==="
Get-ScheduledTask | Where TaskName -in "LabBackup","LabUpdater","SecurityCheck" |
ForEach-Object {
    Log " - $($_.TaskName)"
}

Log ""
Log "[+] Phase 14 COMPLETE - REAL vulnerabilities deployed"