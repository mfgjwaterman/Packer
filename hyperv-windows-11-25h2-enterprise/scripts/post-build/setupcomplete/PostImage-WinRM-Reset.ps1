<#
.SYNOPSIS
Resets WinRM after provisioning/build and returns the system to a clean post-image state, with logging.

.DESCRIPTION
This script is intended for post-provisioning / post-image scenarios (for example after Packer,
and typically during first boot via SetupComplete.cmd) to remove temporary build-time WinRM
configuration and restore a clean, predictable remote management state.

Main actions:
- Creates/uses a persistent log location at C:\Windows\Logs\Packer
- Ensures required services are available for stability
- Restores WinRM configuration to OS defaults
- Removes existing WinRM listeners
- Sets network profiles to Private (best effort)
- Recreates the default WinRM listener (HTTP 5985)
- Removes temporary build certificates (CN=packer) from common machine/user stores
- Sets final WinRM service state based on target role:
  - Server: Automatic + Running
  - Client: Manual + optionally Stopped

.PARAMETER TargetRole
Determines the desired final WinRM state.
Valid values:
- Server
- Client

.PARAMETER RemoveAllListeners
Removes all existing WinRM listeners before recreating the default listener.

.PARAMETER CreateDefaultListener
Recreates the default WinRM listener via 'winrm quickconfig -quiet'.

.PARAMETER StopServiceOnClient
If TargetRole is Client, stop the WinRM service after cleanup.

.PARAMETER RemovePackerCert
Removes certificates matching CN=packer from common machine/user stores.

.EXAMPLE
.\WinRM-Reset-Defaults.ps1 -TargetRole Server

.EXAMPLE
.\WinRM-Reset-Defaults.ps1 -TargetRole Client

.NOTES
Author: Michael Waterman
Purpose: Post-image WinRM reset for golden image workflows
#>

