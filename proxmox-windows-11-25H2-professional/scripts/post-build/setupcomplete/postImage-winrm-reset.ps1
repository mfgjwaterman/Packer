<#
.SYNOPSIS
Resets WinRM to OS defaults after provisioning and removes build-time artifacts, with full logging.

.DESCRIPTION
This script is intended for post-provisioning / post-image steps (e.g., after Packer and/or
during/after sysprep phases) to return WinRM to a safer, default state.

The script performs the following actions:
- Creates/uses a persistent log location at C:\Windows\Logs\Packer
- Ensures required services are available (Winmgmt and WinRM) for stability
- Restores WinRM configuration to OS defaults (winrm invoke restore winrm/config '@{}')
- Removes existing WinRM listeners (optional)
- Ensures network profiles are set to Private to allow default listener creation (best-effort)
- Recreates the default WinRM listener (HTTP 5985) via winrm quickconfig (optional)
- Sets WinRM service startup to Manual and optionally stops the service
- Removes a temporary build certificate (CN=packer) from LocalMachine\My (optional)

All steps log INFO/WARN/ERROR messages to a local log file and write to the console,
making the script suitable for automated pipelines and troubleshooting.

.PARAMETER None
This script does not accept parameters.

.EXAMPLE
.\WinRM-Reset-Defaults.ps1

Restores WinRM to default OS configuration, removes listeners created during the build,
optionally recreates the default listener, and stops WinRM. Logs are written to:
C:\Windows\Logs\Packer\winrm-reset-defaults.log

.NOTES
Author: Michael Waterman  
Purpose: Post-image WinRM reset to defaults for golden image workflows (e.g. Packer)  
Requirements:
- Administrator privileges
- WinRM/WSMan available (winrm.exe, WSMan: drive)
- Access to modify services, network profiles, listeners, and LocalMachine certificate store

Logging location:
C:\Windows\Logs\Packer\winrm-reset-defaults.log

Logging format:
[YYYY-MM-DD HH:MM:SS] [LEVEL] Message

Possible log levels:
- INFO  – Normal operational messages
- WARN  – Non-fatal issues (script continues best-effort)
- ERROR – Fatal failure in main execution path

Operational considerations:
- Listener removal and quickconfig actions can affect remote management accessibility.
- Network profile changes to Private are applied best-effort and may be restricted by policy.
- Stopping WinRM and setting StartupType to Manual is typically desirable for golden images,
  but may not be appropriate for systems that require persistent remote management.
- CN=packer certificate removal helps prevent leaving build-time certificates behind.
#>


$ErrorActionPreference = "Stop"

# ---------------------------------------------------------
# Logging
# ---------------------------------------------------------
$LogDir  = "C:\Windows\Logs\Packer"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$LogFile = Join-Path $LogDir "winrm-reset-defaults.log"

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

function Ensure-ServiceRunning {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServiceName,

        [string]$DisplayName = $ServiceName,

        [ValidateSet("Automatic","Manual")]
        [string]$StartupType = "Manual"
    )

    try {
        $svc = Get-Service -Name $ServiceName -ErrorAction Stop

        if ($svc.StartType -eq 'Disabled') {
            Write-Log ("{0} service is Disabled. Setting StartupType to {1}." -f $DisplayName, $StartupType) "WARN"
            Set-Service -Name $ServiceName -StartupType $StartupType -ErrorAction Stop
        }

        if ($svc.Status -ne 'Running') {
            Write-Log ("{0} service is {1}. Attempting to start..." -f $DisplayName, $svc.Status) "WARN"
            Start-Service -Name $ServiceName -ErrorAction Stop

            Start-Sleep -Seconds 1
            $svc = Get-Service -Name $ServiceName -ErrorAction Stop

            if ($svc.Status -eq 'Running') {
                Write-Log ("{0} service started successfully." -f $DisplayName)
            }
            else {
                Write-Log ("{0} service did not reach Running state (current: {1})." -f $DisplayName, $svc.Status) "WARN"
            }
        }
        else {
            Write-Log ("{0} service is already running." -f $DisplayName)
        }
    }
    catch {
        Write-Log ("Failed to verify/start {0} service: {1}" -f $DisplayName, $_.Exception.Message) "WARN"
    }
}

