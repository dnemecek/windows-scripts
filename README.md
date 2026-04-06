# windows-scripts

General-purpose Windows PowerShell scripts. Ansible-ready, GPO-ready (dual-ready standard).

## Structure

Every `.ps1` script has a matching `.cmd` launcher for easy execution from CMD with `ExecutionPolicy Bypass` and parameter passthrough (`%*`).

## Scripts

| Script | Description |
|---|---|
| `Reset-RdsGracePeriod` | Reset RDS grace period when below threshold. Supports `-Status`, `-DryRun`, `-DisableLicenseNotification`. |

## Usage

```powershell
# Status check
.\Reset-RdsGracePeriod.ps1 -Status

# Dry run
.\Reset-RdsGracePeriod.ps1 -DryRun -Force -GraceThreshold 90

# Reset
.\Reset-RdsGracePeriod.ps1 -Force

# Via CMD launcher
Reset-RdsGracePeriod.cmd -Force -Verbose
```

## Output

All scripts produce JSON on stdout (Ansible-compatible):

```json
{"changed":true,"reboot_required":true,"status":"reset_done","msg":"Grace period reset to 120 days"}
```

Logging goes to file only (default: `C:\Windows\Logs\<ScriptName>.log`), never to stdout.

## Author

David Nemecek
