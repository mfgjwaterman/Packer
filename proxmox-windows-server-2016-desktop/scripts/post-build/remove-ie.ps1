<#
.SYNOPSIS
Disables/removes Internet Explorer (IE11) Optional Feature on Windows Server 2016/2019.

.DESCRIPTION
- Checks admin rights
- Logs to C:\Build\Logs by default
- Disables Optional Feature: Internet-Explorer-Optional-amd64
- Verifies result
- Reports if reboot is required
#>

[CmdletBinding()]
param(
    [string]$LogDirectory = "C:\Build\Logs",
    [switch]$RestartIfNeeded
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Logging helpers ---
function New-LogFilePath {
    param(
        [Parameter(Mandatory=$true)][string]$Dir,
        [Parameter(Mandatory=$true)][string]$BaseName
    )
    if (-not (Test-Path -Path $Dir)) {
        New-Item -Path $Dir -ItemType Directory -Force | Out-Null
    }
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    return Join-Path $Dir "$BaseName-$timestamp.log"
}

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("INFO","WARN","ERROR")][string]$Level = "INFO"
    )
    $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Write-Host $line
    Add-Content -Path $script:LogFile -Value $line
}

function Assert-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        throw "This script must be run as Administrator."
    }
}

# --- Main ---
$LogFile = New-LogFilePath -Dir $LogDirectory -BaseName "Remove-InternetExplorer"
$script:LogFile = $LogFile

try {
    Write-Log "=== Starting IE removal/disable script ==="
    Write-Log "Log file: $LogFile"

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
