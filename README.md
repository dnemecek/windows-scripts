# windows-scripts

Meta-repozitář — kolekce obecných Windows PowerShell skriptů jako git submodulů. Žádný vlastní kód.

## Skripty

| Submodul | Popis |
|---|---|
| [Reset-RdsGracePeriod](https://github.com/dnemecek/Reset-RdsGracePeriod) | Reset RDS grace period pokud je pod prahem |

## Stažení všech skriptů

```bash
git clone --recurse-submodules https://github.com/dnemecek/windows-scripts.git
```

## Aktualizace

```bash
git pull && git submodule update --remote
```

## Autor

David Němeček
