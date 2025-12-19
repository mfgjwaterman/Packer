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
echo [%date% %time%] Running PostImage-WinRM-Hardening.ps1 >> %LOG%
powershell.exe -ExecutionPolicy Bypass -File "C:\Windows\Setup\Scripts\PostImage-WinRM-Hardening.ps1" >> %LOG% 2>&1

REM ---------------------------------------------------------
REM Remove PostImage Script
REM ---------------------------------------------------------
if exist "C:\Windows\Setup\Scripts\PostImage-WinRM-Hardening.ps1" (
    echo [%date% %time%] Removing PostImage-WinRM-Hardening.ps1 >> %LOG%
    del /f /q "C:\Windows\Setup\Scripts\PostImage-WinRM-Hardening.ps1"
)

REM ---------------------------------------------------------
REM BCDEdit set the timeout to 5
REM ---------------------------------------------------------
echo [%date% %time%] Set the bcd timeout to 5 >> %LOG%
cmd.exe /c bcdedit /timeout 5

REM ---------------------------------------------------------
REM Remove SetupComplete.cmd itself
REM ---------------------------------------------------------
echo [%date% %time%] Removing SetupComplete.cmd >> %LOG%
del /f /q "C:\Windows\Setup\Scripts\SetupComplete.cmd"

endlocal
exit /b 0
