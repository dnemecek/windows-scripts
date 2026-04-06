# windows-scripts

Obecné Windows PowerShell skripty. Ansible-ready, GPO-ready (dual-ready standard).

## Struktura

Ke každému `.ps1` skriptu existuje `.cmd` launcher pro snadné spuštění z CMD s `ExecutionPolicy Bypass` a předáním parametrů přes `%*`.

## Skripty

| Skript | Popis |
|---|---|
| `Reset-RdsGracePeriod` | Reset RDS grace period pokud je pod prahem. Podporuje `-Status`, `-DryRun`, `-DisableLicenseNotification`. |

## Použití

```powershell
# Zjisteni stavu
.\Reset-RdsGracePeriod.ps1 -Status

# Simulace bez zmen
.\Reset-RdsGracePeriod.ps1 -DryRun -Force -GraceThreshold 90

# Reset
.\Reset-RdsGracePeriod.ps1 -Force

# Pres CMD launcher
Reset-RdsGracePeriod.cmd -Force -Verbose
```

## Výstup

Všechny skripty produkují JSON na stdout (kompatibilní s Ansible):

```json
{"changed":true,"reboot_required":true,"status":"reset_done","msg":"Grace period reset to 120 days"}
```

Logování do souboru (výchozí: `C:\Windows\Logs\<ScriptName>.log`), nikdy na stdout.

## Autor

David Němeček
