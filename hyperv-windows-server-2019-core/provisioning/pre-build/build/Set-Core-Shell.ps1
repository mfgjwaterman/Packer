#Requires -RunAsAdministrator

<#
.SYNOPSIS
Configures PowerShell as the default shell on Windows Server Core systems and logs the operation.

.DESCRIPTION
This script is intended for use in Server Core environments, typically as part of an
automated image build process (e.g., Packer). It modifies the system shell configuration
by updating the Winlogon registry key to launch PowerShell instead of the default
command prompt interface.

The script performs the following actions:
- Ensures a persistent log location exists at C:\Windows\Logs\Packer
- Retrieves and logs the current shell configuration
- Sets the default shell to:
  PowerShell.exe -WindowStyle Maximized -NoLogo
- Logs the updated shell configuration
- Captures and logs any errors during execution

All actions and encountered errors are written to a log file and echoed to the console
to support troubleshooting and auditing.

.PARAMETER None
This script does not accept parameters.

.EXAMPLE
.\Set-Core-Shell.ps1

Runs the configuration and writes the results to:
C:\Windows\Logs\Packer\set-shell.log

.NOTES
Author: Michael Waterman (https://michaelwaterman.nl)  
Purpose: Configure PowerShell as the default shell for Windows Server Core environments  
Requirements:
- Administrator privileges
- Write access to C:\Windows\Logs\Packer
- Access to modify HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon

Logging location:
C:\Windows\Logs\Packer\set-shell.log

Logging format:
[YYYY-MM-DD HH:MM:SS] [LEVEL] Message

Possible log levels:
- INFO  – Normal operational messages
- WARN  – Non-critical warnings
- ERROR – Execution failures (script exits with code 1)

Operational considerations:
- Changing the Winlogon shell affects all interactive logons on the system.
- This configuration is typically intended for Server Core systems where PowerShell
  is preferred over cmd.exe.
- Incorrect shell configuration may impact usability or require recovery actions.
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