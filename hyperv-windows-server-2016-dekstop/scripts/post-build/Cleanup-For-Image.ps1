
<#
.SYNOPSIS
Performs final system cleanup for a golden image and consolidates build logs to a persistent location.

.DESCRIPTION
This script is intended for the final stage of an automated image build (e.g., Packer).
It performs cleanup actions to reduce image size, remove build artifacts, and improve
general hygiene before sealing/capturing the image.

The script performs the following actions:
- Ensures a persistent log location exists at C:\Windows\Logs\Packer
- Migrates build logs from C:\Build\Logs to C:\Windows\Logs\Packer
- Removes the C:\Build directory (build artifacts)
- Cleans Windows and user temp folders (excluding packer-ps-env-vars-*)
- Clears Windows Update download cache (SoftwareDistribution\Download)
- Runs component store cleanup (DISM /StartComponentCleanup /ResetBase)
- Clears all Windows event logs
- Removes C:\Windows.old (with ownership/ACL handling and DISM fallback)

All actions and encountered errors are written to a log file and echoed to the console
to support troubleshooting and auditing.

.PARAMETER None
This script does not accept parameters.

.EXAMPLE
.\Cleanup-For-Image.ps1

Runs the final cleanup steps and writes the results to:
C:\Windows\Logs\Packer\cleanup-for-image.log

.NOTES
Author: Michael Waterman  
Purpose: Final image cleanup for automated provisioning (e.g. Packer)  
Requirements:
- Administrator privileges
- Write access to C:\Windows\Logs\Packer
- DISM, wevtutil, takeown.exe, and icacls.exe available (standard Windows tooling)

Logging location:
C:\Windows\Logs\Packer\cleanup-for-image.log

Logging format:
[YYYY-MM-DD HH:MM:SS] [LEVEL] Message

Possible log levels:
- INFO  – Normal operational messages
- WARN  – Non-critical warnings (e.g., failure to clear specific event logs)
- ERROR – Execution failures for major steps (script continues where possible)

Operational considerations:
- Clearing event logs is typically only appropriate for golden images and lab builds.
- DISM cleanup (/ResetBase) can reduce component rollback capability.
- Removing Windows.old may require ownership and ACL changes; a reboot may be needed
  if files are locked.
#>


$ErrorActionPreference = "Stop"

# ---------------------------------------------------------
# Locations
# ---------------------------------------------------------
$BuildRoot      = "C:\Build"
$OldLogRoot     = "C:\Build\Logs"
$NewLogRoot     = "C:\Windows\Logs\Packer"
$CleanupLogFile = Join-Path $NewLogRoot "cleanup-for-image.log"

# ---------------------------------------------------------
# Logging
# ---------------------------------------------------------
$LogDir  = "C:\Windows\Logs\Packer"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$LogFile = Join-Path $LogDir "cleanup-for-image.log"

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

Write-Log '===== Starting final image cleanup ====='

# ---------------------------------------------------------
# 1. Migrate logs to C:\Windows\Logs\Packer
# ---------------------------------------------------------
Write-Log 'Migrating logs from C:\Build\Logs to C:\Windows\Logs\Packer...'
try {
    if (Test-Path $OldLogRoot) {
        Copy-Item -Path "$OldLogRoot\*" -Destination $NewLogRoot -Recurse -Force
        Write-Log 'Log migration completed.'
    }
    else {
        Write-Log 'No logs found in C:\Build\Logs — nothing to migrate.'
    }
}
catch {
    Write-Log ("Log migration FAILED: {0}" -f $_.Exception.Message) 'ERROR'
}

# ---------------------------------------------------------
# 2. Delete C:\Build completely
# ---------------------------------------------------------
Write-Log 'Removing C:\Build...'
try {
    if (Test-Path $BuildRoot) {
        Remove-Item $BuildRoot -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log 'C:\Build removed.'
    }
    else {
        Write-Log 'C:\Build does not exist — skipping removal.'
    }
}
catch {
    Write-Log ("Removing C:\Build FAILED: {0}" -f $_.Exception.Message) 'ERROR'
}

