@echo off
REM Reset RDS Grace Period - CMD Launcher
REM Autor: David Nemecek | Duben 2026
REM
REM Pouziti:
REM   Reset-RdsGracePeriod.cmd                   - Zjisti stav a resetuje grace period
REM   Reset-RdsGracePeriod.cmd -Force            - Primo spusteni (pro Ansible)
REM   Reset-RdsGracePeriod.cmd -Force -Verbose   - S verbose vystupem do konzole
REM
REM Vyzaduje: elevated (Administrator) pristup

set "scriptPath=%~dp0"
set "scriptName=%~n0"

REM Detekce -Verbose v argumentech
set "hasVerbose=0"
for %%a in (%*) do (
    if /i "%%~a"=="-Verbose" set "hasVerbose=1"
)

REM Spusteni PowerShell scriptu (predani vsech argumentu)
REM Verbose: stderr do konzole (Write-Verbose jde pres stderr)
REM Normal:  stderr potlacen (chyby se logji do souboru pres Write-Log)
if "%hasVerbose%"=="1" (
    powershell.exe -ExecutionPolicy Bypass -NoProfile -NonInteractive -File "%scriptPath%%scriptName%.ps1" %*
) else (
    powershell.exe -ExecutionPolicy Bypass -NoProfile -NonInteractive -File "%scriptPath%%scriptName%.ps1" %* 2>nul
)
set "exitCode=%ERRORLEVEL%"

exit /b %exitCode%
