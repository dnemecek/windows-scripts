<#
.SYNOPSIS
    Reset RDS grace period na Windows Server.

.DESCRIPTION
    Zjisti zbyvajici dny RDS grace period z registry a pokud je pod prahem,
    provede reset smazanim GracePeriod klice.
    - Idempotentni: pokud dnu >= threshold, nic nedela
    - Detekce stavu "reboot pending" po resetu
    - Ansible-ready: stdout = pouze JSON, log do souboru
    - Dual-ready: spustitelny pres GPO (CMD launcher) i Ansible
    - Vyzaduje elevated (Administrator) pristup

.PARAMETER LogPath
    Cesta k log souboru. Adresar se vytvori automaticky pokud neexistuje.
    Vychozi: C:\Windows\Logs\Reset-RdsGracePeriod.log

.PARAMETER GraceThreshold
    Minimalni pocet zbyvajicich dni grace period.
    Pokud je zbyvajicich dni >= threshold, skript nic nedela.
    Vychozi: 110.

.PARAMETER NoReboot
    Potlaci reboot_required v JSON vystupu.
    Pouzij pokud reboot neni zadouci (napr. maintenance window).
    Vychozi: restart se vyzaduje vzdy po resetu.

.PARAMETER DisableLicenseNotification
    Zakaze notifikaci "No license server configured" nastavenim
    fDisableTerminalServerTooltip = 1 v registry (GPO policy klic).
    Idempotentni: pokud uz je nastaveno, nic nemeni.

.PARAMETER DryRun
    Simulace bez provedeni zmen. Zobrazi co by skript udelal.
    JSON vystup obsahuje "dry_run": true.

.PARAMETER Status
    Pouze zjisti a vypise aktualni stav grace period.
    Zadne zmeny, zadny reset. JSON vystup obsahuje "days_remaining"
    a "status" (ok / low / expired / reboot_pending).

.PARAMETER Force
    Prepinac pro prime spusteni bez potvrzeni (pro Ansible).

.EXAMPLE
    .\Reset-RdsGracePeriod.ps1 -Status

.EXAMPLE
    .\Reset-RdsGracePeriod.ps1 -DryRun -Force -GraceThreshold 90

.EXAMPLE
    .\Reset-RdsGracePeriod.ps1 -Force

.EXAMPLE
    .\Reset-RdsGracePeriod.ps1 -Force -LogPath "C:\Windows\Logs\BFMT\Reset-RdsGracePeriod.log"

.EXAMPLE
    .\Reset-RdsGracePeriod.ps1 -Force -NoReboot -DisableLicenseNotification

.NOTES
    Nazev: Reset-RdsGracePeriod.ps1
    Autor: David Nemecek
    Vytvoreno: 2026-04-06
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\Windows\Logs\Reset-RdsGracePeriod.log",

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 120)]
    [int]$GraceThreshold = 110,

    [Parameter(Mandatory = $false)]
    [switch]$NoReboot,

    [Parameter(Mandatory = $false)]
    [switch]$DisableLicenseNotification,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [switch]$Status,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

#region Script Variables
$script:StartTime = Get-Date
$script:LogFile = $LogPath
$script:GraceKeyPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\RCM\GracePeriod"
#endregion

#region Write-Log
function Write-Log {
    <#
    .SYNOPSIS
        Zapise zpravu do log souboru (nikdy na stdout).
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO'
    )

    $logFolder = Split-Path $script:LogFile -Parent
    if (-not (Test-Path $logFolder)) {
        New-Item -ItemType Directory -Path $logFolder -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $elapsed = ((Get-Date) - $script:StartTime).TotalSeconds.ToString("0.000")
    $logMessage = "[$timestamp] (+$elapsed) [$Level] $Message"

    Add-Content -Path $script:LogFile -Value $logMessage -Encoding ASCII

    # Verbose vystup na stderr (neovlivni JSON na stdout)
    Write-Verbose $logMessage
}
#endregion

