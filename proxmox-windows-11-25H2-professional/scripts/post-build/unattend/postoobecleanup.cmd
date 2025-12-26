@echo off
setlocal
REM ---------------------------------------------------------
REM Log location
REM ---------------------------------------------------------
set LOG=C:\Windows\Logs\Packer\PostOOBECleanup.log
if not exist C:\Windows\Logs\Packer mkdir C:\Windows\Logs\Packer

echo [%date% %time%] Starting PostOOBECleanup.cmd >> %LOG%

REM ---------------------------------------------------------
REM Disable AutoLogon
REM ---------------------------------------------------------
echo [%date% %time%] Removing Autologon Registry Keys >> %LOG%
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /t REG_SZ /d 0 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v ForceAutoLogon /t REG_SZ /d 0 /f
reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultUserName /f
reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword /f
reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultDomainName /f

REM ---------------------------------------------------------
REM Cleanup temp user
REM ---------------------------------------------------------
echo [%date% %time%] Removing the Temp User >> %LOG%
net user temp /delete
rmdir /s /q C:\Users\temp

REM ---------------------------------------------------------
REM Remove unattend.xml
REM ---------------------------------------------------------
echo [%date% %time%] Delete the unattend.xml file >> %LOG%
if exist "C:\Windows\System32\Sysprep\unattend.xml" (
    del /f /q "C:\Windows\System32\Sysprep\unattend.xml"
)

REM ---------------------------------------------------------
REM Optional: disable Administrator again
REM be carefull, you need a user on the system
REM use this when joining a domain
REM Uncomment to activate
REM ---------------------------------------------------------
REM echo [%date% %time%] Deactivate the Administrator >> %LOG%
REM net user Administrator /active:no

REM ---------------------------------------------------------
REM Reboot 
REM ---------------------------------------------------------
echo [%date% %time%] Reboot the machine in 5 seconds >> %LOG%
shutdown /r /t 5 /f

REM ---------------------------------------------------------
REM Self delete
REM ---------------------------------------------------------
echo [%date% %time%] Delete the PostOOBECleanup.cmd file >> %LOG%
del "%~f0"

endlocal
exit /b 0
