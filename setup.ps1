<#
.SYNOPSIS
  Unlocks Windows Firewall on locked-down PC bang machines and launches dropship.

.DESCRIPTION
  Some PC bang disk images ship with mpssvc (Windows Defender Firewall service)
  in a configuration where:
    - Service is set to Disabled (Start = 4)
    - The service object DACL has DC (CHANGE_CONFIG) and WP (STOP) stripped
      from the BUILTIN\Administrators ACE
    - All firewall profiles have EnableFirewall = 0
    - SCM caches the disabled state at boot

  This blocks tools like dropship that need INetFwPolicy2 to answer.

  This script restores the minimum needed for dropship to function:
    1. Rewrites mpssvc DACL back to Windows defaults (uses leftover WD bit)
    2. Calls sc config to update both the registry and SCM's in-memory cache
    3. Starts mpssvc (mpsdrv kernel driver auto-loads as a dependency)
    4. Enables firewall on whichever profile is currently active
    5. Downloads dropship.exe (if not present) and launches it

  All changes are non-persistent. The cafe's disk image resets on reboot.

.NOTES
  Requires Administrator. Idempotent. Safe to run multiple times.

  Known weirdness on these machines: Task Manager crashes with an empty white
  window once mpssvc is running. Cause unknown (likely cafe management software
  reacting to the firewall state change). Resource Monitor / Process Explorer
  work fine as alternatives.
#>

[CmdletBinding()]
param(
    [switch]$NoLaunch,
    [string]$DropshipDir = (Join-Path $env:USERPROFILE 'dropship')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Step($n, $msg) {
    Write-Host "[$n/5] $msg" -ForegroundColor Cyan
}

function Write-Info($msg) {
    Write-Host "      $msg" -ForegroundColor DarkGray
}

function Write-Ok($msg) {
    Write-Host "      $msg" -ForegroundColor Green
}

# ---------- Step 0: admin check ----------
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: Administrator privileges required." -ForegroundColor Red
    Write-Host "Re-launch PowerShell as Administrator and try again." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "blue-pcbang-dropship setup" -ForegroundColor White
Write-Host "===========================" -ForegroundColor White
Write-Host ""

# ---------- Step 1: DACL ----------
Write-Step 1 "Restore mpssvc service DACL (grant DC/WP/SD to Administrators)"

# Standard Windows default DACL: BA gets full standard control.
# The cafe image strips DC/WP/DT/SD from BA but leaves WD (WRITE_DAC) intact,
# which is the only reason this rewrite is possible without elevation tricks.
$standardSDDL = 'D:(A;;CCLCLORC;;;AU)(A;;CCDCLCSWRPLORCWDWO;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCLO;;;BU)S:(AU;FA;CCDCLCSWRPWPDTLOSDRCWDWO;;;WD)'
$currentSDDL = (& sc.exe sdshow mpssvc | Out-String).Trim()
if ($currentSDDL -eq $standardSDDL) {
    Write-Info "DACL already at Windows defaults"
} else {
    $r = & sc.exe sdset mpssvc $standardSDDL 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "sdset failed (exit $LASTEXITCODE): $r"
    }
    Write-Ok "DACL restored"
}

# ---------- Step 2: config refresh ----------
Write-Step 2 "Set mpssvc start type to Manual (refreshes SCM cache)"

$r = & sc.exe config mpssvc start= demand 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    throw "sc config failed (exit $LASTEXITCODE): $r"
}
Write-Ok "Start type = Manual"

# ---------- Step 3: start service ----------
Write-Step 3 "Start mpssvc"

$svc = Get-Service -Name mpssvc
if ($svc.Status -eq 'Running') {
    Write-Info "Already running"
} else {
    Start-Service -Name mpssvc
    (Get-Service -Name mpssvc).WaitForStatus('Running', '00:00:30')
    Write-Ok "mpssvc running"
}

# ---------- Step 4: enable active profile ----------
Write-Step 4 "Enable firewall on active network profile"

$active = Get-NetConnectionProfile | Select-Object -First 1
if (-not $active) {
    Write-Info "No active network. Skipping profile enable."
} else {
    $psProfile = switch ($active.NetworkCategory) {
        'Public'              { 'Public' }
        'Private'             { 'Private' }
        'DomainAuthenticated' { 'Domain' }
        default               { throw "Unknown network category: $($active.NetworkCategory)" }
    }
    Write-Info "Active profile: $psProfile (network: $($active.Name))"

    $current = Get-NetFirewallProfile -Name $psProfile
    if ($current.Enabled -eq 'True') {
        Write-Info "Already enabled"
    } else {
        Set-NetFirewallProfile -Name $psProfile -Enabled True
        Write-Ok "$psProfile profile enabled"
    }
}

# ---------- Step 5: download + launch dropship ----------
Write-Step 5 "Prepare dropship"

$dropshipExe = Join-Path $DropshipDir 'dropship.exe'
$dropshipUrl = 'https://github.com/stowmyy/dropship/releases/latest/download/dropship.exe'

if (-not (Test-Path $dropshipExe)) {
    if (-not (Test-Path $DropshipDir)) {
        New-Item -ItemType Directory -Path $DropshipDir -Force | Out-Null
    }
    Write-Info "Downloading: $dropshipUrl"
    try {
        Invoke-WebRequest -Uri $dropshipUrl -OutFile $dropshipExe -UseBasicParsing
    } catch {
        throw "dropship download failed: $($_.Exception.Message)"
    }
    Write-Ok "Downloaded to $dropshipExe"
} else {
    Write-Info "Already present at $dropshipExe"
}

Write-Host ""
Write-Host "Setup complete." -ForegroundColor Green
Write-Host ""

if ($NoLaunch) {
    Write-Host "  -NoLaunch flag set. dropship not launched." -ForegroundColor DarkGray
    Write-Host "  Manual launch: $dropshipExe" -ForegroundColor DarkGray
} else {
    Write-Host "Launching dropship..." -ForegroundColor White
    Start-Process -FilePath $dropshipExe
}

Write-Host ""
Write-Host "REMINDER: Before leaving this PC, revoke any GitHub tokens you authorized:" -ForegroundColor Yellow
Write-Host "  https://github.com/settings/applications" -ForegroundColor Yellow
Write-Host ""
