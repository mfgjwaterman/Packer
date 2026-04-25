<#
.SYNOPSIS
Configures WinRM over HTTPS with a self-signed certificate for automated provisioning.

.DESCRIPTION
This script prepares a Windows system for secure remote management by configuring
WinRM over HTTPS. It is designed for automated provisioning scenarios such as
Packer builds or cloud-based image creation.

The script performs the following actions:
- Verifies administrative privileges
- Removes existing WinRM listeners
- Creates a self-signed certificate for WinRM
- Configures a new HTTPS WinRM listener
- Applies required WinRM service and security settings
- Configures firewall rules for WinRM (TCP 5986)
- Restarts the WinRM service

All actions and errors are logged to a local log file to support troubleshooting
and auditability.

.PARAMETER None
This script does not accept parameters.

.EXAMPLE
.\WinRM-Packer.ps1

Configures WinRM over HTTPS using a self-signed certificate and prepares the
system for remote management or image provisioning.

.NOTES
Author: Michael Waterman (https://www.michaelwaterman.nl)
Purpose: Secure WinRM configuration for automated provisioning (e.g. Packer)  
Requirements:
- Administrator privileges
- Windows Server or Windows client with WinRM support
- Permission to create certificates and firewall rules

Logging location:
C:\Build\Logs\winrm-packer.log

Logging format:
[YYYY-MM-DD HH:MM:SS] [LEVEL] Message

Possible log levels:
- INFO  – Normal operational messages
- WARN  – Non-critical warnings
- ERROR – Execution failures

Security considerations:
- WinRM is configured to allow Basic authentication and unencrypted traffic
  (intended for controlled build environments only).
- A self-signed certificate is generated automatically.
- Firewall access is limited to the local subnet.

This script is intended for temporary provisioning scenarios and should not
be used unchanged in production environments.
#>

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------
# Logging setup
# ---------------------------------------------------------
$LogDir  = "C:\Build\Logs"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$LogFile = Join-Path $LogDir "winrm-packer.log"

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

Write-Log "Running User Data Script"
Write-Host "(host) Running User Data Script"

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
    Write-Log "Elevation check failed: $_" "ERROR"
    exit 1
}

# ---------------------------------------------------------
# Remove existing WinRM listeners
# ---------------------------------------------------------
try {
    Write-Log "Removing existing WinRM listeners..."

    $existingListeners = Get-ChildItem WSMan:\LocalHost\Listener -ErrorAction SilentlyContinue
    if ($existingListeners) {
        $existingListeners | Remove-Item -Recurse -Force
        Write-Log "Existing listeners removed."
    }
    else {
        Write-Log "No existing listeners found."
    }
}
catch {
    Write-Log "Failed to remove listeners: $_" "ERROR"
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
    Write-Log "Failed to create certificate: $_" "ERROR"
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
        -Force

    Write-Log "HTTPS listener created."
}
catch {
    Write-Log "Failed to create HTTPS listener: $_" "ERROR"
    exit 1
}

# ---------------------------------------------------------
# WinRM service config
# ---------------------------------------------------------
try {
    Write-Log "Configuring WinRM service..."

    if ((Get-Service WinRM).Status -ne "Running") {
        Set-Service -Name WinRM -StartupType Automatic
        Start-Service -Name WinRM
        Write-Log "WinRM started."
    }
    else {
        Write-Log "WinRM already running."
    }
}
catch {
    Write-Log "Failed to configure WinRM service: $_" "ERROR"
    exit 1
}

# ---------------------------------------------------------
# WinRM advanced settings
# ---------------------------------------------------------
try {
    $build = [System.Environment]::OSVersion.Version.Build
    Write-Log "Detected OS build number: $build"

    if ($build -lt 20348) {
        Write-Log "OS < Server 2022 — setting MaxMemoryPerShellMB to 1024"
        Set-Item -Path WSMan:\localhost\Shell\MaxMemoryPerShellMB -Value 1024
    }
    else {
        Write-Log "Server 2022+ detected — leaving MaxMemoryPerShellMB untouched"
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
    Write-Log "Failed applying WinRM configuration: $_" "ERROR"
    exit 1
}

# ---------------------------------------------------------
# Firewall rule for WinRM over HTTPS
# ---------------------------------------------------------
try {
    Write-Log "Checking firewall rule for WinRM 5986..."

    if (-not (Get-NetFirewallRule -DisplayName "WinRM HTTPS-In" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule `
            -DisplayName "WinRM HTTPS-In" `
            -Direction Inbound `
            -Action Allow `
            -Protocol TCP `
            -LocalPort 5986 `
            -Program "SYSTEM" `
            -RemoteAddress "LocalSubnet"

        Write-Log "Firewall rule created."
    }
    else {
        Write-Log "Firewall rule already exists."
    }
}
catch {
    Write-Log "Failed to configure firewall: $_" "ERROR"
    exit 1
}

# ---------------------------------------------------------
# Restart WinRM
# ---------------------------------------------------------
try {
    Write-Log "Restarting WinRM service..."

    Restart-Service WinRM -Force

    Write-Log "WinRM restarted successfully."
}
catch {
    Write-Log "Failed to restart WinRM: $_" "ERROR"
    exit 1
}

Write-Log "User Data Script completed successfully."
