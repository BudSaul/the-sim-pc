# SystemAudit.ps1 - DCS/MSFS VR Optimization Audit
# Run this in an Elevated (Admin) PowerShell window

Write-Host "Auditing Windows Settings" -ForegroundColor Cyan

# 1. Check Platform Clock (HPET vs TSC)
$bcd = bcdedit /enum | Out-String
if ($bcd -match 'useplatformclock\s+Yes') {
    Write-Host 'WARNING: useplatformclock is ENABLED. This can cause VR stutters.' -ForegroundColor Yellow
} else {
    Write-Host 'SUCCESS: useplatformclock is Disabled (System using TSC).' -ForegroundColor Green
}

# 2. Verify Dynamic Tick
if ($bcd -like '*disabledynamictick*Yes*') {
    Write-Host 'SUCCESS: Dynamic Tick Disabled.' -ForegroundColor Green
} else {
    Write-Host 'WARNING: Dynamic Tick is Enabled (Power Saving Active).' -ForegroundColor Yellow
}

# 3. Audit Virtualization-Based Security (VBS)
try {
    $vbs = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace 'root\Microsoft\Windows\DeviceGuard' -ErrorAction Stop
    if ($vbs.VirtualizationBasedSecurityStatus -eq 0) {
        Write-Host 'SUCCESS: Virtualization-Based Security (VBS) is Disabled.' -ForegroundColor Green
    } else {
        Write-Host 'WARNING: VBS is RUNNING. This can cause VR micro-stutters.' -ForegroundColor Yellow
    }
} catch {
    Write-Host 'INFO: Could not audit VBS (Class not found).' -ForegroundColor Gray
}

# 4. Audit for active Bluetooth Radios
$bt = Get-PnpDevice -Class Bluetooth -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'OK' }
if ($bt) {
    Write-Host 'WARNING: Bluetooth is ENABLED. This can cause VR stutters.' -ForegroundColor Yellow
    foreach ($d in $bt) {
        Write-Host ("   [!] " + $d.FriendlyName) -ForegroundColor Yellow
    }
} else {
    Write-Host 'SUCCESS: Bluetooth is Disabled or No Radios found.' -ForegroundColor Green
}

# 5. Check NVIDIA GPU Performance State (P0 = Max)
# Note: P8 is the normal state unless an app requiring the performance is required - this can be ignored
if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
    $pstate = nvidia-smi --query-gpu=pstate --format=csv,noheader
    if ($pstate -eq 'P0') {
        Write-Host 'SUCCESS: GPU is in Max Performance state (P0).' -ForegroundColor Green
    } else {
        Write-Host "WARNING: GPU is in state $pstate (Expected P0). Check NVIDIA Power Settings." -ForegroundColor Yellow
    }
} else {
    Write-Host 'INFO: nvidia-smi not found. Skipping GPU state check.' -ForegroundColor Gray
}

Write-Host "Windows Audit Complete.`n" -ForegroundColor Cyan
