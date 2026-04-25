<#
.SYNOPSIS
Disables the Internet Explorer 11 optional feature and logs the result, optionally restarting if required.

.DESCRIPTION
This script is intended for automated build/provisioning workflows and hardening scenarios.
It checks the state of the Internet Explorer 11 optional Windows feature and disables it when
enabled. The script validates the end state and records all actions, warnings, and errors
to a log file for auditing and troubleshooting.

The script performs the following actions:
- Ensures it is running with Administrator privileges
- Detects and logs OS information
- Checks the state of the IE optional feature (Internet-Explorer-Optional-amd64)
- Disables the feature (without immediate restart)
- Re-checks and validates the resulting feature state
- Optionally triggers a restart if Windows indicates one is required and -RestartIfNeeded is set

.PARAMETER LogDirectory
Directory used for logging. Defaults to "C:\Build\Logs".
Note: the current implementation logs to "C:\Build\Logs" regardless of this parameter.

.PARAMETER RestartIfNeeded
If specified and Windows indicates a restart is required to finalize the feature disable,
the script will restart the computer automatically.

.EXAMPLE
.\Remove-InternetExplorer.ps1

Disables the Internet Explorer optional feature if it is enabled and writes logs to:
C:\Build\Logs\Remove-InternetExplorer.log

.EXAMPLE
.\Remove-InternetExplorer.ps1 -RestartIfNeeded

Disables the Internet Explorer optional feature if needed and automatically restarts
the system when a reboot is required to complete the operation.

.NOTES
Author: Michael Waterman (https://www.michaelwaterman.nl)
Purpose: Hardening / golden image preparation (disable Internet Explorer 11 feature)  
Requirements:
- Administrator privileges
- DISM/Optional Features cmdlets available (Get-WindowsOptionalFeature, Disable-WindowsOptionalFeature)
- Write access to the log directory

Logging location:
C:\Build\Logs\Remove-InternetExplorer.log

Logging format:
[YYYY-MM-DD HH:MM:SS] [LEVEL] Message

Possible log levels:
- INFO  – Normal operational messages
- WARN  – Non-fatal warnings (e.g., reboot required)
- ERROR – Failures (script exits with code 1)

Acceptable end states after disable:
- Disabled
- DisablePending (reboot required to complete)
- DisabledWithPayloadRemoved (varies by OS/image)
#>


[CmdletBinding()]
param(
    [string]$LogDirectory = "C:\Build\Logs",
    [switch]$RestartIfNeeded
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------
# Logging setup
# ---------------------------------------------------------
$LogDir  = "C:\Build\Logs"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$LogFile = Join-Path $LogDir "Remove-InternetExplorer.log"

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

function Assert-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-Log "This script must be run as Administrator."
        throw "This script must be run as Administrator."
    }
}

# --- Main ---
try {
    Write-Log "=== Starting IE removal/disable script ==="
    
    Assert-Admin
    Write-Log "Running with administrative privileges."

    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    Write-Log ("Detected OS: {0} (Version: {1})" -f $os.Caption, $os.Version)

    # IE11 Optional Feature name used by DISM/PowerShell
    $featureName = "Internet-Explorer-Optional-amd64"

    # Ensure DISM module/cmdlets are available
    if (-not (Get-Command -Name Get-WindowsOptionalFeature -ErrorAction SilentlyContinue)) {
        throw "Get-WindowsOptionalFeature is not available on this system."
    }

    Write-Log "Checking feature state: $featureName"
    $feature = Get-WindowsOptionalFeature -Online -FeatureName $featureName -ErrorAction Stop

    Write-Log ("Current state: {0}" -f $feature.State)

    if ($feature.State -eq "Enabled") {
        Write-Log "Feature is enabled. Disabling now..."

        $WarningPreference = "Continue"
        $result = Disable-WindowsOptionalFeature -Online -FeatureName $featureName -NoRestart -WarningAction Continue -ErrorAction Stop 3>&1 |
            ForEach-Object {
                # Capture warnings and log them
                if ($_ -is [System.Management.Automation.WarningRecord]) {
                    Write-Log $_.Message "WARN"
                } else {
                    $_
                }
            }

        Write-Log ("Disable operation completed. RestartNeeded: {0}" -f $result.RestartNeeded)

        # Re-check
        $featureAfter = Get-WindowsOptionalFeature -Online -FeatureName $featureName -ErrorAction Stop
        Write-Log ("State after operation: {0}" -f $featureAfter.State)

        # Acceptable end states:
        # - Disabled               : feature fully disabled
        # - DisablePending         : reboot required to complete disable
        # - DisabledWithPayloadRemoved : payload removed (varies by OS/image)
        $acceptableStates = @("Disabled", "DisablePending", "DisabledWithPayloadRemoved")

        if ($acceptableStates -notcontains $featureAfter.State) {
            throw "Expected feature state one of '$($acceptableStates -join ", ")' but got '$($featureAfter.State)'."
        }

        if ($featureAfter.State -eq "DisablePending") {
            Write-Log "Feature disable is pending. A reboot is required to finalize removal." "WARN"
        }
        elseif ($featureAfter.State -eq "DisabledWithPayloadRemoved") {
            Write-Log "Feature is disabled and payload is removed." "INFO"
        }

        Write-Log "Internet Explorer Optional Feature has been disabled successfully."

        if ($result.RestartNeeded) {
            Write-Log "A reboot is required to complete the removal." "WARN"
            if ($RestartIfNeeded) {
                Write-Log "RestartIfNeeded was specified. Restarting computer now..." "WARN"
                Restart-Computer -Force
            }
        } else {
            Write-Log "No reboot required."
        }
    }
    elseif ($feature.State -eq "Disabled") {
        Write-Log "Feature is already disabled. No action needed."
    }
    else {
        Write-Log ("Feature is in state '{0}'. No automatic action taken." -f $feature.State) "WARN"
    }

    Write-Log "=== Completed successfully ==="
    exit 0
}
catch {
    Write-Log ("FAILED: {0}" -f $_.Exception.Message) "ERROR"
    Write-Log ("Stack: {0}" -f $_.ScriptStackTrace) "ERROR"
    Write-Log "=== Completed with errors ===" "ERROR"
    exit 1
}
