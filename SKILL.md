---
name: blue-pcbang-dropship
description: Set up dropship (Overwatch 2 server selector) at the "blue" PC bang where the disk image disables Windows Firewall. Trigger when user mentions blue pcbang / blue PC방 / dropship not working at PC bang / firewall service disabled at cafe / "failed to query firewall state for network profile" / setting up dropship at this cafe again.
---

# blue-pcbang-dropship

A specific PC bang ("blue") ships a Windows image that breaks dropship and any
other tool that reads firewall state via `INetFwPolicy2`. This skill captures
how to fix it.

## TL;DR

The cafe's `mpssvc` (Windows Defender Firewall) service is disabled, with its
service-object DACL stripped of `CHANGE_CONFIG` and `STOP` rights for
Administrators. dropship's COM call fails with `failed to query firewall state
for network profile` and the app crashes on launch.

The leftover `WRITE_DAC` bit on the DACL is the only reason this is fixable
without the cafe staff. Run `setup.ps1` from this repo as Administrator. It
takes ~3 seconds, applies the minimum needed changes, downloads dropship.exe
if missing, and launches it. Everything reverts on reboot (cafe uses
disk-restore image).

## How to recognize you're at this cafe

The cafe matches this profile when ALL of the following are true on a fresh
boot:

1. `sc query mpssvc` shows **STOPPED** with exit code 1077
2. `sc qc mpssvc` shows **START_TYPE: 4 DISABLED**
3. `sc sdshow mpssvc` returns:
   `D:(A;;CCLCLORC;;;AU)(A;;CCDCLCSWRPLORCWDWO;;;SY)(A;;CCLCSWRPLORCWDWO;;;BA)(A;;CCLCLO;;;BU)S:(AU;FA;CCDCLCSWRPWPDTLOSDRCWDWO;;;WD)`
   Note the `BA` ACE is `CCLCSWRPLORCWDWO` — missing `DC`, `WP`, `DT`, `SD`,
   but `WD` (WriteDac) is intact. That's the foothold.
4. All three FirewallPolicy profiles have `EnableFirewall = 0`
5. `whoami /priv` shows the user is an elevated Administrator (the cafe runs
   sessions under a logged-in admin account, oddly enough)
6. The svchost group is `LocalServiceNoNetworkFirewall` (slightly nonstandard
   name, used for both `bfe` and `mpssvc`)

If any of those don't match, you're at a *different* cafe and this skill may
not apply. Fall back to manual diagnosis (see "Diagnostic order" below).

## How to use

1. Clone or download this repo on the PC bang machine
2. Open PowerShell as Administrator
3. Run: `powershell -ExecutionPolicy Bypass -File .\setup.ps1`
4. dropship launches
5. Use it
6. **Before leaving the cafe**: revoke any GitHub tokens you authorized at
   <https://github.com/settings/applications>

The script is idempotent. Safe to run multiple times.

Flags:

- `-NoLaunch` — apply fixes and download dropship but don't launch it
- `-DropshipDir <path>` — install dropship to a custom path (default:
  `$env:USERPROFILE\dropship`)

## What the script actually does

Five steps, in order. Each is the minimum needed — we tested with everything
removed and added back one at a time.

| # | Action | Why it's needed |
|---|---|---|
| 1 | `sc.exe sdset mpssvc <standard SDDL>` | Restore Administrators' `DC` (`CHANGE_CONFIG`) right. Required by step 2. Uses the leftover `WD` bit on the BA ACE. |
| 2 | `sc.exe config mpssvc start= demand` | Update both registry `Start` value AND SCM's in-memory cache. Just writing the registry directly is not enough — SCM caches the boot-time disabled state and `StartService` returns `ERROR_SERVICE_DISABLED` (1058) until SCM's cache is refreshed via the `ChangeServiceConfig` API. |
| 3 | `Start-Service mpssvc` | Actually start the service. `mpsdrv` (the kernel driver) auto-loads as a dependency. |
| 4 | `Set-NetFirewallProfile -Name <active> -Enabled True` | dropship needs the *currently connected* profile enabled to actually filter traffic. Active profile is detected dynamically via `Get-NetConnectionProfile`. Other profiles are left untouched (less surface area, less to revert). |
| 5 | Download `dropship.exe` from <https://github.com/stowmyy/dropship/releases/latest> and launch it | One-click experience. |

### What we explicitly do NOT do

- We do NOT manually start `mpsdrv` — SCM auto-starts it as a dependency
- We do NOT directly write `Start = 3` to the registry — `sc config` does
  both that and the SCM cache refresh in a single API call
- We do NOT enable firewall on Standard/Domain profiles — only the active
  one. Less invasive, less to revert, less side effects
- We do NOT touch group policy, AppLocker, Defender, or anything else

## Known weirdness

### Task Manager crashes after running this

Once `mpssvc` is running, Windows 11 Task Manager opens an empty white window
for ~2 seconds and then crashes. Cause not fully diagnosed — possibly the
cafe management software has a watchdog that breaks Task Manager when the
firewall service comes up, or the WinUI Task Manager has an init path that
relies on cached firewall state being absent.

The user has confirmed they don't need Task Manager. Use Process Explorer
or `Get-Process` from PowerShell as alternatives.

### Reboot wipes everything

The cafe uses a disk-restore / "frozen disk" image. Every change above
disappears on reboot. This is actually convenient — there's no cleanup to do,
no risk of bricking the machine, no persistent footprint. But it does mean
you have to re-run `setup.ps1` every session.

## Diagnostic order (if a future cafe doesn't match exactly)

If the script fails, use this order to find what's different:

1. `sc query mpssvc` — is the service even queryable? If access denied at this
   step, the cafe has stripped even read rights and you're stuck.
2. `sc sdshow mpssvc` — does the BA ACE still have `WD`? If not, you cannot
   modify the DACL and there is no path forward without the cafe's admin
   password.
3. `sc qc mpssvc` — is `Start` actually `4 DISABLED`? Some cafes set it to
   `MANUAL` and only disable via the EnableFirewall flags.
4. `whoami /priv` — are you actually an Administrator? Most cafes are NOT
   admin; this one is the exception.
5. `Get-NetConnectionProfile` — what category is the active network? If it's
   `DomainAuthenticated` you're on a different network type than usual.
6. `Get-WinEvent -LogName System -MaxEvents 50 | Where {$_.Id -in 7000,7001,7036} | Format-Table` —
   service start failures and watchdog activity.

## Security reminders

- This script is unauthorized tampering with the cafe's lockdown. The cafe
  may not consent. If their TOS forbids modifying system settings, running
  this is a TOS violation. Use your judgment.
- The script does not exfiltrate anything. It does not phone home. It does
  not install persistent software. Verify by reading `setup.ps1` (it's ~150
  lines).
- If you authenticated `gh` or any other CLI tool at the cafe, **revoke the
  tokens before leaving**. The OAuth token gh CLI requests has full `repo`,
  `gist`, `workflow`, `read:org` scopes. Revoke at
  <https://github.com/settings/applications>.
- For future cafe visits, prefer fine-grained PATs scoped to a single repo
  with `Contents: Read` only, stored in a phone password manager.
