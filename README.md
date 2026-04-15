# blue-pcbang-dropship

One-click setup script for running [dropship](https://github.com/stowmyy/dropship)
(Overwatch 2 server selector) at a specific PC bang chain whose disk image
disables Windows Firewall in a way that breaks dropship's firewall queries.

## What's broken at this cafe

The cafe ships an image where:

- `mpssvc` (Windows Defender Firewall service) is set to **Disabled**
- The service object's DACL has `CHANGE_CONFIG` and `STOP` rights stripped
  from the Administrators ACE
- All firewall profiles have `EnableFirewall = 0`

This makes dropship crash with `failed to query firewall state for network
profile` because its `INetFwPolicy2::get_FirewallEnabled()` call has nothing
to talk to.

The leftover `WRITE_DAC` bit on the DACL is the foothold this script uses
to grant Administrators back the missing rights, refresh SCM's cached config,
and start the service.

## Usage

```powershell
# Clone
git clone https://github.com/<user>/blue-pcbang-dropship.git
cd blue-pcbang-dropship

# Run as Administrator
powershell -ExecutionPolicy Bypass -File .\setup.ps1
```

The script:

1. Restores the mpssvc service DACL to Windows defaults
2. Forces an SCM cache refresh via `sc config`
3. Starts mpssvc (mpsdrv loads as a dependency)
4. Enables firewall on the currently-active network profile only
5. Downloads `dropship.exe` (if missing) and launches it

Idempotent — safe to run multiple times. All changes are non-persistent and
reset on the cafe machine's next boot (it uses a disk-restore image).

## Flags

- `-NoLaunch` — apply fixes and download dropship but don't launch it
- `-DropshipDir <path>` — install dropship to a custom path (default
  `$env:USERPROFILE\dropship`)

## Known issues

- **Task Manager crashes** once `mpssvc` is running on this image. Cause
  unknown (likely the cafe's management software). Use Process Explorer or
  `Get-Process` instead.
- **Only works on this specific cafe.** Other cafes lock things down
  differently. See `SKILL.md` "Diagnostic order" section for how to identify
  whether you're at the right cafe and how to adapt if not.

## Security

- The script is ~150 lines, all local actions, no network calls except
  downloading dropship.exe from its official GitHub release. Read it before
  running.
- If you authenticate any CLI tools (`gh`, `git credential`, etc.) at the
  cafe, **revoke the tokens before leaving**:
  <https://github.com/settings/applications>
- The cafe may consider this a TOS violation. Use judgment.

## Why this exists

Mostly so I (and Claude, when I ask it next time) don't have to re-derive
the unlock procedure from scratch every visit. See `SKILL.md` for the
detailed background — it's structured as a Claude Code skill but is also
just human-readable documentation.

## License

Public domain / unlicensed. Do whatever.
