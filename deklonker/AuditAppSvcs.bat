:: Turn off Terminal output
@echo off
powershell -Command "Write-Host 'Auditing Apps and Services.' -ForegroundColor Cyan"

:: Limit variable scope, enable modern cmd line features, make variables updateable
setlocal EnableExtensions EnableDelayedExpansion

:: Check for installed but unwanted programs running 
@echo Checking for apps that should be dead
set "apps=brave.exe,discord.exe,MicrosoftEdgeUpdate.exe,SearchIndexer.exe"
for %%a in (%apps%) do (
    tasklist /fi "ImageName eq %%a" | find /i "%%a" >nul && (
        powershell -Command "Write-Host 'Program %%a is still running!' -ForegroundColor Red"
    )
)

:: Make sure permanently disabled services are dead
@echo Checking for services that should be permanently disabled
set disabled_svcs="AMD Crash Defender Service"
set "disabled_svcs=%disabled_svcs%,"AMD External Events Utility""
set "disabled_svcs=%disabled_svcs%,DiagTrack" &rem Connected User Experiences and Telemetry - MS spyware!
set "disabled_svcs=%disabled_svcs%,TrkWks" &rem Distributed Link Tracking Client - No NTFS network file links on this PC
set "disabled_svcs=%disabled_svcs%,lfsvc" &rem Geolocation Service - why run on a stationary PC?
set "disabled_svcs=%disabled_svcs%,iphlpsvc" &rem Only for a very specific VPN or an old IPv6-only network setups
set "disabled_svcs=%disabled_svcs%,PhoneSvc" &rem No phones on this PC
set "disabled_svcs=%disabled_svcs%,Spooler" &rem No printing from this PC
set "disabled_svcs=%disabled_svcs%,SysMain" &rem Stop crap like app preloading/predictive preloading/mem caching
for %%a in (%disabled_svcs%) do (
    tasklist /fi "ImageName eq %%~a" | find /i "%%~a" >nul && (
        powershell -Command "Write-Host 'Service %%~a is still running!' -ForegroundColor Red"
    )
)

:: Make sure services that will be restarted on reboot are dead
@echo Checking for services that should be killed for this gaming session
set "running_svcs= PcaSvc, WSearch, UsoSvc, wuauserv"
for %%a in (%running_svcs%) do (
    tasklist /svc /fi "Services eq %%a" | find /i "%%a" >nul && (
        powershell -Command "Write-Host 'Service %%a is still running!' -ForegroundColor Red"
    )
)

:: Make sure manual start services are dead
@echo Checking that manual start services are dead
set "man_start= WMPNetworkSvc, WMPNetwk"
for %%a in (%man_start%) do (
    tasklist /svc /fi "Services eq %%a" | find /i "%%a" >nul && (
        powershell -Command "Write-Host 'Service %%a is still running!' -ForegroundColor Red"
    )
)

powershell -Command "Write-Host 'Apps and Services Audit Complete.' -ForegroundColor Cyan"
