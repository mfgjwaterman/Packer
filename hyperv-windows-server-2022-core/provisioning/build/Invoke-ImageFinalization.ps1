#Requires -RunAsAdministrator

<#
.SYNOPSIS
Performs post-Packer system finalization by restoring WinRM configuration, removing build artifacts, 
and preparing the system for imaging using Sysprep.

.DESCRIPTION
This script is intended for the final stage of an automated image build (e.g., Packer).
It restores Windows Remote Management (WinRM) to a clean and secure state, removes
temporary build artifacts such as Packer-generated certificates and scheduled tasks,
and prepares the system for capture.

The script performs the following actions:
- Ensures required services (WinRM, Winmgmt) are running and properly configured
- Restores WinRM configuration to OS defaults
- Removes all existing WinRM listeners (optional)
- Sets all network profiles to Private for consistent management behavior
- Recreates a default WinRM listener and enables firewall rules (optional)
- Validates WinRM listener configuration
- Removes Packer-related certificates from multiple certificate stores (optional)
- Configures final WinRM service state based on target role (Server or Client)
- Removes the scheduled task used for image finalization
- Deletes the script itself to prevent reuse
- Executes Sysprep with optional unattend configuration and shuts down the system

All actions and encountered errors are written to a log file and echoed to the console
to support troubleshooting and auditing.

.PARAMETER TargetRole
Specifies the intended role of the system (Server or Client). Determines the final
WinRM service configuration.

.PARAMETER RemoveAllListeners
Removes all existing WinRM listeners before reconfiguration.

.PARAMETER CreateDefaultListener
Creates a default WinRM listener using winrm quickconfig.

.PARAMETER StopServiceOnClient
Stops the WinRM service when TargetRole is set to Client.

.PARAMETER RemovePackerCert
Removes certificates associated with Packer from certificate stores.

.PARAMETER UnattendPath
Specifies an optional path to a Sysprep unattend.xml file.

.EXAMPLE
.\Post-Packer-Cleanup.ps1 -TargetRole Server

Runs the finalization process for a server image and writes the results to:
C:\Windows\Logs\Packer\post-packer-cleanup.log

.NOTES
Author: Michael Waterman (https://www.michaelwaterman.nl)
Purpose: Final image preparation and WinRM normalization for automated provisioning (e.g. Packer)  
Requirements:
- Administrator privileges
- Write access to C:\Windows\Logs\Packer
- WinRM and Winmgmt services available
- Sysprep available at C:\Windows\System32\Sysprep\sysprep.exe

Logging location:
C:\Windows\Logs\Packer\post-packer-cleanup.log

Logging format:
[YYYY-MM-DD HH:MM:SS] [LEVEL] Message

Possible log levels:
- INFO  – Normal operational messages
- WARN  – Non-critical warnings (e.g., failure to remove specific listeners or certificates)
- ERROR – Execution failures for major steps (script terminates)

Operational considerations:
- Removing and recreating WinRM listeners ensures a clean and predictable management configuration.
- Setting network profiles to Private may be required for WinRM and firewall rule consistency.
- Removing Packer certificates helps prevent leftover trust artifacts in the final image.
- WinRM configuration differs between Server and Client roles to reduce attack surface.
- Sysprep generalizes the system; after execution, the machine will shut down and be ready for capture.
#>

[CmdletBinding()]
param(
    [ValidateSet("Server","Client")]
    [string]$TargetRole = "Server",

    [switch]$RemoveAllListeners = $true,
    [switch]$CreateDefaultListener = $true,
    [switch]$StopServiceOnClient = $true,
    [switch]$RemovePackerCert = $true,
    [string]$UnattendPath
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------
# Logging
# ---------------------------------------------------------
$LogDir = "C:\Windows\Logs\Packer"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$LogFile = Join-Path $LogDir "post-packer-cleanup.log"

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



# ---------------------------------------------------------
# functions
# ---------------------------------------------------------
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
            Write-Log "$DisplayName service is Disabled. Setting StartupType to $StartupType." "WARN"
            Set-Service -Name $ServiceName -StartupType $StartupType -ErrorAction Stop
        }

        if ($svc.Status -ne "Running") {
            Write-Log "$DisplayName service is $($svc.Status). Attempting to start..." "WARN"
            Start-Service -Name $ServiceName -ErrorAction Stop
            Start-Sleep -Seconds 1
        }

        $svc = Get-Service -Name $ServiceName -ErrorAction Stop
        Write-Log "$DisplayName service state: $($svc.Status)."
    }
    catch {
        Write-Log "Failed to verify/start $DisplayName service: $($_.Exception.Message)" "WARN"
    }
}

