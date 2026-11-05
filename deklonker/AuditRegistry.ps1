# VR_Registry_Audit.ps1 - Comprehensive DCS/MSFS VR Audit
# This script handles HKCU (User) and HKLM (System) settings accurately.

#############################
# --- Registry Safety Net ---
#############################
[bool]$DoRepair = $false  # True backup registry hives and make changes, $false to only Audit

#--- Run accounting ---
$RunDateTime = Get-Date -Format "yyyyMMdd_HHmm"
$BackupDir = "$PSScriptRoot\RegistryBackups"

# --- Elevate to Admin ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Elevating to Administrator..." -ForegroundColor Cyan
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}


# --- Support functions ---

function Write-ChangeLog {
    param (
        [string]$Path,
        [string]$ValueName,
        $OldValue,
        $NewValue,
        [string]$Action = "UPDATED"
    )
    
    $logFile = Join-Path -Path $BackupDir -ChildPath "$($RunDateTime)_VR_Optimization_Log.txt"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Format the log entry
    $logEntry = "[$timestamp] [$Action] Path: $Path | Value: $ValueName | From: $OldValue | To: $NewValue"
    
    # Append to file
    $logEntry | Out-File -FilePath $logFile -Append -Encoding utf8
}

function Write-AuditLog {
    param (
        [string]$Message,
        [string]$ForegroundColor = "Gray"
    )
    
    $logFile = Join-Path -Path $BackupDir -ChildPath "$($RunDateTime)_VR_Audit_Log.txt"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Format the log entry
    $logEntry = "[$timestamp] $Message"
    
    # Append to file
    $logEntry | Out-File -FilePath $logFile -Append -Encoding utf8
    Write-Host $Message -ForegroundColor $ForegroundColor
}

function Export-MasterRegistryBackup {
    param (
        [string[]]$Paths
    )

    if (-not (Test-Path $BackupDir)) { New-Item -Path $BackupDir -ItemType Directory | Out-Null }
    $masterFile = Join-Path -Path $BackupDir -ChildPath "$($RunDateTime)_Master_VR_Backup.reg"

    $tempDir = "$env:TEMP\RegBackupTemp"
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
    New-Item $tempDir -ItemType Directory | Out-Null

    # 1. Export each hive to a temporary file
    Write-AuditLog "Exporting hives to temporary storage..." -ForegroundColor Gray
    $i = 0
    foreach ($path in $Paths) {
        $i++
        $regPath = $path -replace ':', ''
        reg export "$regPath" "$tempDir\$i.reg" /y > $null 2>&1
    }

    # 2. Stitch files together into one Master file
    # Standard .reg files require Unicode (UTF-16LE) encoding to be recognized by Windows
    Write-AuditLog "Merging into Master File: $($masterFile)" -ForegroundColor Cyan
    
    "Windows Registry Editor Version 5.00`r`n" | Set-Content $masterFile -Encoding Unicode
    
    Get-ChildItem "$tempDir\*.reg" | ForEach-Object {
        # Skip the header line from each individual file and append the rest
        (Get-Content $_.FullName) | Where-Object { $_ -notmatch 'Windows Registry Editor Version 5.00' } | 
        Add-Content $masterFile -Encoding Unicode
    }

    # 3. Cleanup
    Remove-Item $tempDir -Recurse -Force
    Write-AuditLog "SUCCESS: Single-file backup created." -ForegroundColor Green
}

