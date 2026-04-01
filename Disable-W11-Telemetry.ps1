# =============================================================================
# Windows 11 Telemetry Reduction & Privacy improvement Script
# Version 2.0
# =============================================================================
# Covers:
#   1.  Diagnostic data registry keys
#   2.  Group Policy telemetry key
#   3.  Telemetry services
#   4.  Telemetry scheduled tasks
#   5.  Advertising ID
#   6.  Windows Error Reporting
#   7.  Cortana & Search cloud features
#   8.  Activity History / Timeline
#   9.  Tailored Experiences
#  10.  Inking & Typing personalization
#  11.  App diagnostics
#  12.  Feedback notifications
#  13.  Cloud Clipboard sync
#  14.  Microsoft Edge telemetry
#  15.  Delivery Optimization (P2P upload limits)
#  16.  Hosts-file block of known telemetry endpoints (optional)
#  17.  Summary report + transcript log
# =============================================================================

#region ── Bootstrap ──────────────────────────────────────────────────────────

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Warning "Please run PowerShell as Administrator."
    exit 1
}

# Start a transcript so every action is saved to disk
$LogPath = "$env:SystemDrive\Logs\TelemetryReduction_$(Get-Date -f 'yyyyMMdd_HHmmss').log"
$null = New-Item -Path (Split-Path $LogPath) -ItemType Directory -Force
Start-Transcript -Path $LogPath -Append | Out-Null

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   Windows 11 Telemetry Reduction  v2.0                   ║" -ForegroundColor Cyan
Write-Host "║   Log → $LogPath   ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Counters for the final summary
$Script:PassCount = 0
$Script:FailCount = 0

#endregion

#region ── Helper Functions ───────────────────────────────────────────────────

function Set-RegValue {
    <#
    .SYNOPSIS  Creates the registry path if missing, then writes the value.
    .PARAMETER Path   Full HKLM:/HKCU: registry path.
    .PARAMETER Name   Value name.
    .PARAMETER Value  Data to write.
    .PARAMETER Type   Registry type (default DWord).
    #>
    param(
        [string]$Path,
        [string]$Name,
        $Value,
        [string]$Type = "DWord"
    )
    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
        Write-Host "  [OK] $Path\$Name = $Value"
        $Script:PassCount++
    }
    catch {
        Write-Warning "  [FAIL] $Path\$Name — $_"
        $Script:FailCount++
    }
}

function Disable-ScheduledTaskSafe {
    param([string]$TaskPath)
    try {
        $t = Get-ScheduledTask -TaskPath (Split-Path $TaskPath) `
                               -TaskName  (Split-Path $TaskPath -Leaf) `
                               -ErrorAction Stop
        Disable-ScheduledTask -InputObject $t | Out-Null
        Write-Host "  [OK] Task disabled: $TaskPath"
        $Script:PassCount++
    }
    catch {
        Write-Warning "  [SKIP] Task not found or already disabled: $TaskPath"
        # Not counted as failure — task may not exist on this edition
    }
}

function Disable-ServiceSafe {
    param([string]$Name)
    try {
        Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
        Set-Service  -Name $Name -StartupType Disabled -ErrorAction Stop
        Write-Host "  [OK] Service disabled: $Name"
        $Script:PassCount++
    }
    catch {
        Write-Warning "  [SKIP] Service not found: $Name"
    }
}

#endregion

# =============================================================================
# 1. Diagnostic Data (AllowTelemetry / DisableTelemetry)
# =============================================================================
Write-Host "`n[1] Diagnostic Data Registry Keys" -ForegroundColor Yellow

$diagKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"
Set-RegValue $diagKey "AllowTelemetry"       0
Set-RegValue $diagKey "MaxTelemetryAllowed"  0
Set-RegValue $diagKey "DisableTelemetry"     1

# =============================================================================
# 2. Group Policy Equivalent (DataCollection)
# =============================================================================
Write-Host "`n[2] Group Policy — DataCollection" -ForegroundColor Yellow

$gpKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
Set-RegValue $gpKey "AllowTelemetry"                  0
Set-RegValue $gpKey "DisableOneSettingsDownloads"     1
Set-RegValue $gpKey "DoNotShowFeedbackNotifications"  1
Set-RegValue $gpKey "LimitDiagnosticLogCollection"    1
Set-RegValue $gpKey "DisableDiagnosticDataViewer"     1

# =============================================================================
# 3. Telemetry Services
# =============================================================================
Write-Host "`n[3] Telemetry Services" -ForegroundColor Yellow