function Set-NetworkProfilesPrivate {
    try {
        $profiles = Get-NetConnectionProfile -ErrorAction Stop

        foreach ($profile in $profiles) {
            if ($profile.NetworkCategory -ne "Private") {
                Write-Log "Network '$($profile.Name)' is '$($profile.NetworkCategory)'. Setting to Private." "WARN"

                try {
                    Set-NetConnectionProfile -InterfaceIndex $profile.InterfaceIndex -NetworkCategory Private -ErrorAction Stop
                    Write-Log "Network '$($profile.Name)' successfully set to Private."
                }
                catch {
                    Write-Log "Failed to set network '$($profile.Name)' to Private: $($_.Exception.Message)" "WARN"
                }
            }
            else {
                Write-Log "Network '$($profile.Name)' already Private."
            }
        }
    }
    catch {
        Write-Log "Failed to query network connection profiles: $($_.Exception.Message)" "WARN"
    }
}

function Restore-WinRMDefaults {
    Write-Log "Restoring WinRM configuration to OS defaults..."

    try {
        & winrm invoke restore winrm/config '@{}' | Out-Null
        Write-Log "WinRM configuration restored to OS defaults."
    }
    catch {
        Write-Log "WinRM restore failed: $($_.Exception.Message)" "WARN"
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
                    Write-Log "Removing listener: $($listener.Name)"
                    Remove-Item -Path $listener.PSPath -Recurse -Force -ErrorAction Stop
                }
                catch {
                    Write-Log "Failed to remove listener '$($listener.Name)': $($_.Exception.Message)" "WARN"
                }
            }
        }
        else {
            Write-Log "No WinRM listeners found."
        }
    }
    catch {
        Write-Log "Failed to enumerate/remove WinRM listeners: $($_.Exception.Message)" "WARN"
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
        Write-Log "Failed to create default WinRM listener via quickconfig: $($_.Exception.Message)" "WARN"
    }

    try {
        Enable-NetFirewallRule -DisplayGroup "Windows Remote Management" -ErrorAction SilentlyContinue | Out-Null
        Write-Log "WinRM firewall rules enabled."
    }
    catch {
        Write-Log "Failed to enable WinRM firewall rules: $($_.Exception.Message)" "WARN"
    }
}

function Test-WinRMListeners {
    Write-Log "Validating WinRM listeners..."

    try {
        $listeners = Get-ChildItem WSMan:\LocalHost\Listener -ErrorAction Stop

        if ($listeners) {
            Write-Log "WinRM listener count: $($listeners.Count)"
            foreach ($listener in $listeners) {
                Write-Log "Listener present: $($listener.Name)"
            }
        }
        else {
            Write-Log "No WinRM listeners found after configuration." "WARN"
        }
    }
    catch {
        Write-Log "Failed to enumerate WinRM listeners: $($_.Exception.Message)" "WARN"
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
                        Write-Log "Removing certificate from $store Subject='$($cert.Subject)', Thumbprint='$($cert.Thumbprint)'"
                        Remove-Item -Path $cert.PSPath -Force -ErrorAction Stop
                    }
                    catch {
                        Write-Log "Failed to remove certificate '$($cert.Thumbprint)' from $store $($_.Exception.Message)" "WARN"
                    }
                }
            }
            else {
                Write-Log "No packer certificates found in $store"
            }
        }
        catch {
            Write-Log "Certificate cleanup failed in store $store $($_.Exception.Message)" "WARN"
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
            Start-Service -Name WinRM -ErrorAction SilentlyContinue
            Write-Log "WinRM service set to Automatic and started."
        }
        catch {
            Write-Log "Failed to set/start WinRM for Server: $($_.Exception.Message)" "WARN"
        }
    }
    else {
        Write-Log "TargetRole is Client. Setting WinRM to Manual."

        try {
            Set-Service -Name WinRM -StartupType Manual -ErrorAction Stop
            Write-Log "WinRM service StartupType set to Manual."
        }
        catch {
            Write-Log "Failed to set WinRM StartupType to Manual: $($_.Exception.Message)" "WARN"
        }

        if ($StopServiceOnClient) {
            try {
                Stop-Service -Name WinRM -Force -ErrorAction Stop
                Write-Log "WinRM service stopped for Client target."
            }
            catch {
                Write-Log "Failed to stop WinRM service: $($_.Exception.Message)" "WARN"
            }
        }
    }
}

