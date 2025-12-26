<#
.SYNOPSIS
Locks the current user session and logs the action to a local log file.

.DESCRIPTION
This script locks the active Windows workstation using the built-in
LockWorkStation function via rundll32.exe.  

All actions are logged to a local log file, including:
- Script start
- Successful workstation lock
- Errors if the lock operation fails

The logging mechanism writes both to a log file and to the console,
making the script suitable for interactive use as well as automated
execution scenarios.

.PARAMETER None
This script does not accept parameters.

.EXAMPLE
.\Lock-Screen.ps1

Locks the current workstation and writes the result to:
C:\Build\Logs\lock-screen.log

.NOTES
Author: Michael Waterman (https://www.michaelwaterman.nl)
Purpose: Security hardening / session protection  
Requirements:
- Windows operating system
- Permission to execute rundll32.exe
- Write access to C:\Build\Logs

Logging format:
[YYYY-MM-DD HH:MM:SS] [LEVEL] Message

Possible log levels:
- INFO  – Normal operational messages
- WARN  – Non-critical warnings
- ERROR – Failures during execution

This script can be safely used in automation, scheduled tasks,
or security enforcement workflows.
#>

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------
# Logging setup
# ---------------------------------------------------------
$LogDir  = "C:\Build\Logs"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$LogFile = Join-Path $LogDir "lock-screen.log"

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $entry = "[$timestamp] [$Level] $Message"

    # Log to file
    Add-Content -Path $LogFile -Value $entry

    # Log to console
    switch ($Level) {
        "ERROR" { Write-Error $Message }
        "WARN"  { Write-Warning $Message }
        default { Write-Output $Message }
    }
}

try {
    Write-Log "Attempting to lock the workstation."

    Start-Process "rundll32.exe" "user32.dll,LockWorkStation" -ErrorAction Stop

    Write-Log "Workstation locked successfully."
}
catch {
    Write-Log "Failed to lock workstation. Error: $($_.Exception.Message)" "ERROR"
}
