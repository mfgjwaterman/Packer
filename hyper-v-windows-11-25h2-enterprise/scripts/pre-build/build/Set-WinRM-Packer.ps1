<#
.SYNOPSIS
Configures WinRM over HTTPS with a self-signed certificate for automated provisioning.

.DESCRIPTION
This script prepares a Windows system for remote management by configuring
WinRM over HTTPS for controlled build/provisioning scenarios such as Packer.

Important behavior:
- Starts WinRM before using WSMan:\ paths
- Sets network profiles to Private where possible
- Creates a self-signed certificate
- Creates a WinRM HTTPS listener on TCP 5986
- Enables required WinRM authentication settings
- Creates a firewall rule for Private profile only
- Logs all actions to C:\Build\Logs\winrm-packer.log

.NOTES
Author: Michael Waterman
Purpose: Secure WinRM configuration for automated provisioning
#>

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------
# Logging setup
# ---------------------------------------------------------
$LogDir = "C:\Build\Logs"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$LogFile = Join-Path $LogDir "winrm-packer.log"

function Write-Log {
    param(
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

Write-Log "=== WinRM Packer configuration started ==="

# ---------------------------------------------------------
# Elevation check
# ---------------------------------------------------------
try {
    $isAdmin = ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-Log "Script must be run as Administrator. Aborting." "ERROR"
        exit 1
    }

    Write-Log "Running with elevated privileges."
}
catch {
    Write-Log "Elevation check failed: $($_.Exception.Message)" "ERROR"
    exit 1
}

# ---------------------------------------------------------
# Ensure WinRM service is available before WSMan actions
# ---------------------------------------------------------
try {
    Write-Log "Ensuring WinRM service is enabled and running..."

    Set-Service -Name WinRM -StartupType Automatic -ErrorAction Stop

    $winrmService = Get-Service -Name WinRM -ErrorAction Stop
    if ($winrmService.Status -ne "Running") {
        Start-Service -Name WinRM -ErrorAction Stop
        Start-Sleep -Seconds 2
        Write-Log "WinRM service started."
    }
    else {
        Write-Log "WinRM service already running."
    }

    # Initialize WinRM if needed
    & winrm quickconfig -quiet | Out-Null
    Write-Log "WinRM quickconfig completed."
}
catch {
    Write-Log "Failed to start or initialize WinRM: $($_.Exception.Message)" "ERROR"
    exit 1
}

# ---------------------------------------------------------
# Set network profile to Private
# ---------------------------------------------------------
try {
    Write-Log "Checking network connection profiles..."

    $profiles = Get-NetConnectionProfile -ErrorAction Stop

    foreach ($profile in $profiles) {
        if ($profile.NetworkCategory -ne "Private") {
            Write-Log ("Network '{0}' is '{1}'. Setting to Private." -f $profile.Name, $profile.NetworkCategory) "WARN"

            try {
                Set-NetConnectionProfile `
                    -InterfaceIndex $profile.InterfaceIndex `
                    -NetworkCategory Private `
                    -ErrorAction Stop

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
    Write-Log "Failed to query network profiles: $($_.Exception.Message)" "WARN"
}

# ---------------------------------------------------------
# Remove existing WinRM listeners
# ---------------------------------------------------------
try {
    Write-Log "Removing existing WinRM listeners..."

    $existingListeners = Get-ChildItem WSMan:\LocalHost\Listener -ErrorAction SilentlyContinue

    if ($existingListeners) {
        foreach ($listener in $existingListeners) {
            Write-Log ("Removing listener: {0}" -f $listener.Name)
            Remove-Item -Path $listener.PSPath -Recurse -Force -ErrorAction Stop
        }

        Write-Log "Existing listeners removed."
    }
    else {
        Write-Log "No existing listeners found."
    }
}
catch {
    Write-Log "Failed to remove listeners: $($_.Exception.Message)" "ERROR"
    exit 1
}

# ---------------------------------------------------------
# Create self-signed certificate
# ---------------------------------------------------------
try {
    Write-Log "Creating new self-signed certificate for WinRM..."

    $cert = New-SelfSignedCertificate `
        -DnsName "packer" `
        -CertStoreLocation "Cert:\LocalMachine\My"

    Write-Log "Certificate created: $($cert.Thumbprint)"
}
catch {
    Write-Log "Failed to create certificate: $($_.Exception.Message)" "ERROR"
    exit 1
}

# ---------------------------------------------------------
# Create new WinRM HTTPS listener
# ---------------------------------------------------------
try {
    Write-Log "Creating WinRM HTTPS listener..."

    New-Item -Path WSMan:\LocalHost\Listener `
        -Transport HTTPS `
        -Address * `
        -CertificateThumbprint $cert.Thumbprint `
        -Force | Out-Null

    Write-Log "HTTPS listener created."
}
catch {
    Write-Log "Failed to create HTTPS listener: $($_.Exception.Message)" "ERROR"
    exit 1
}

# ---------------------------------------------------------
# WinRM advanced settings
# ---------------------------------------------------------
try {
    Write-Log "Applying WinRM settings..."

    $build = [System.Environment]::OSVersion.Version.Build
    Write-Log "Detected OS build number: $build"

    if ($build -lt 20348) {
        Write-Log "OS build below Server 2022. Setting MaxMemoryPerShellMB to 1024."
        Set-Item -Path WSMan:\localhost\Shell\MaxMemoryPerShellMB -Value 1024
    }
    else {
        Write-Log "Server 2022 or newer detected. Leaving MaxMemoryPerShellMB untouched."
    }

    Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $true
    Set-Item WSMan:\localhost\Client\AllowUnencrypted -Value $true
    Set-Item WSMan:\localhost\Service\Auth\Basic -Value $true
    Set-Item WSMan:\localhost\Client\Auth\Basic -Value $true
    Set-Item WSMan:\localhost\Service\Auth\CredSSP -Value $true
    Set-Item WSMan:\localhost\MaxTimeoutms -Value 1800000

    Write-Log "WinRM settings applied."
}
catch {
    Write-Log "Failed applying WinRM configuration: $($_.Exception.Message)" "ERROR"
    exit 1
}

# ---------------------------------------------------------
# Firewall rule for WinRM over HTTPS - Private profile only
# ---------------------------------------------------------
try {
    Write-Log "Configuring firewall rule for WinRM HTTPS on TCP 5986..."

    $ruleName = "WinRM HTTPS-In"

    $existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue

    if (-not $existingRule) {
        New-NetFirewallRule `
            -DisplayName $ruleName `
            -Direction Inbound `
            -Action Allow `
            -Protocol TCP `
            -LocalPort 5986 `
            -Program "System" `
            -RemoteAddress "LocalSubnet" `
            -Profile Private `
            -Enabled True | Out-Null

        Write-Log "Firewall rule created for Private profile only."
    }
    else {
        Set-NetFirewallRule `
            -DisplayName $ruleName `
            -Profile Private `
            -Enabled True `
            -ErrorAction Stop

        Set-NetFirewallAddressFilter `
            -AssociatedNetFirewallRule $existingRule `
            -RemoteAddress LocalSubnet `
            -ErrorAction SilentlyContinue

        Write-Log "Existing firewall rule updated to Private profile only."
    }
}
catch {
    Write-Log "Failed to configure firewall: $($_.Exception.Message)" "ERROR"
    exit 1
}

# ---------------------------------------------------------
# Restart WinRM
# ---------------------------------------------------------
try {
    Write-Log "Restarting WinRM service..."

    Restart-Service WinRM -Force -ErrorAction Stop
    Start-Sleep -Seconds 2

    $winrmService = Get-Service WinRM -ErrorAction Stop
    Write-Log ("WinRM service status after restart: {0}" -f $winrmService.Status)
}
catch {
    Write-Log "Failed to restart WinRM: $($_.Exception.Message)" "ERROR"
    exit 1
}

# ---------------------------------------------------------
# Validation
# ---------------------------------------------------------
try {
    Write-Log "Validating WinRM listeners..."

    $listeners = winrm enumerate winrm/config/listener
    foreach ($line in $listeners) {
        Write-Log $line
    }

    Write-Log "Validation completed."
}
catch {
    Write-Log "Failed to validate WinRM listeners: $($_.Exception.Message)" "WARN"
}

Write-Log "=== WinRM Packer configuration completed successfully ==="
exit 0