#region Get-GracePeriodState
function Get-GracePeriodState {
    <#
    .SYNOPSIS
        Zjisti stav grace period. Vraci hashtable s days a status.
    .DESCRIPTION
        Stavy:
        - ok:             CIM vraci dny >= threshold
        - low:            CIM vraci dny < threshold
        - expired:        CIM vraci 0 a klic existuje
        - reboot_pending: CIM selhava a klic neexistuje (smazan, ceka na reboot)
        - unknown:        nelze zjistit
    #>
    [CmdletBinding()]
    param()

    $cimAvailable = $false
    $cimDays = -1
    $keyExists = Test-Path $script:GraceKeyPath

    # Metoda 1: CIM (nahradi deprecated Invoke-WmiMethod)
    try {
        $ts = Get-CimInstance -Namespace "root/CIMV2/TerminalServices" -ClassName Win32_TerminalServiceSetting
        $result = $ts | Invoke-CimMethod -MethodName GetGracePeriodDays
        if ($null -ne $result -and $null -ne $result.DaysLeft) {
            $cimAvailable = $true
            $cimDays = [int]$result.DaysLeft
            Write-Log "CIM GetGracePeriodDays returned $cimDays days"
        }
    }
    catch {
        Write-Log "CIM GetGracePeriodDays failed: $($_.Exception.Message)" -Level DEBUG
    }

    # Rozhodnuti o stavu
    if ($cimAvailable) {
        if ($cimDays -le 0) {
            return @{ days = 0; status = "expired" }
        }
        elseif ($cimDays -lt $GraceThreshold) {
            return @{ days = $cimDays; status = "low" }
        }
        else {
            return @{ days = $cimDays; status = "ok" }
        }
    }

    # CIM neni dostupny — fallback na registry
    Write-Log "Falling back to registry-based detection"

    if (-not $keyExists) {
        # CIM selhalo + klic neexistuje = byl smazan, ceka se na reboot
        Write-Log "CIM unavailable and GracePeriod key missing - reboot pending" -Level WARNING
        return @{ days = -1; status = "reboot_pending" }
    }

    $key = Get-Item $script:GraceKeyPath
    $valueNames = $key.GetValueNames() | Where-Object { $_ -ne "" }

    if ($valueNames.Count -eq 0) {
        Write-Log "GracePeriod key exists but empty - reboot pending" -Level WARNING
        return @{ days = -1; status = "reboot_pending" }
    }

    # Klic existuje s hodnotami, CIM nefunguje — presny pocet nezjistitelny
    Write-Log "GracePeriod key has $($valueNames.Count) value(s), CIM unavailable - days unknown" -Level WARNING
    return @{ days = 0; status = "unknown" }
}
#endregion

#region Enable-TakeOwnership
function Enable-TakeOwnership {
    <#
    .SYNOPSIS
        Aktivuje SeTakeOwnershipPrivilege pres ntdll RtlAdjustPrivilege.
    #>
    [CmdletBinding()]
    param()

    if (-not ([System.Management.Automation.PSTypeName]'Win32Api.NtDll').Type) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
namespace Win32Api
{
    public class NtDll
    {
        [DllImport("ntdll.dll", EntryPoint="RtlAdjustPrivilege")]
        public static extern int RtlAdjustPrivilege(
            ulong Privilege, bool Enable, bool CurrentThread, ref bool Enabled);
    }
}
'@
    }

    $enabled = $false
    # Privilege 9 = SeTakeOwnershipPrivilege
    $result = [Win32Api.NtDll]::RtlAdjustPrivilege(9, $true, $false, [ref]$enabled)
    if ($result -ne 0) {
        throw "RtlAdjustPrivilege failed with NTSTATUS $result"
    }
}
#endregion

#region Reset-GracePeriod
function Reset-GracePeriod {
    <#
    .SYNOPSIS
        Prevezme ownership GracePeriod klice a smaze ho.
    #>
    [CmdletBinding()]
    param()

    $regPath = "SYSTEM\CurrentControlSet\Control\Terminal Server\RCM\GracePeriod"

    # Krok 0: Aktivace SeTakeOwnershipPrivilege pres ntdll
    Write-Log "Enabling SeTakeOwnershipPrivilege via RtlAdjustPrivilege"
    Enable-TakeOwnership

    # Krok 1: Prevzeti ownership + nastaveni ACL (jeden handle, jako original)
    Write-Log "Taking ownership of GracePeriod registry key"
    $regKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
        $regPath,
        [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
        [System.Security.AccessControl.RegistryRights]::TakeOwnership
    )
    $acl = $regKey.GetAccessControl()
    $acl.SetOwner([System.Security.Principal.NTAccount]"Administrators")
    $regKey.SetAccessControl($acl)

    # Krok 2: Nastaveni FullControl pro Administrators (stejny handle)
    Write-Log "Setting FullControl ACL for Administrators"
    $rule = [System.Security.AccessControl.RegistryAccessRule]::new(
        "Administrators",
        [System.Security.AccessControl.RegistryRights]::FullControl,
        [System.Security.AccessControl.AccessControlType]::Allow
    )
    $acl.SetAccessRule($rule)
    $regKey.SetAccessControl($acl)
    $regKey.Close()

    # Krok 3: Smazani klice
    Write-Log "Deleting GracePeriod registry key to reset grace period"
    Remove-Item -Path $script:GraceKeyPath -Recurse -Force
    Write-Log "GracePeriod key deleted successfully"
}
#endregion

