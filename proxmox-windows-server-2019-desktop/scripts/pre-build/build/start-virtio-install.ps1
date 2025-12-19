<#
.SYNOPSIS
  Detect a CD/DVD drive by volume label and start an installer from it.
  Extended with logging and error handling.

.PARAMETER VolumeLabel
  The volume label of the CD/DVD you want to detect (e.g., "virtio-win-0.1.285").

.PARAMETER InstallerName
  Name of the installer on the disc (e.g., "setup.exe").

.PARAMETER InstallerRelativePath
  Optional subfolder on the disc where the installer resides.

.PARAMETER InstallerArguments
  Optional arguments to pass to the installer.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$VolumeLabel,

    [string]$InstallerName = "virtio-win-guest-tools.exe",

    [string]$InstallerRelativePath = "",

    [string]$InstallerArguments = "/passive /noreboot"
)

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