function Reset-WinRMToDefaults {
    param(
        [switch]$RemoveAllListeners = $true,
        [switch]$CreateDefaultListener = $true,
        [switch]$StopService = $true,
        [switch]$RemovePackerCert = $true
    )

    Write-Log "Resetting WinRM to OS defaults..."

    # Ensure WinRM is available to run the restore
    Ensure-ServiceRunning -ServiceName "WinRM" -DisplayName "Windows Remote Management" -StartupType "Manual"

    # 1) Restore WinRM configuration to defaults for this OS build
    try {
        & winrm invoke restore winrm/config '@{}' | Out-Null
        Write-Log "WinRM configuration restored to OS defaults (winrm invoke restore winrm/config)."
    }
    catch {
        Write-Log ("WinRM restore failed: {0}" -f $_.Exception.Message) "WARN"
    }

    # 2) Remove all listeners
    if ($RemoveAllListeners) {
        try {
            Get-ChildItem WSMan:\LocalHost\Listener -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-Item -Path $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            Write-Log "WinRM listeners removed."
        }
        catch {
            Write-Log ("Removing WinRM listeners failed: {0}" -f $_.Exception.Message) "WARN"
        }
    }

    # 2A) Ensure network profile is Private (required for WinRM listener creation)
    try {
        $profiles = Get-NetConnectionProfile -ErrorAction Stop

        foreach ($profile in $profiles) {
            if ($profile.NetworkCategory -ne 'Private') {
                Write-Log ("Network '{0}' is '{1}'. Setting to Private." -f $profile.Name, $profile.NetworkCategory) "WARN"

                try {
                    Set-NetConnectionProfile `
                        -InterfaceIndex $profile.InterfaceIndex `
                        -NetworkCategory Private `
                        -ErrorAction Stop

                    Write-Log ("Network '{0}' successfully set to Private." -f $profile.Name)
                }
                catch {
                    Write-Log (
                        "Failed to set network '{0}' to Private: {1}" -f
                        $profile.Name, $_.Exception.Message
                    ) "WARN"
                }
            }
            else {
                Write-Log ("Network '{0}' already Private." -f $profile.Name)
            }
        }
        }
            catch {
        Write-Log ("Failed to query network connection profiles: {0}" -f $_.Exception.Message) "WARN"
        }

    # 2b) Create the default listener (HTTP 5985) + firewall rules if needed
    if ($CreateDefaultListener) {
        try {
            # quickconfig will (re)create listener and set firewall exception (when possible)
            & winrm quickconfig -quiet| Out-Null
            Write-Log "Default WinRM listener ensured (winrm quickconfig -quiet)."
        }
        catch {
            Write-Log ("Failed to create default WinRM listener via quickconfig: {0}" -f $_.Exception.Message) "WARN"
        }
    }

    # 3) Set service startup to Manual and optionally stop it
    try {
        Set-Service -Name WinRM -StartupType Manual -ErrorAction SilentlyContinue
        Write-Log "WinRM service StartupType set to Manual."
    }
    catch {
        Write-Log ("Failed to set WinRM StartupType: {0}" -f $_.Exception.Message) "WARN"
    }

    if ($StopService) {
        try {
            Stop-Service -Name WinRM -Force -ErrorAction SilentlyContinue
            Write-Log "WinRM service stopped."
        }
        catch {
            Write-Log ("Failed to stop WinRM service: {0}" -f $_.Exception.Message) "WARN"
        }
    }

    # 4) Optional: remove temporary CN=packer certificate used during builds
    if ($RemovePackerCert) {
        try {
            $packerCerts = Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
                Where-Object { $_.Subject -eq 'CN=packer' }

            if ($packerCerts) {
                $thumbs = $packerCerts | Select-Object -ExpandProperty Thumbprint
                Write-Log ("Found packer certificate(s): {0}" -f ($thumbs -join ", "))

                foreach ($cert in $packerCerts) {
                    Write-Log ("Removing packer certificate {0}" -f $cert.Thumbprint)
                    Remove-Item -Path $cert.PSPath -Force -ErrorAction SilentlyContinue
                }
            }
            else {
                Write-Log "No CN=packer certificate found."
            }
        }
        catch {
            Write-Log ("Packer certificate cleanup failed: {0}" -f $_.Exception.Message) "WARN"
        }
    }

    Write-Log "WinRM reset to defaults completed."
}

# --------------------------
# Main
# --------------------------
Write-Log "=== Post-image WinRM restore defaults starting ==="

try {
    # Helpful for stability in certain build phases
    Ensure-ServiceRunning -ServiceName "Winmgmt" -DisplayName "Windows Management Instrumentation" -StartupType "Manual"
    Ensure-ServiceRunning -ServiceName "WinRM" -DisplayName "Windows Remote Management (WS-Management)" -StartupType "Manual"

    # Restore WinRM to defaults AFTER sysprep has started
    Reset-WinRMToDefaults -RemoveAllListeners -CreateDefaultListener -StopService -RemovePackerCert

    Write-Log "=== Post-image WinRM restore defaults completed ==="
    exit 0
}
catch {
    Write-Log ("Post-image script FAILED: {0}" -f $_.Exception.Message) "ERROR"
    exit 1
}