function Test-RegistrySetting {
    param (
        [string]$Path,
        [string]$ValueName,
        $ExpectedValue,
        [string]$ExpectedType = "DWord",
        [string]$Description = "",
        [bool]$Repair = $DoRepair
    )

    # Standardize Path
    $Path = $Path -replace "HKEY_CURRENT_USER", "HKCU:" -replace "HKEY_LOCAL_MACHINE", "HKLM:"
    if ($Path -notmatch ":") { $Path = $Path.Replace("HKCU", "HKCU:").Replace("HKLM", "HKLM:") }

    # 1. Handle Missing Keys
    if (-not (Test-Path $Path)) {
        if ($Repair) {
            New-Item -Path $Path -Force | Out-Null
            Write-ChangeLog -Path $Path -ValueName "KEY_ROOT" -OldValue "NONE" -NewValue "CREATED" -Action "NEW_KEY"
            Write-AuditLog "FIXED: Created missing key $Path" -ForegroundColor Cyan
        } else {
            Write-AuditLog "ERROR: Key missing - $Path" -ForegroundColor Red
            return
        }
    }

    # 2. Capture Current State for Logging
    $item = Get-ItemProperty -Path $Path -Name $ValueName -ErrorAction SilentlyContinue
    $actualValue = if ($null -ne $item) { $item.$ValueName } else { "MISSING" }

    # 3. Check and Repair
    if ($actualValue.ToString() -eq $ExpectedValue.ToString()) {
        Write-AuditLog "SUCCESS: $ValueName is $ExpectedValue ($Description)" -ForegroundColor Green
    } else {
        if ($Repair) {
            $regType = if ($ExpectedType -eq "Int32") { "DWord" } else { $ExpectedType }
            
            # LOG THE CHANGE BEFORE APPLYING
            $actionType = if ($actualValue -eq "MISSING") { "CREATED" } else { "UPDATED" }
            Write-ChangeLog -Path $Path -ValueName $ValueName -OldValue $actualValue -NewValue $ExpectedValue -Action $actionType
            
            Set-ItemProperty -Path $Path -Name $ValueName -Value $ExpectedValue -Type $regType -Force
            Write-AuditLog "REPAIRED: $ValueName set to $ExpectedValue ($Description)" -ForegroundColor Cyan
        } else {
            Write-AuditLog "WARNING: $ValueName is $actualValue (Expected $ExpectedValue) [$Description]" -ForegroundColor Yellow
        }
    }
}

function Get-NvidiaGpuRegistryPath {
    $guid = "{4d36e968-e325-11ce-bfc1-08002be10318}"
    $basePath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$guid"

    if (Test-Path $basePath) {
        # -ErrorAction SilentlyContinue is mandatory to skip locked system subkeys
        $gpuKeys = Get-ChildItem $basePath -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' }

        foreach ($key in $gpuKeys) {
            $props = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
            
            if ($props -and $props.DriverDesc -like "*NVIDIA*") {
                # CLEANUP: This ensures we return "HKLM:\..." instead of the long Provider path
                return "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$guid\$($key.PSChildName)"
            }
        }
    }
    return $null
}

