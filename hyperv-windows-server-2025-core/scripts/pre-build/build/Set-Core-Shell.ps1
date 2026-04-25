<#
.SYNOPSIS
Sets PowerShell as the default shell on Windows Server Core and logs the action.

.DESCRIPTION
This script configures the system shell by modifying the Winlogon registry key:
HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\Shell

The shell will be set to:
PowerShell.exe -WindowStyle Maximized -NoLogo

All actions are logged to a local log file, including:
- Script start
- Current shell value
- New shell value
- Errors if the operation fails

.PARAMETER None

.EXAMPLE
.\Set-Core-Shell.ps1

.NOTES
Author: Michael Waterman
Purpose: Configure default shell for Server Core environments
#>

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------
# Logging setup
# ---------------------------------------------------------
$LogDir  = "C:\Windows\Logs\Packer"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$LogFile = Join-Path $LogDir "set-shell.log"

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $entry = "[$timestamp] [$Level] $Message"

    Add-Content -Path $LogFile -Value $entry

    switch ($Level) {
        "ERROR" { Write-Error $Message }
        "WARN"  { Write-Warning $Message }
        default { Write-Output $Message }
    }
}

# ---------------------------------------------------------
# Main
# ---------------------------------------------------------
try {
    Write-Log "=== Set PowerShell as default shell started ==="

    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    $propertyName = "Shell"

    # Get current value
    $currentValue = (Get-ItemProperty -Path $regPath -Name $propertyName -ErrorAction Stop).Shell
    Write-Log ("Current shell value: {0}" -f $currentValue)

    # Desired value
    $newValue = "PowerShell.exe -WindowStyle Maximized -NoLogo"

    # Set new value
    Set-ItemProperty -Path $regPath -Name $propertyName -Value $newValue -ErrorAction Stop

    Write-Log ("Shell successfully updated to: {0}" -f $newValue)

    Write-Log "=== Set PowerShell as default shell completed ==="
    exit 0
}
catch {
    Write-Log ("Failed to set shell. Error: {0}" -f $_.Exception.Message) "ERROR"
    exit 1
}