function Start-SelfDeleteAndSysprepShutdown {
    param(
        [string]$UnattendPath
    )

    $scriptPath = $PSCommandPath

    if (-not $scriptPath) {
        Write-Log "Cannot determine script path. Self-delete skipped." "WARN"
    }

    $sysprepArgs = @(
        "/generalize",
        "/oobe",
        "/shutdown",
        "/mode:vm"
    )

    if ($UnattendPath) {
        if (Test-Path $UnattendPath) {
            Write-Log "Using Sysprep unattend file: $UnattendPath"
            $sysprepArgs += "/unattend:$UnattendPath"
        }
        else {
            Write-Log "UnattendPath was specified but file does not exist: $UnattendPath" "ERROR"
            exit 1
        }
    }
    else {
        Write-Log "No Sysprep unattend file specified."
    }

    if ($scriptPath -and (Test-Path $scriptPath)) {
        try {
            Write-Log "Removing finalization script: $scriptPath"
            Remove-Item -LiteralPath $scriptPath -Force -ErrorAction Stop
            Write-Log "Finalization script removed."
        }
        catch {
            Write-Log "Failed to remove finalization script: $($_.Exception.Message)" "WARN"
        }
    }

    $sysprep = "C:\Windows\System32\Sysprep\sysprep.exe"

    Write-Log "Starting Sysprep with arguments: $($sysprepArgs -join ' ')"

    Start-Process -FilePath $sysprep -ArgumentList $sysprepArgs -Wait
}

function Remove-ImageFinalizationScheduledTask {
    param(
        [string]$TaskName = "PackerImageFinalization"
    )

    try {
        Write-Log "Removing scheduled task '$TaskName'."
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
        Write-Log "Scheduled task '$TaskName' removed successfully."
    }
    catch {
        Write-Log "Failed to remove scheduled task '$TaskName': $($_.Exception.Message)" "WARN"
    }
}

# ---------------------------------------------------------
# Main
# ---------------------------------------------------------
Write-Log "=== Post-Packer cleanup starting ==="
Write-Log "TargetRole: $TargetRole"

try {
    Ensure-ServiceRunning -ServiceName "Winmgmt" -DisplayName "Windows Management Instrumentation" -StartupType "Manual"
    Ensure-ServiceRunning -ServiceName "WinRM" -DisplayName "Windows Remote Management" -StartupType "Manual"

    Restore-WinRMDefaults
    Remove-WinRMListeners
    Set-NetworkProfilesPrivate
    Create-DefaultWinRMListener
    Test-WinRMListeners
    Remove-PackerCertificates
    Set-FinalWinRMState -Role $TargetRole

    Write-Log "WinRM cleanup completed successfully."

    Write-Log "Removing finalization scheduled task."
    Remove-ImageFinalizationScheduledTask

    Write-Log "Starting self-delete and shutdown."
    Start-SelfDeleteAndSysprepShutdown -UnattendPath $UnattendPath
}
catch {
    Write-Log "Post-Packer cleanup FAILED: $($_.Exception.Message)" "ERROR"
    exit 1
}