# Assemble a list of key names for backup
$HivesList = @(
    ($HkcuControPanel = "HKCU:\Control Panel"),
    ($HkcuCurrentVerion = "HKCU:\Software\Microsoft\Windows\CurrentVersion"),
    ($HkcuDirectX = "HKCU:\Software\Microsoft\DirectX"),
    ($HkcuExplorer = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"),
    ($HkcuGameConfigStore = "HKCU:\System\GameConfigStore"),
    ($HkcuNvidia = "HKCU:\Software\NVIDIA Corporation"),
    ($HkcuPersonalization = "HKCU:\Software\Microsoft\InputPersonalization"),
    ($HklmControl = "HKLM:\SYSTEM\CurrentControlSet\Control"),
    ($HklmCurrentVerion = "HKLM:\Software\Microsoft\Windows\CurrentVersion")
    ($HklmIFEO = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"),
    ($HklmNvidia = "HKLM:\SOFTWARE\NVIDIA Corporation"),
    ($HklmServices = "HKLM:\SYSTEM\CurrentControlSet\Services"),
    ($HklmSystemProfile = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"),
    ($HklmWindows = "HKLM:\SOFTWARE\Policies\Microsoft\Windows"),
    ($HklmWindowsUpdate = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate"),
    ($HklmPolicyManager = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager")
)

if ($DoRepair) {
    Write-AuditLog "--- Initializing Registry Safety Net ---" -ForegroundColor Cyan
    Export-MasterRegistryBackup -Paths $HivesList.Replace("HKCU:", "HKCU").Replace("HKLM:", "HKLM")
    Write-AuditLog "`nAll backups stored in: $PSScriptRoot\RegistryBackups`n" -ForegroundColor Gray
}

Clear-Host
Write-AuditLog "===============================================" -ForegroundColor Cyan
Write-AuditLog "   DCS / MSFS VR REGISTRY AUDIT (FEB 2026)    " -ForegroundColor Cyan
Write-AuditLog "===============================================`n" -ForegroundColor Cyan

# --- 3. User Settings (HKCU) ---
Write-AuditLog "[*] Auditing User Interface & Notifications..." -ForegroundColor Gray
Test-RegistrySetting "$HkcuCurrentVerion\PushNotifications" "ToastEnabled" 0 "Int32" "App Notifications"
Test-RegistrySetting "$HkcuExplorer" "DisableNotificationCenter" 1 "Int32" "Notification Center"
Test-RegistrySetting "$HkcuCurrentVerion\FocusAssist" "QuietHoursActive" 1 "Int32" "Focus Mode"

Write-AuditLog "`n[*] Auditing Game Recording & Fullscreen Optimizations..." -ForegroundColor Gray
Test-RegistrySetting "$HkcuCurrentVerion\GameDVR" "AppCaptureEnabled" 0 "Int32" "GameDVR Capture"
Test-RegistrySetting "$HkcuGameConfigStore" "GameDVR_Enabled" 0 "Int32" "Game Bar Hub"
Test-RegistrySetting "$HkcuGameConfigStore" "GameDVR_FSEBehavior" 2 "Int32" "Disable FSE"

Write-AuditLog "`n[*] Auditing Visuals & Privacy..." -ForegroundColor Gray
# Visuals & UI
Test-RegistrySetting "HKCU:\Software\Microsoft\Lighting" "AmbientLightingEnabled" 0 "Int32" "Dynamic RGB"
Test-RegistrySetting "$HkcuCurrentVerion\CDP" "CdpSessionUserEnable" 0 "Int32" "Share Across Devices"
Test-RegistrySetting "$HkcuControPanel\Desktop\WindowMetrics" "MinAnimate" "0" "String" "Window Animations"
Test-RegistrySetting "$HkcuCurrentVerion\Themes\Personalize" "EnableTransparency" 0 "Int32" "Transparency Effects"
Test-RegistrySetting "$HkcuCurrentVerion\Explorer\Advanced" "TaskbarAnimations" 0 "Int32" "Taskbar Animations"
Test-RegistrySetting "$HkcuDirectX\UserGpuPreferences" "DirectXUserGlobalSettings" "VRROptimizeEnable=0;SwapEffectUpgradeEnable=1" "String" "Windowed Game Optimizations"

# Privacy & Tracking
Test-RegistrySetting "$HkcuCurrentVerion\AdvertisingInfo" "Enabled" 0 "Int32" "Ad Tracking"
Test-RegistrySetting "$HkcuControPanel\International\User Profile" "HttpAcceptLanguageOptOut" 1 "Int32" "Language Opt-Out"

# Inking & Telemetry (Stutter Killers)
Test-RegistrySetting "$HkcuPersonalization" "RestrictImplicitTextCollection" 1 "Int32" "Inking Personalization"
Test-RegistrySetting "$HkcuPersonalization\TrainedDataStore" "HarvestContacts" 0 "Int32" "Contact Harvesting"
Test-RegistrySetting "$HkcuCurrentVerion\Diagnostics\DiagTrack" "ShowedToastAtSessionStart" 0 "Int32" "Telemetry Toast"

# --- 4. System Settings (HKLM) ---
Write-AuditLog "`n[*] Auditing Simulator Process Priorities (Image File Execution Options)..." -ForegroundColor Gray
Test-RegistrySetting "$HklmIFEO\DCS.exe\PerfOptions" "CpuPriorityClass" 3 "Int32" "DCS High Priority" $true
Test-RegistrySetting "$HklmIFEO\FlightSimulator2024.exe\PerfOptions" "CpuPriorityClass" 3 "Int32" "MSFS 2024 High Priority" $true
Test-RegistrySetting "$HklmIFEO\pi_server.exe\PerfOptions" "CpuPriorityClass" 6 "Int32" "Pimax Server Priority" $true
Test-RegistrySetting "$HklmIFEO\MOZA Cockpit.exe\PerfOptions" "CpuPriorityClass" 6 "Int32" "MOZA Cockpit Priority" $true
Test-RegistrySetting "$HklmIFEO\SimHubWPF.exe\PerfOptions" "CpuPriorityClass" 6 "Int32" "SimHub Priority" $true

Write-AuditLog "`n[*] Auditing Multimedia System Profile..." -ForegroundColor Gray
Test-RegistrySetting "$HklmSystemProfile" "NetworkThrottlingIndex" 4294967295 "UInt32" "Network Throttling Off"
Test-RegistrySetting "$HklmSystemProfile" "SystemResponsiveness" 0 "Int32" "100% CPU for Games"
Test-RegistrySetting "$HklmSystemProfile\Tasks\Games" "GPU Priority" 8 "Int32" "Multimedia GPU Priority"
Test-RegistrySetting "$HklmSystemProfile\Tasks\Games" "GPU Priority" 8 "Int32" "GPU Priority"
Test-RegistrySetting "$HklmSystemProfile\Tasks\Games" "Priority" 6 "Int32" "Task Priority (Fail-safe)"
Test-RegistrySetting "$HklmSystemProfile\Tasks\Games" "Scheduling Category" "High" "String" "Task Scheduling"
Test-RegistrySetting "$HklmSystemProfile\Tasks\Games" "SFIO Priority" "High" "String" "Disk/Network Priority"

Write-AuditLog "`n[*] Auditing System-Wide Windows Performance (HKLM)..." -ForegroundColor Gray
# 1. Connectivity & Security
Test-RegistrySetting "$HklmWindows\ConnectedDevices" "EnableCDP" 0 "Int32" "Global Share Across Devices"
Test-RegistrySetting "$HklmControl\GraphicsDrivers" "HwSchMode" 1 "Int32" "HAGS (1=Off for VR)"
Test-RegistrySetting "$HklmControl\DeviceGuard" "EnableVirtualizationBasedSecurity" 0 "Int32" "Virtualization Based Security"
Test-RegistrySetting "$HklmControl\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" "Enabled" 0 "Int32" "Core Isolation"

# 2. CPU & Priority Management
Test-RegistrySetting "$HklmControl\PriorityControl" "Win32PrioritySeparation" 38 "Int32" "Priority Quantum (38=Default)"
Test-RegistrySetting "$HklmControl\Power" "PowerThrottlingOff" 1 "Int32" "Power Throttling Disable"
Test-RegistrySetting "$HklmControl\Session Manager\Memory Management" "EnableMemoryCompression" 0 "Int32" "Memory Compression"

# 3. Background Services & USB
Test-RegistrySetting "$HklmServices\WSearch" "Start" 4 "Int32" "Windows Search Service (4=Disabled)"
Test-RegistrySetting "$HklmServices\USB" "DisableSelectiveSuspend" 1 "Int32" "Master USB Selective Suspend"

# 4. Telemetry & Windows Update
Test-RegistrySetting "$HklmCurrentVerion\Policies\DataCollection" "AllowTelemetry" 0 "Int32" "Global Telemetry"
Test-RegistrySetting "$HklmWindowsUpdate\UX\Settings" "IsContinuousBackupEnabled" 0 "Int32" "Continuous Update Reboots"
Test-RegistrySetting "$HklmCurrentVerion\DeliveryOptimization\Config" "DODownloadMode" 0 "Int32" "Update Delivery Optimization"

# Virtualization based security
Test-RegistrySetting "$HklmControl\DeviceGuard\Scenarios\WindowsHello" "Enabled" 0 "Int32" "Windows Hedllo"
# These setting were mentions for shutting off VBS but we're required - I'm leaving them here for future reference.
# $HklmControl\DeviceGuard\Scenarios\WindowsHello Enabled set to 0 reboot
# HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\CredentialGuard set to 0 reboot
# BIOS Find settings labeled Intel VT-x, AMD-V, or SVM Mode and set them to Disabled.

#Bluetooth services
Test-RegistrySetting "$HklmServices\bthserv" "Start" 4 "Int32" "Bluetooth Support Service"
Test-RegistrySetting "$HklmServices\BluetoothUserService" "Start" 4 "Int32" "Bluetooth User Service"
Test-RegistrySetting "$HklmServices\BTAGService" "Start" 4 "Int32" "Bluetooth Audio Gateway Service"
Test-RegistrySetting "$HklmPolicyManager\default\Connectivity\AllowBluetooth" "value" 0 "Int32" "Bluetooth Windows Policy"


Write-AuditLog "Registry Audit Complete.`n" -ForegroundColor Cyan
