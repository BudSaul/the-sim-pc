:: Turn off Terminal output
@echo off

powershell -Command "Write-Host 'Auditing Power Plan.' -ForegroundColor Cyan"

:: Limit variable scope, enable modern cmd line features, make variables updateable
setlocal EnableExtensions EnableDelayedExpansion

:: Make sure Ultimate-perf power plan is running.
set "ultimate_guid=dbdf73d7-cd8a-4e4f-ba93-85d9f863c61f"
for /f "tokens=4" %%a in ('powercfg /getactivescheme') do set "active_guid=%%a"
if "%active_guid%"=="%ultimate_guid%" (
    powershell -Command "Write-Host 'Ultimate power plan is running.' -ForegroundColor Green"
) else (
    powershell -Command "Write-Host 'Ultimate power plan is not running!' -ForegroundColor Red"
)

@REM 3. USB & Peripheral Power
@REM USB Hub Power Management: Ensure "Allow the computer to turn off this device" is unchecked in Device Manager for all USB Root Hubs. 

:: 1. USB Selective Suspend (Optimal: 0 = Disabled)
call :CheckPowerSetting "2a737441-1930-4402-8d77-b2bebba308a3" "48e6b7a6-50f5-4782-a5d4-53bb8f07e226" 0 "USB Selective Suspend"

:: 2. Minimum Processor State (Optimal: 100% Percent)
call :CheckPowerSetting "SUB_PROCESSOR" "PROCTHROTTLEMIN" 100 "Min Processor State"

:: 3. Maximum Processor State (Optimal: 100% Percent)
call :CheckPowerSetting "SUB_PROCESSOR" "PROCTHROTTLEMAX" 100 "Max Processor State"

:: 4. Processor Performance Core Parking (Optimal: 0% Min)
:: Note: Some systems use CPMIN or PERFPARK
call :CheckPowerSetting "SUB_PROCESSOR" "CPMINCORES1" 0 "Core Parking Min"

:: 5. PCI Express Link State Power Management (Optimal: 0 = Off)
call :CheckPowerSetting "SUB_PCIEXPRESS" "ASPM" 0 "PCIe Link State Management"

:: 6. Hard Disk Idle Timeout (Optimal: 0 = Never)
call :CheckPowerSetting "SUB_DISK" "DISKIDLE" 0 "Hard Disk Idle Timeout"

:: 7. Allow Wake Timers (Optimal: 0 = Disabled)
:: Prevents Windows from waking up to do background updates mid-sim
call :CheckPowerSetting "SUB_SLEEP" "RTCWAKE" 0 "Allow Wake Timers"

powershell -Command "Write-Host 'Power Plan Audit Complete' -ForegroundColor Cyan; Write-Host"
exit /b

:CheckPowerSetting
setlocal
set "f_subGroup=%~1"
set "f_setting=%~2"
set "f_expected=%~3"
set "f_desc=%~4"
set "f_indexRegex=Current AC Power Setting Index: (0x[0-9a-fA-F]+)"
powershell -NoProfile -Command ^
    "$p = powercfg /query SCHEME_CURRENT %f_subGroup% %f_setting% | Out-String; " ^
    "if ($p -match '%f_indexRegex%') { " ^
    "  $valAsInt = [Convert]::ToInt32($Matches[1], 16); " ^
    "  if ($valAsInt -eq %f_expected%) { " ^
    "    Write-Host 'SUCCESS: %f_desc% is %f_expected%.' -ForegroundColor Green; " ^
    "    exit 0; " ^
    "  } else { " ^
    "    Write-Host ('WARNING: %f_desc% is ' + $valAsInt + ' (Expected %f_expected%).') -ForegroundColor Yellow; " ^
    "    exit 1; " ^
    "  } " ^
    "} else { " ^
    "  Write-Host 'ERROR: Could not parse %f_desc%.' -ForegroundColor Red; " ^
    "  exit 1; " ^
    "}"
endlocal & exit /b %errorlevel%
