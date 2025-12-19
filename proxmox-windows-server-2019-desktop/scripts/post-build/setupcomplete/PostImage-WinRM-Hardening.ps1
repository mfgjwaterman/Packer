$ErrorActionPreference = "Stop"

$logRoot = "C:\Windows\Logs\Packer"
if (-not (Test-Path $logRoot)) {
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
}
$logFile = Join-Path $logRoot "postimage-winrm-hardening.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $entry = "[$ts] [$Level] $Message"
    Add-Content -Path $logFile -Value $entry
}

Write-Log "=== Post-image WinRM hardening starting ==="

try {
    # 1. Harden WinRM settings
    try {
        Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $false -ErrorAction Stop
        Set-Item WSMan:\localhost\Client\AllowUnencrypted  -Value $false -ErrorAction Stop

        Set-Item WSMan:\localhost\Service\Auth\Basic       -Value $false -ErrorAction Stop
        Set-Item WSMan:\localhost\Client\Auth\Basic        -Value $false -ErrorAction Stop
        Set-Item WSMan:\localhost\Service\Auth\CredSSP     -Value $false -ErrorAction Stop

        Write-Log "WinRM AllowUnencrypted, Basic, CredSSP set to secure defaults."
    }
    catch {
        Write-Log ("Failed to set WinRM security options: {0}" -f $_.Exception.Message) "WARN"
    }

    # 2. Remove CN=packer cert and HTTPS listeners that use it
    try {
        $packerCerts = Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
            Where-Object { $_.Subject -eq 'CN=packer' }

        $thumbs = @()
        if ($packerCerts) {
            $thumbs = $packerCerts | Select-Object -ExpandProperty Thumbprint
            Write-Log ("Found packer certificate(s): {0}" -f ($thumbs -join ", "))
        }
        else {
            Write-Log "No CN=packer certificate found."
        }

        $listeners = Get-ChildItem WSMan:\LocalHost\Listener -ErrorAction SilentlyContinue
        foreach ($listener in $listeners) {
            $transportKey = $listener.Keys | Where-Object { $_ -like "Transport=*" }
            $isHttps      = $transportKey -match "HTTPS"

            if ($isHttps) {
                $listenerPath   = $listener.PSPath
                $listenerObject = Get-Item $listenerPath
                $listenerThumb  = $listenerObject.CertificateThumbprint

                if ($thumbs -and $thumbs -contains $listenerThumb) {
                    Write-Log ("Removing WinRM HTTPS listener at {0} (packer cert)." -f $listenerPath)
                    Remove-Item $listenerPath -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }

        if ($packerCerts) {
            foreach ($cert in $packerCerts) {
                Write-Log ("Removing packer certificate {0}" -f $cert.Thumbprint)
                Remove-Item -Path $cert.PSPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
        Write-Log ("WinRM listener/cert cleanup failed: {0}" -f $_.Exception.Message) "WARN"
    }

    Write-Log "Post-image WinRM hardening finished."
}
catch {
    Write-Log ("Post-image WinRM hardening FAILED: {0}" -f $_.Exception.Message) "ERROR"
}

Write-Log "=== Post-image WinRM hardening completed ==="