[CmdletBinding()]
param(
    [ValidateSet("Server","Client")]
    [string]$TargetRole = "Server",

    [switch]$RemoveAllListeners = $true,
    [switch]$CreateDefaultListener = $true,
    [switch]$StopServiceOnClient = $true,
    [switch]$RemovePackerCert = $true
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------
# Logging
# ---------------------------------------------------------
$LogDir = "C:\Windows\Logs\Packer"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$LogFile = Join-Path $LogDir "winrm-reset-defaults.log"

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO","WARN","ERROR")]
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

        if ($svc.StartType -eq "Disabled") {
            Write-Log ("{0} service is Disabled. Setting StartupType to {1}." -f $DisplayName, $StartupType) "WARN"
            Set-Service -Name $ServiceName -StartupType $StartupType -ErrorAction Stop
        }

        if ($svc.Status -ne "Running") {
            Write-Log ("{0} service is {1}. Attempting to start..." -f $DisplayName, $svc.Status) "WARN"
            Start-Service -Name $ServiceName -ErrorAction Stop
            Start-Sleep -Seconds 1

            $svc = Get-Service -Name $ServiceName -ErrorAction Stop
            if ($svc.Status -eq "Running") {
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

function Set-NetworkProfilesPrivate {
    try {
        $profiles = Get-NetConnectionProfile -ErrorAction Stop

        foreach ($profile in $profiles) {
            if ($profile.NetworkCategory -ne "Private") {
                Write-Log ("Network '{0}' is '{1}'. Setting to Private." -f $profile.Name, $profile.NetworkCategory) "WARN"

                try {
                    Set-NetConnectionProfile -InterfaceIndex $profile.InterfaceIndex -NetworkCategory Private -ErrorAction Stop
                    Write-Log ("Network '{0}' successfully set to Private." -f $profile.Name)
                }
                catch {
                    Write-Log ("Failed to set network '{0}' to Private: {1}" -f $profile.Name, $_.Exception.Message) "WARN"
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
}

function Restore-WinRMDefaults {
    Write-Log "Restoring WinRM configuration to OS defaults..."

    try {
        & winrm invoke restore winrm/config '@{}' | Out-Null
        Write-Log "WinRM configuration restored to OS defaults."
    }
    catch {
        Write-Log ("WinRM restore failed: {0}" -f $_.Exception.Message) "WARN"
    }
}

function Remove-WinRMListeners {
    if (-not $RemoveAllListeners) {
        Write-Log "Listener removal skipped by configuration."
        return
    }

    Write-Log "Removing existing WinRM listeners..."

    try {
        $listeners = Get-ChildItem WSMan:\LocalHost\Listener -ErrorAction SilentlyContinue

        if ($listeners) {
            foreach ($listener in $listeners) {
                try {
                    Write-Log ("Removing listener: {0}" -f $listener.Name)
                    Remove-Item -Path $listener.PSPath -Recurse -Force -ErrorAction Stop
                }
                catch {
                    Write-Log ("Failed to remove listener '{0}': {1}" -f $listener.Name, $_.Exception.Message) "WARN"
                }
            }
            Write-Log "WinRM listeners removed."
        }
        else {
            Write-Log "No WinRM listeners found."
        }
    }
    catch {
        Write-Log ("Failed to enumerate/remove WinRM listeners: {0}" -f $_.Exception.Message) "WARN"
    }
}

function Create-DefaultWinRMListener {
    if (-not $CreateDefaultListener) {
        Write-Log "Default listener creation skipped by configuration."
        return
    }

    Write-Log "Creating default WinRM listener via winrm quickconfig..."

    try {
        & winrm quickconfig -quiet | Out-Null
        Write-Log "Default WinRM listener ensured via quickconfig."
    }
    catch {
        Write-Log ("Failed to create default WinRM listener via quickconfig: {0}" -f $_.Exception.Message) "WARN"
    }

    try {
        Enable-NetFirewallRule -DisplayGroup "Windows Remote Management" -ErrorAction SilentlyContinue | Out-Null
        Write-Log "WinRM firewall rules enabled."
    }
    catch {
        Write-Log ("Failed to enable WinRM firewall rules: {0}" -f $_.Exception.Message) "WARN"
    }
}

function Test-WinRMListeners {
    Write-Log "Validating WinRM listeners..."

    try {
        $listeners = Get-ChildItem WSMan:\LocalHost\Listener -ErrorAction Stop
        if ($listeners) {
            Write-Log ("WinRM listener count: {0}" -f $listeners.Count)
            foreach ($listener in $listeners) {
                Write-Log ("Listener present: {0}" -f $listener.Name)
            }
        }
        else {
            Write-Log "No WinRM listeners found after configuration." "WARN"
        }
    }
    catch {
        Write-Log ("Failed to enumerate WinRM listeners: {0}" -f $_.Exception.Message) "WARN"
    }
}

function Remove-PackerCertificates {
    if (-not $RemovePackerCert) {
        Write-Log "Packer certificate cleanup skipped by configuration."
        return
    }

    Write-Log "Removing leftover Packer certificates..."

    $stores = @(
        "Cert:\LocalMachine\My",
        "Cert:\LocalMachine\CA",
        "Cert:\LocalMachine\Root",
        "Cert:\CurrentUser\My",
        "Cert:\CurrentUser\CA",
        "Cert:\CurrentUser\Root"
    )

    foreach ($store in $stores) {
        try {
            if (-not (Test-Path $store)) {
                continue
            }

            $certs = Get-ChildItem -Path $store -ErrorAction SilentlyContinue | Where-Object {
                $_.Subject -match 'CN=packer' -or
                $_.Issuer -match 'CN=packer' -or
                $_.FriendlyName -match 'packer'
            }

            if ($certs) {
                foreach ($cert in $certs) {
                    try {
                        Write-Log ("Removing certificate from {0}: Subject='{1}', Thumbprint='{2}'" -f $store, $cert.Subject, $cert.Thumbprint)
                        Remove-Item -Path $cert.PSPath -Force -ErrorAction Stop
                    }
                    catch {
                        Write-Log ("Failed to remove certificate '{0}' from {1}: {2}" -f $cert.Thumbprint, $store, $_.Exception.Message) "WARN"
                    }
                }
            }
            else {
                Write-Log ("No packer certificates found in {0}" -f $store)
            }
        }
        catch {
            Write-Log ("Certificate cleanup failed in store {0}: {1}" -f $store, $_.Exception.Message) "WARN"
        }
    }
}

function Set-FinalWinRMState {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Server","Client")]
        [string]$Role
    )

    if ($Role -eq "Server") {
        Write-Log "TargetRole is Server. Setting WinRM to Automatic and Running."

        try {
            Set-Service -Name WinRM -StartupType Automatic -ErrorAction Stop
            Write-Log "WinRM service StartupType set to Automatic."
        }
        catch {
            Write-Log ("Failed to set WinRM StartupType to Automatic: {0}" -f $_.Exception.Message) "WARN"
        }

        try {
            Start-Service -Name WinRM -ErrorAction Stop
            Write-Log "WinRM service started."
        }
        catch {
            try {
                $svc = Get-Service -Name WinRM -ErrorAction Stop
                if ($svc.Status -eq "Running") {
                    Write-Log "WinRM service already running."
                }
                else {
                    Write-Log ("Failed to start WinRM service. Current state: {0}" -f $svc.Status) "WARN"
                }
            }
            catch {
                Write-Log ("Failed to verify/start WinRM service: {0}" -f $_.Exception.Message) "WARN"
            }
        }
    }
    else {
        Write-Log "TargetRole is Client. Setting WinRM to Manual."

        try {
            Set-Service -Name WinRM -StartupType Manual -ErrorAction Stop
            Write-Log "WinRM service StartupType set to Manual."
        }
        catch {
            Write-Log ("Failed to set WinRM StartupType to Manual: {0}" -f $_.Exception.Message) "WARN"
        }

        if ($StopServiceOnClient) {
            try {
                Stop-Service -Name WinRM -Force -ErrorAction Stop
                Write-Log "WinRM service stopped for Client target."
            }
            catch {
                try {
                    $svc = Get-Service -Name WinRM -ErrorAction Stop
                    if ($svc.Status -eq "Stopped") {
                        Write-Log "WinRM service already stopped."
                    }
                    else {
                        Write-Log ("Failed to stop WinRM service. Current state: {0}" -f $svc.Status) "WARN"
                    }
                }
                catch {
                    Write-Log ("Failed to verify/stop WinRM service: {0}" -f $_.Exception.Message) "WARN"
                }
            }
        }
        else {
            Write-Log "StopServiceOnClient not set. WinRM service left running."
        }
    }
}

# --------------------------
# Main
# --------------------------
Write-Log "=== Post-image WinRM reset starting ==="
Write-Log ("TargetRole: {0}" -f $TargetRole)

try {
    Ensure-ServiceRunning -ServiceName "Winmgmt" -DisplayName "Windows Management Instrumentation" -StartupType "Manual"
    Ensure-ServiceRunning -ServiceName "WinRM" -DisplayName "Windows Remote Management (WS-Management)" -StartupType "Manual"

    Restore-WinRMDefaults
    Remove-WinRMListeners
    Set-NetworkProfilesPrivate
    Create-DefaultWinRMListener
    Test-WinRMListeners
    Remove-PackerCertificates
    Set-FinalWinRMState -Role $TargetRole

    Write-Log "=== Post-image WinRM reset completed successfully ==="
    exit 0
}
catch {
    Write-Log ("Post-image WinRM reset FAILED: {0}" -f $_.Exception.Message) "ERROR"
    exit 1
}