@(
    "DiagTrack",                           # Connected User Experiences & Telemetry
    "dmwappushservice",                    # Device Management WAP Push
    "PcaSvc",                              # Program Compatibility Assistant
    "WerSvc",                              # Windows Error Reporting
    "wercplsupport"                        # Problem Reports Control Panel Support
) | ForEach-Object { Disable-ServiceSafe $_ }

# =============================================================================
# 4. Scheduled Tasks
# =============================================================================
Write-Host "`n[4] Scheduled Tasks" -ForegroundColor Yellow

@(
    # CEIP
    "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator"
    "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip"
    "\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask"
    # Application Experience
    "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser"
    "\Microsoft\Windows\Application Experience\ProgramDataUpdater"
    "\Microsoft\Windows\Application Experience\StartupAppTask"
    # Autochk
    "\Microsoft\Windows\Autochk\Proxy"
    # DiskDiagnostic
    "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector"
    # Feedback
    "\Microsoft\Windows\Feedback\Siuf\DmClient"
    "\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload"
    # Maintenance
    "\Microsoft\Windows\Maintenance\WinSAT"
    # Maps
    "\Microsoft\Windows\Maps\MapsToastTask"
    "\Microsoft\Windows\Maps\MapsUpdateTask"
    # NetTrace
    "\Microsoft\Windows\NetTrace\GatherNetworkInfo"
    # WER
    "\Microsoft\Windows\Windows Error Reporting\QueueReporting"
) | ForEach-Object { Disable-ScheduledTaskSafe $_ }

# =============================================================================
# 5. Advertising ID
# =============================================================================
Write-Host "`n[5] Advertising ID" -ForegroundColor Yellow

Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" `
             "Enabled" 0

# Also disable via policy so new user profiles inherit it
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" `
             "DisabledByGroupPolicy" 1

# =============================================================================
# 6. Windows Error Reporting
# =============================================================================
Write-Host "`n[6] Windows Error Reporting" -ForegroundColor Yellow

Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" `
             "Disabled" 1
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" `
             "Disabled" 1
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" `
             "DontSendAdditionalData" 1

# =============================================================================
# 7. Cortana & Search Cloud Features
# =============================================================================
Write-Host "`n[7] Cortana & Search Cloud Features" -ForegroundColor Yellow

Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" `
             "AllowCortana" 0
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" `
             "AllowCloudSearch" 0
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" `
             "AllowSearchToUseLocation" 0
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" `
             "ConnectedSearchUseWeb" 0
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" `
             "DisableWebSearch" 1
# Disable search highlights / dynamic content in taskbar search box
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" `
             "EnableDynamicContentInWSB" 0

# =============================================================================
# 8. Activity History (Timeline)
# =============================================================================
Write-Host "`n[8] Activity History / Timeline" -ForegroundColor Yellow

Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" `
             "EnableActivityFeed" 0
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" `
             "PublishUserActivities" 0
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" `
             "UploadUserActivities" 0

# =============================================================================
# 9. Tailored Experiences
# =============================================================================
Write-Host "`n[9] Tailored Experiences" -ForegroundColor Yellow

Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" `
             "TailoredExperiencesWithDiagnosticDataEnabled" 0
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" `
             "DisableTailoredExperiencesWithDiagnosticData" 1
# Disable Windows tips and consumer features (Start menu suggestions, etc.)
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" `
             "DisableWindowsConsumerFeatures" 1
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" `
             "DisableSoftLanding" 1

# =============================================================================
# 10. Inking & Typing Personalization
# =============================================================================
Write-Host "`n[10] Inking & Typing Personalization" -ForegroundColor Yellow

Set-RegValue "HKCU:\Software\Microsoft\InputPersonalization" `
             "RestrictImplicitInkCollection" 1
Set-RegValue "HKCU:\Software\Microsoft\InputPersonalization" `
             "RestrictImplicitTextCollection" 1
Set-RegValue "HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore" `
             "HarvestContacts" 0
Set-RegValue "HKCU:\Software\Microsoft\Personalization\Settings" `
             "AcceptedPrivacyPolicy" 0

# =============================================================================
# 11. App Diagnostics Permission
# =============================================================================
Write-Host "`n[11] App Diagnostics" -ForegroundColor Yellow

Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\appDiagnostics" `
             "Value" "Deny" -Type String

# =============================================================================
# 12. Feedback Notifications
# =============================================================================
Write-Host "`n[12] Feedback Notifications" -ForegroundColor Yellow

