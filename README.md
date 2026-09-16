# windows-scripts

Meta-repozitář — kolekce obecných Windows PowerShell skriptů jako git submodulů. Žádný vlastní kód.

## Skripty

| Submodul | Popis |
|---|---|
| [Reset-RdsGracePeriod](https://github.com/dnemecek/Reset-RdsGracePeriod) | Reset RDS grace period pokud je pod prahem |
| [uninstall-msipackage](https://github.com/dnemecek/uninstall-msipackage) | Výpis, interaktivní výběr a odinstalace MSI balíčků, úklid asociací a zástupců |
| [set-remoteapp-workspace](https://github.com/dnemecek/set-remoteapp-workspace) | Přihlášení / odhlášení / výpis RemoteApp and Desktop Connections feedu (per-user) |

## Stažení všech skriptů

```bash
git clone --recurse-submodules https://github.com/dnemecek/windows-scripts.git
```

## Git na klientovi (Windows 10/11)

```
winget install --id Git.Git -e --source winget
```

Po instalaci znovu otevřít CMD (PATH), pak `git clone --recurse-submodules …` výše.

Bez gitu: ZIP z GitHubu **neobsahuje submoduly** — `common/` i složky skriptů by byly
prázdné. Stáhnout ZIP každého repa zvlášť (skript + `ps-common` do `common/`), nebo
naklonovat jednou na admin stroji a na klienty nést hotovou složku.

## Aktualizace

```bash
git pull && git submodule update --remote
```

## Autor

David Němeček