# ---------------------------------------------------------
# 3. Clean temp folders
# ---------------------------------------------------------
Write-Log 'Cleaning Windows and user temp folders...'
try {
    if (Test-Path 'C:\Windows\Temp') {
        Get-ChildItem 'C:\Windows\Temp' -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike 'packer-ps-env-vars-*' } |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    if ($env:TEMP -and (Test-Path $env:TEMP)) {
        Get-ChildItem $env:TEMP -Recurse -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Log 'Temp folders cleaned (excluding packer-ps-env-vars-*).'
}
catch {
    Write-Log ("Cleaning temp folders FAILED: {0}" -f $_.Exception.Message) 'ERROR'
}

# ---------------------------------------------------------
# 4. Clear Windows Update cache
# ---------------------------------------------------------
Write-Log 'Clearing Windows Update download cache...'
try {
    net stop wuauserv /y | Out-Null
    net stop bits /y     | Out-Null

    if (Test-Path 'C:\Windows\SoftwareDistribution\Download') {
        Remove-Item 'C:\Windows\SoftwareDistribution\Download\*' -Recurse -Force -ErrorAction SilentlyContinue
    }

    net start wuauserv | Out-Null
    net start bits     | Out-Null

    Write-Log 'Windows Update cache cleared.'
}
catch {
    Write-Log ("Clearing Windows Update cache FAILED: {0}" -f $_.Exception.Message) 'ERROR'
}

# ---------------------------------------------------------
# 5. WinSxS cleanup
# ---------------------------------------------------------
Write-Log 'Running WinSxS cleanup (DISM) — this may take a while...'
try {
    Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase |
        ForEach-Object { Write-Log $_ }
    Write-Log 'WinSxS cleanup completed.'
}
catch {
    Write-Log ("WinSxS cleanup FAILED: {0}" -f $_.Exception.Message) 'ERROR'
}

# ---------------------------------------------------------
# 6. Clear ALL Windows event logs
# ---------------------------------------------------------
Write-Log 'Clearing all Windows event logs...'
try {
    $logs = wevtutil el
    foreach ($log in $logs) {
        try {
            Write-Log ("Clearing log: {0}" -f $log)
            wevtutil cl "$log"
        }
        catch {
            Write-Log ("Failed to clear {0}: {1}" -f $log, $_.Exception.Message) 'WARN'
        }
    }
    Write-Log 'Event log clearing completed.'
}
catch {
    Write-Log ("Clearing event logs FAILED: {0}" -f $_.Exception.Message) 'ERROR'
}

# ---------------------------------------------------------
# 7. Remove C:\Windows.old if present
# ---------------------------------------------------------
$windowsOldPath = "C:\Windows.old"

if (Test-Path -LiteralPath $windowsOldPath) {
    Write-Host "[Cleanup] Found Windows.old at $windowsOldPath. Removing..." -ForegroundColor Yellow

    try {
        # Take ownership + grant Administrators full control (Windows.old is often protected)
        & takeown.exe /F $windowsOldPath /R /D Y | Out-Null
        & icacls.exe $windowsOldPath /grant "Administrators:(OI)(CI)F" /T /C | Out-Null

        # Try normal removal
        Remove-Item -LiteralPath $windowsOldPath -Recurse -Force -ErrorAction Stop

        Write-Host "[Cleanup] Windows.old removed successfully." -ForegroundColor Green
    }
    catch {
        Write-Warning "[Cleanup] Direct delete failed: $($_.Exception.Message)"
        Write-Host "[Cleanup] Trying DISM cleanup as fallback..." -ForegroundColor Yellow

        try {
            # Fallback: cleanup previous Windows installation files
            & dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase | Out-Null

            # Re-check and attempt delete again
            if (Test-Path -LiteralPath $windowsOldPath) {
                & takeown.exe /F $windowsOldPath /R /D Y | Out-Null
                & icacls.exe $windowsOldPath /grant "Administrators:(OI)(CI)F" /T /C | Out-Null
                Remove-Item -LiteralPath $windowsOldPath -Recurse -Force -ErrorAction Stop
            }

            if (-not (Test-Path -LiteralPath $windowsOldPath)) {
                Write-Host "[Cleanup] Windows.old removed after DISM fallback." -ForegroundColor Green
            } else {
                Write-Warning "[Cleanup] Windows.old still exists. It may be locked; consider reboot + rerun."
            }
        }
        catch {
            Write-Warning "[Cleanup] DISM fallback failed: $($_.Exception.Message)"
        }
    }
}
else {
    Write-Host "[Cleanup] No Windows.old found. Skipping." -ForegroundColor Gray
}

Write-Log '===== Final image cleanup completed successfully ====='