Set-RegValue "HKCU:\Software\Microsoft\Siuf\Rules" "NumberOfSIUFInPeriod" 0
Set-RegValue "HKCU:\Software\Microsoft\Siuf\Rules" "PeriodInNanoSeconds"  0
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
             "DoNotShowFeedbackNotifications" 1

# =============================================================================
# 13. Cloud Clipboard Sync
# =============================================================================
Write-Host "`n[13] Cloud Clipboard Sync" -ForegroundColor Yellow

Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" `
             "AllowCrossDeviceClipboard" 0
Set-RegValue "HKCU:\Software\Microsoft\Clipboard" `
             "EnableCloudClipboard" 0

# =============================================================================
# 14. Microsoft Edge Telemetry
# =============================================================================
Write-Host "`n[14] Microsoft Edge Telemetry" -ForegroundColor Yellow

$edgePolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
Set-RegValue $edgePolicy "MetricsReportingEnabled"         0
Set-RegValue $edgePolicy "SendSiteInfoToImproveServices"   0
Set-RegValue $edgePolicy "DiagnosticData"                  0   # 0 = off, 1 = required only
Set-RegValue $edgePolicy "PersonalizationReportingEnabled" 0
Set-RegValue $edgePolicy "EdgeCollectTextAndInkLogs"       0

# =============================================================================
# 15. Delivery Optimization (limit outbound P2P uploads)
# =============================================================================
Write-Host "`n[15] Delivery Optimization" -ForegroundColor Yellow

# DODownloadMode: 0=off, 1=LAN only, 2=LAN+Internet, 3=HTTP only
# Setting 1 keeps fast local downloads while stopping Internet uploads
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" `
             "DODownloadMode" 1
# Cap monthly upload to 1 GB (value in GB)
Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" `
             "DOMonthlyUploadDataCap" 1

# =============================================================================
# 16. (Optional) Hosts-file Telemetry Endpoint Blocking
# =============================================================================
Write-Host "`n[16] Hosts-file Telemetry Blocking" -ForegroundColor Yellow

$telemetryHosts = @(
    "vortex.data.microsoft.com"
    "vortex-win.data.microsoft.com"
    "telecommand.telemetry.microsoft.com"
    "telecommand.telemetry.microsoft.com.nsatc.net"
    "oca.telemetry.microsoft.com"
    "oca.telemetry.microsoft.com.nsatc.net"
    "sqm.telemetry.microsoft.com"
    "sqm.telemetry.microsoft.com.nsatc.net"
    "watson.telemetry.microsoft.com"
    "watson.telemetry.microsoft.com.nsatc.net"
    "redir.metaservices.microsoft.com"
    "choice.microsoft.com"
    "choice.microsoft.com.nsatc.net"
    "df.telemetry.microsoft.com"
    "reports.wes.df.telemetry.microsoft.com"
    "wes.df.telemetry.microsoft.com"
    "services.wes.df.telemetry.microsoft.com"
    "sqm.df.telemetry.microsoft.com"
    "telemetry.microsoft.com"
    "watson.ppe.telemetry.microsoft.com"
    "settings-sandbox.data.microsoft.com"
    "v10-win.vortex.data.microsoft.com"
    "v10.vortex-win.data.microsoft.com"
    "v20.events.data.microsoft.com"
    "self.events.data.microsoft.com"
)

$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$existing  = Get-Content $hostsPath -Raw

$added = 0
foreach ($host in $telemetryHosts) {
    if ($existing -notmatch [regex]::Escape($host)) {
        Add-Content -Path $hostsPath -Value "0.0.0.0`t$host"
        $added++
        $Script:PassCount++
    }
}
if ($added -gt 0) {
    Write-Host "  [OK] Added $added telemetry hosts to $hostsPath"
} else {
    Write-Host "  [OK] All telemetry hosts already present in hosts file"
}

# Flush DNS so blocks take effect immediately
ipconfig /flushdns | Out-Null
Write-Host "  [OK] DNS cache flushed"

# =============================================================================
# 17. Summary
# =============================================================================
Write-Host ""
Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                   SUMMARY                    ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host ("║  ✔  Passed : {0,-32}║" -f $Script:PassCount)  -ForegroundColor Green
Write-Host ("║  ✘  Failed : {0,-32}║" -f $Script:FailCount)  -ForegroundColor $(if ($Script:FailCount -gt 0) {"Red"} else {"Green"})
Write-Host "╚══════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "Log saved to: $LogPath" -ForegroundColor DarkGray
Write-Host ""
Write-Host "A system REBOOT is required for all changes to take effect." -ForegroundColor Yellow
Write-Host ""

Stop-Transcript | Out-Null
