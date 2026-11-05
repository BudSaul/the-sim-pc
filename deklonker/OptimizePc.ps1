# 1. Run as Admin Check
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Restarting with Admin permissions..." -ForegroundColor Yellow
    Start-Process pwsh.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Set-Location $PSScriptRoot

# 2. BCDEDIT Tweaks (System Latency)
Write-Host "Disabling Dynamic Tick..." -ForegroundColor Cyan
bcdedit /set disabledynamictick yes | Out-Null

Write-Host "Disabling HPET (High Precision Event Timer)..." -ForegroundColor Cyan
# Try/Catch handles the "Element not found" error silently if already deleted
try { bcdedit /deletevalue useplatformclock | Out-Null } catch { }

# 3. NVIDIA Optimizations
if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
    Write-Host "Turning on NVIDIA persistence mode..." -ForegroundColor Cyan
    # Note: Some GeForce cards may report this as unsupported; error is suppressed
    nvidia-smi -pm 1 2>$null
}

# 4. Network Cleanup
Write-Host "Flushing DNS Cache..." -ForegroundColor Cyan
Clear-DnsClientCache

# 5. Kill Unwanted Processes
$procsToKill = @("brave", "Discord", "MicrosoftEdgeUpdate", "SearchIndexer")
foreach ($proc in $procsToKill) {
    if (Get-Process -Name $proc -ErrorAction SilentlyContinue) {
        Stop-Process -Name $proc -Force -ErrorAction SilentlyContinue
        Write-Host "$proc killed." -ForegroundColor Gray
    }
}

# 6. Stop and Disable Persistent Services
# Combining both lists for efficiency
$servicesToStop = @(
    "AMD Crash Defender Service",
    "AMD External Events Utility",
    "DiagTrack",     # Telemetry
    "TrkWks",        # Distributed Link Tracking
    "lfsvc",         # Geolocation
    "iphlpsvc",      # IP Helper
    "PhoneSvc",      # Phone Service
    "Spooler",       # Print Spooler
    "SysMain",       # Superfetch/Prefetch
    "PcaSvc",        # Compatibility Assistant
    "WSearch",       # Windows Search
    "UsoSvc",        # Update Orchestrator
    "wuauserv",      # Windows Update
    "WMPNetworkSvc", # Media Player Sharing
    "WMPNetwk"       # Media Player Alias
)

foreach ($svcName in $servicesToStop) {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($svc) {
        Write-Host "Stopping and Disabling: $svcName" -ForegroundColor Cyan
        # Set to disabled first so it doesn't restart
        Set-Service -Name $svcName -StartupType Disabled -ErrorAction SilentlyContinue
        # Force stop the service and its dependencies
        if ($svc.Status -ne 'Stopped') {
            Stop-Service -Name $svcName -Force -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
}

Write-Host "`nAll VR Optimizations Applied! Remember to REBOOT for BCD/Registry changes." -ForegroundColor Green
