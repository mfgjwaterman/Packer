<#
.SYNOPSIS
Locates and launches a VirtIO guest tools installer from a labeled CD/DVD volume and logs the process.

.DESCRIPTION
This script is a helper for automated build/provisioning workflows. It searches the system
for CD/DVD drives, selects the drive that matches a specified volume label, and then
constructs the full path to a VirtIO guest tools installer (optionally within a subfolder).

If the installer is found, the script launches it (optionally with arguments) using elevated
execution. All steps, including parameter values, discovery results, and errors, are written
to a local log file and echoed to the console for troubleshooting and auditing.

.PARAMETER VolumeLabel
The expected volume label of the CD/DVD drive that contains the installer media
(e.g., "virtio-win" or another label used in your build pipeline). This parameter is required.

.PARAMETER InstallerName
The filename of the installer executable to launch. Defaults to "virtio-win-guest-tools.exe".

.PARAMETER InstallerRelativePath
Optional subdirectory (relative to the drive root) where the installer resides.
If omitted or empty, the installer is expected at the drive root.

.PARAMETER InstallerArguments
Optional arguments passed to the installer. Defaults to "/passive /noreboot".
If empty or whitespace, the installer is launched without arguments.

.EXAMPLE
.\Install-VirtIO.ps1 -VolumeLabel "virtio-win"

Searches for a CD/DVD drive with volume label "virtio-win", looks for
"virtio-win-guest-tools.exe" at the root of that drive, and launches it with
the default arguments.

.EXAMPLE
.\Install-VirtIO.ps1 -VolumeLabel "virtio-win" -InstallerRelativePath "guest-tools" -InstallerName "virtio-win-gt-x64.exe" -InstallerArguments "/quiet /noreboot"

Searches the labeled media and launches a custom installer from a subfolder
with custom arguments.

.NOTES
Author: Michael Waterman (https://www.michaelwaterman.nl)
Purpose: Automated VirtIO guest tools installation during image builds / provisioning  
Requirements:
- Access to a CD/DVD device (DriveType = 5) with the specified volume label
- The installer must exist at the resolved path
- Script must be able to write logs to C:\Build\Logs
- The installer is started with elevation (RunAs), which may require interactive consent
  depending on UAC configuration and execution context

Logging location:
C:\Build\Logs\virtio-installer.log

Logging format:
[YYYY-MM-DD HH:MM:SS] [LEVEL] Message

Possible log levels:
- INFO  – Normal operational messages
- WARN  – Non-critical warnings
- ERROR – Execution failures
#>


param(
    [Parameter(Mandatory = $true)]
    [string]$VolumeLabel,

    [string]$InstallerName = "virtio-win-guest-tools.exe",

    [string]$InstallerRelativePath = "",

    [string]$InstallerArguments = "/passive /noreboot"
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------
# Logging setup
# ---------------------------------------------------------
$LogDir  = "C:\Build\Logs"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$LogFile = Join-Path $LogDir "virtio-installer.log"

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

Write-Log "Starting VirtIO installer helper script."
Write-Log "Parameters: VolumeLabel='$VolumeLabel', InstallerName='$InstallerName', InstallerRelativePath='$InstallerRelativePath', InstallerArguments='$InstallerArguments'"

try {
    # ---------------------------------------------------------
    # Get all CD/DVD drives
    # ---------------------------------------------------------
    Write-Log "Searching for CD/DVD drives (DriveType = 5)..."
    $cdDrives = Get-CimInstance Win32_LogicalDisk -Filter "DriveType = 5" -ErrorAction Stop

    if (-not $cdDrives) {
        Write-Log "No CD/DVD drives were detected on this machine." "ERROR"
        exit 1
    }

    Write-Log "Found CD/DVD drives: $(( $cdDrives | ForEach-Object { $_.DeviceID } ) -join ', ')"

    # ---------------------------------------------------------
    # Find the drive with the given volume label
    # ---------------------------------------------------------
    Write-Log "Looking for CD/DVD drive with label '$VolumeLabel'..."
    $targetDrive = $cdDrives | Where-Object { $_.VolumeName -eq $VolumeLabel }

    if (-not $targetDrive) {
        Write-Log "No CD/DVD drive with label '$VolumeLabel' was found." "ERROR"
        exit 1
    }

    $driveRoot = $targetDrive.DeviceID + "\"
    Write-Log "Match found. Drive: $($targetDrive.DeviceID), VolumeName: '$($targetDrive.VolumeName)'"

    # ---------------------------------------------------------
    # Build installer path
    # ---------------------------------------------------------
    if ([string]::IsNullOrWhiteSpace($InstallerRelativePath)) {
        $installerPath = Join-Path $driveRoot $InstallerName
    }
    else {
        $installerPath = Join-Path $driveRoot (Join-Path $InstallerRelativePath $InstallerName)
    }

    Write-Log "Looking for installer at: $installerPath"

    if (-not (Test-Path -Path $installerPath)) {
        Write-Log "Installer '$InstallerName' not found at '$installerPath'." "ERROR"
        exit 1
    }

    Write-Log "Installer found. Starting installation..."

    # ---------------------------------------------------------
    # Start installer
    # ---------------------------------------------------------
    try {
        if ([string]::IsNullOrWhiteSpace($InstallerArguments)) {
            Write-Log "Launching installer without arguments."
            Start-Process -FilePath $installerPath -Verb RunAs
        }
        else {
            Write-Log "Launching installer with arguments: $InstallerArguments"
            Start-Process -FilePath $installerPath -ArgumentList $InstallerArguments -Verb RunAs
        }

        Write-Log "Installation process started successfully."
    }
    catch {
        Write-Log "Failed to launch installer: $($_.Exception.Message)" "ERROR"
        exit 1
    }

    Write-Log "VirtIO installer helper script completed successfully."
}
catch {
    Write-Log "Unexpected error in script: $($_.Exception.Message)" "ERROR"
    exit 1
}
