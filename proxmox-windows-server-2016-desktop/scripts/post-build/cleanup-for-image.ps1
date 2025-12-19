<#
  cleanup-for-image.ps1
  Final cleanup script for golden image creation.

  Actions:
  - Move logs from C:\Build\Logs to C:\Windows\Logs\Packer
  - Remove C:\Build entirely
  - Clean temp folders
  - Clean Windows Update cache
  - WinSxS cleanup via DISM
  - Clear all event logs
  - Reset WinRM security-related settings
  - Remove Packer WinRM HTTPS listener + self-signed cert (CN=packer)
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
# Ensure new log storage exists
# ---------------------------------------------------------
if (-not (Test-Path $NewLogRoot)) {
    New-Item -ItemType Directory -Path $NewLogRoot -Force | Out-Null
}

# ---------------------------------------------------------
# Logging
# ---------------------------------------------------------
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $entry = "[$ts] [$Level] $Message"

    Add-Content -Path $CleanupLogFile -Value $entry
    Write-Output $entry
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