#region Disable-LicenseNotification
function Disable-LicenseNotification {
    <#
    .SYNOPSIS
        Zakaze RDS licensing notifikaci pres registry policy klic.
    #>
    [CmdletBinding()]
    param()

    $policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
    $valueName = "fDisableTerminalServerTooltip"

    # Idempotence: kontrola aktualniho stavu
    if (Test-Path $policyPath) {
        $current = Get-ItemProperty -Path $policyPath -Name $valueName -ErrorAction SilentlyContinue
        if ($current -and $current.$valueName -eq 1) {
            Write-Log "License notification already disabled - no change needed"
            return $false
        }
    }
    else {
        New-Item -Path $policyPath -Force | Out-Null
    }

    Set-ItemProperty -Path $policyPath -Name $valueName -Value 1 -Type DWord
    Write-Log "License notification disabled (fDisableTerminalServerTooltip = 1)"
    return $true
}
#endregion

#region Main
try {
    Write-Log "=== Reset-RdsGracePeriod started ==="

    $state = Get-GracePeriodState

    #--- Rezim: Status (jen info, zadne zmeny) ---
    if ($Status) {
        Write-Log "Status mode - reporting state only"
        $result = @{
            changed         = $false
            reboot_required = $false
            status          = $state.status
            days_remaining  = $state.days
            threshold       = $GraceThreshold
            msg             = switch ($state.status) {
                "ok"             { "Grace period OK ($($state.days) days remaining)" }
                "low"            { "Grace period LOW ($($state.days) days remaining, threshold $GraceThreshold)" }
                "expired"        { "Grace period EXPIRED" }
                "reboot_pending" { "Grace period reset pending reboot" }
                "unknown"        { "Grace period state unknown (CIM unavailable, registry has encrypted data)" }
            }
        }
        Write-Log "=== Reset-RdsGracePeriod finished (status) ==="
        $result | ConvertTo-Json -Compress
        exit 0
    }

    #--- Rezim: Reboot pending (CIM selhalo, klic smazan) ---
    if ($state.status -eq "reboot_pending") {
        Write-Log "Reboot pending - grace period key already deleted, waiting for restart" -Level WARNING
        $result = @{
            changed         = $false
            reboot_required = $true
            status          = "reboot_pending"
            msg             = "Grace period already reset, reboot required to complete"
        }
        Write-Log "=== Reset-RdsGracePeriod finished (reboot pending) ==="
        $result | ConvertTo-Json -Compress
        exit 0
    }

    # Zakaz notifikace pokud pozadovano
    $notificationChanged = $false
    if ($DisableLicenseNotification) {
        if ($DryRun) {
            $policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
            $current = Get-ItemProperty -Path $policyPath -Name "fDisableTerminalServerTooltip" -ErrorAction SilentlyContinue
            if (-not $current -or $current.fDisableTerminalServerTooltip -ne 1) {
                $notificationChanged = $true
                Write-Log "[DRY RUN] Would disable license notification"
            }
        }
        else {
            $notificationChanged = Disable-LicenseNotification
        }
    }

    #--- Rezim: Grace period OK ---
    if ($state.status -eq "ok") {
        $result = @{
            changed         = $notificationChanged
            reboot_required = $false
            status          = "ok"
            days_remaining  = $state.days
            msg             = "Grace period OK ($($state.days) days remaining, threshold $GraceThreshold)"
        }
        Write-Log "No action needed - $($state.days) days remaining (threshold $GraceThreshold)"
    }
    #--- Rezim: DryRun ---
    elseif ($DryRun) {
        Write-Log "[DRY RUN] Would reset grace period ($($state.status), $($state.days) days remaining)"
        $result = @{
            changed         = $false
            reboot_required = $false
            dry_run         = $true
            status          = $state.status
            days_remaining  = $state.days
            msg             = "DRY RUN: would reset grace period ($($state.status), $($state.days) days)"
        }
        if ($notificationChanged) {
            $result.msg += "; would disable license notification"
        }
    }
    #--- Rezim: Reset ---
    else {
        Write-Log "Grace period $($state.status) ($($state.days) days < $GraceThreshold) - resetting"
        Reset-GracePeriod
        $result = @{
            changed         = $true
            reboot_required = (-not $NoReboot)
            status          = "reset_done"
            days_remaining  = $state.days
            msg             = "Grace period reset to 120 days (was $($state.status), $($state.days) days)"
        }
        Write-Log "Grace period reset completed successfully"
    }

    # Doplneni info o notifikaci do msg
    if ($notificationChanged -and -not $DryRun) {
        $result.msg += "; license notification disabled"
    }

    Write-Log "=== Reset-RdsGracePeriod finished ==="
    $result | ConvertTo-Json -Compress
    exit 0
}
catch {
    Write-Log "FATAL: $($_.Exception.Message)" -Level ERROR
    Write-Log "Stack: $($_.ScriptStackTrace)" -Level ERROR

    @{
        changed         = $false
        reboot_required = $false
        msg             = "Error: $($_.Exception.Message)"
    } | ConvertTo-Json -Compress

    exit 1
}
#endregion
