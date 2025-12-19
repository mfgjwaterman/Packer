# Define paths
$LogPath = "C:\Build\Log"
$LogFile = Join-Path $LogPath "LockScreen.log"

# Ensure log directory exists
if (-not (Test-Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

# Logging function
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "$Timestamp [$Level] $Message"
    Add-Content -Path $LogFile -Value $LogEntry
}

try {
    Write-Log "Attempting to lock the workstation."

    Start-Process "rundll32.exe" "user32.dll,LockWorkStation" -ErrorAction Stop

    Write-Log "Workstation locked successfully."
}
catch {
    Write-Log "Failed to lock workstation. Error: $($_.Exception.Message)" "ERROR"
}
