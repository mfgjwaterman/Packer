@echo off
setlocal

REM ---------------------------------------------------------
REM Log location
REM ---------------------------------------------------------
set LOG=C:\Windows\Logs\Packer\setupcomplete.log
if not exist C:\Windows\Logs\Packer mkdir C:\Windows\Logs\Packer

echo [%date% %time%] Starting SetupComplete.cmd >> %LOG%

REM ---------------------------------------------------------
REM Run PostImage WinRM Hardening
REM ---------------------------------------------------------
echo [%date% %time%] Running PostImage-WinRM-reset.ps1 >> %LOG%
powershell.exe -ExecutionPolicy Bypass -File "C:\Windows\Setup\Scripts\postImage-winrm-reset.ps1"

REM ---------------------------------------------------------
REM Remove PostImage Script
REM ---------------------------------------------------------
if exist "C:\Windows\Setup\Scripts\postImage-winrm-reset.ps1" (
    echo [%date% %time%] Removing PostImage-WinRM-Hardening.ps1 >> %LOG%
    del /f /q "C:\Windows\Setup\Scripts\postImage-winrm-reset.ps1"
)

REM ---------------------------------------------------------
REM Delete the Bitlocker Prevention Key
REM Remove this key with the code below (uncomment) to 
REM activate BitLocker after deployment of the image
REM ---------------------------------------------------------
REM echo [%date% %time%] Delete the Bitlocker Prevention Key >> %LOG%
REM reg delete "HKLM\SYSTEM\CurrentControlSet\Control\BitLocker" /v PreventDeviceEncryption /f

REM ---------------------------------------------------------
REM Remove SetupComplete.cmd
REM ---------------------------------------------------------
echo [%date% %time%] Removing SetupComplete.cmd >> %LOG%
del /f /q "%~f0"

endlocal
exit /b 0
