# Governador adaptativo: eco -> light -> medium -> strong -> turbo (noite) + freio ao usar.
param(
    [string]$InstallPath = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'
$InstallPath = (Resolve-Path -LiteralPath $InstallPath).Path.TrimEnd('\')

. "$InstallPath\Softmin-Common.ps1"

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class SoftminIdle {
    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }
    [DllImport("user32.dll")]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    public static uint GetIdleSeconds() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf(typeof(LASTINPUTINFO));
        if (!GetLastInputInfo(ref lii)) return 0;
        return ((uint)Environment.TickCount - lii.dwTime) / 1000;
    }
}
'@

function Get-AdaptiveSettings {
    $defaults = @{
        cpu_mode                      = 'adaptive'
        adaptive_check_seconds        = 30
        adaptive_active_threshold_seconds = 30
        adaptive_resume_seconds       = 120
        adaptive_brake                = 'eco'
        night_start                   = '00:00'
        night_end                     = '07:00'
        adaptive_ramp_minutes         = @(5, 15, 30)
        adaptive_night_ramp_minutes   = 10
    }
    $secure = Join-Path $InstallPath 'Softmin-SecureStorage.ps1'
    if (Test-Path -LiteralPath $secure) {
        . $secure
        $m = Read-SoftminAdaptiveMeta -InstallPath $InstallPath
        foreach ($k in $m.Keys) { if ($null -ne $m[$k]) { $defaults[$k] = $m[$k] } }
        return $defaults
    }
    $ini = Join-Path $InstallPath 'settings.ini'
    $json = Join-Path $InstallPath 'settings.json'
    if (Test-Path -LiteralPath $json) {
        $j = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json
        foreach ($k in $defaults.Keys) {
            if ($j.PSObject.Properties.Name -contains $k) { $defaults[$k] = $j.$k }
        }
    } elseif (Test-Path -LiteralPath $ini) {
        $map = @{}
        Get-Content -LiteralPath $ini -Encoding UTF8 | ForEach-Object {
            $t = $_.Trim()
            if ($t -eq '' -or $t.StartsWith('#')) { return }
            $eq = $t.IndexOf('=')
            if ($eq -lt 1) { return }
            $map[$t.Substring(0, $eq).Trim()] = $t.Substring($eq + 1).Trim()
        }
        if ($map['adaptive_ramp_minutes']) {
            $defaults['adaptive_ramp_minutes'] = @($map['adaptive_ramp_minutes'] -split ',' | ForEach-Object { [int]$_.Trim() })
        }
        foreach ($k in @('cpu_mode', 'adaptive_brake', 'night_start', 'night_end')) {
            if ($map.ContainsKey($k)) { $defaults[$k] = $map[$k] }
        }
        foreach ($k in @('adaptive_check_seconds', 'adaptive_active_threshold_seconds', 'adaptive_resume_seconds', 'adaptive_night_ramp_minutes')) {
            if ($map.ContainsKey($k) -and $map[$k] -match '^\d+$') { $defaults[$k] = [int]$map[$k] }
        }
    }
    return $defaults
}

function Test-NightWindow {
    param([string]$Start, [string]$End)
    $now = Get-Date
    $s = [datetime]::ParseExact($Start, 'HH:mm', $null)
    $e = [datetime]::ParseExact($End, 'HH:mm', $null)
    $t = Get-Date -Hour $now.Hour -Minute $now.Minute -Second 0
    $ts = Get-Date -Hour $s.Hour -Minute $s.Minute -Second 0
    $te = Get-Date -Hour $e.Hour -Minute $e.Minute -Second 0
    if ($ts -le $te) { return ($t -ge $ts -and $t -lt $te) }
    return ($t -ge $ts -or $t -lt $te)
}

function Get-ProfileForIdle {
    param(
        [uint32]$IdleSec,
        [bool]$IsNight,
        [int[]]$RampMinutes,
        [int]$NightRampMinutes
    )
    $r1 = if ($RampMinutes.Count -ge 1) { $RampMinutes[0] * 60 } else { 300 }
    $r2 = if ($RampMinutes.Count -ge 2) { $RampMinutes[1] * 60 } else { 900 }
    $r3 = if ($RampMinutes.Count -ge 3) { $RampMinutes[2] * 60 } else { 1800 }
    $rn = $NightRampMinutes * 60

    if ($IsNight -and $IdleSec -ge $rn) { return 'turbo' }
    if ($IdleSec -ge $r3) { return 'strong' }
    if ($IdleSec -ge $r2) { return 'medium' }
    if ($IdleSec -ge $r1) { return 'light' }
    return 'eco'
}

function Set-ConfigHint {
    param([int]$Hint)
    $cfgPath = Join-Path $InstallPath 'config.json'
    if (-not (Test-Path -LiteralPath $cfgPath)) { return }
    $raw = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$raw.cpu.'max-threads-hint' -eq $Hint) { return }
    $raw.cpu.'max-threads-hint' = $Hint
    Save-JsonUtf8NoBom -Object $raw -Path $cfgPath
}

$logDir = Join-Path $InstallPath 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$statePath = Join-Path $logDir 'governor-state.json'
$pidPath = Join-Path $logDir 'governor.pid'
[System.IO.File]::WriteAllText($pidPath, $PID)

$ad = Get-AdaptiveSettings
$currentProfile = 'eco'
$braking = $false
$lastBrakeAt = [datetime]::MinValue

Write-SoftminInstallLog $InstallPath '[GOVERNOR] Iniciado (modo adaptativo eco->turbo).'

while ($true) {
    try {
        $idle = [SoftminIdle]::GetIdleSeconds()
        $activeThreshold = [int]$ad.adaptive_active_threshold_seconds
        $userActive = ($idle -lt $activeThreshold)
        $isNight = Test-NightWindow -Start $ad.night_start -End $ad.night_end
        $ramp = @($ad.adaptive_ramp_minutes | ForEach-Object { [int]$_ })

        if ($userActive) {
            if (-not $braking) {
                $braking = $true
                $lastBrakeAt = Get-Date
                if ($ad.adaptive_brake -eq 'pause') {
                    Get-Process -Name 'softmin' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                    Write-SoftminInstallLog $InstallPath '[GOVERNOR] Freio: utilizador activo (pause).'
                } else {
                    Set-ConfigHint -Hint (Get-MaxThreadsHint 'eco')
                    $currentProfile = 'eco'
                    Write-SoftminInstallLog $InstallPath '[GOVERNOR] Freio: utilizador activo (eco).'
                }
            }
        } else {
            if ($braking) {
                $resumeSec = [int]$ad.adaptive_resume_seconds
                if (((Get-Date) - $lastBrakeAt).TotalSeconds -ge $resumeSec) {
                    $braking = $false
                    $currentProfile = 'eco'
                    Set-ConfigHint -Hint (Get-MaxThreadsHint 'eco')
                    if ($ad.adaptive_brake -eq 'pause') {
                        $exe = Join-Path $InstallPath 'bin\softmin.exe'
                        $cfg = Join-Path $InstallPath 'config.json'
                        if ((Test-Path $exe) -and -not (Get-Process -Name 'softmin' -ErrorAction SilentlyContinue)) {
                            Start-Process -FilePath $exe -ArgumentList @('--config=' + $cfg, '--log-file=' + (Join-Path $logDir 'softmin.log')) `
                                -WorkingDirectory $InstallPath -WindowStyle Hidden
                        }
                    }
                    Write-SoftminInstallLog $InstallPath '[GOVERNOR] Ocioso confirmado; rampa reinicia em eco.'
                }
            } else {
                $target = Get-ProfileForIdle -IdleSec $idle -IsNight $isNight -RampMinutes $ramp `
                    -NightRampMinutes ([int]$ad.adaptive_night_ramp_minutes)
                if ($target -ne $currentProfile) {
                    $hint = Get-MaxThreadsHint $target
                    Set-ConfigHint -Hint $hint
                    Write-SoftminInstallLog $InstallPath ("[GOVERNOR] Perfil {0} -> {1} (hint={2}, idle={3}s, noite={4})" -f $currentProfile, $target, $hint, $idle, $isNight)
                    $currentProfile = $target
                }
            }
        }

        $state = [pscustomobject]@{
            at       = (Get-Date).ToString('o')
            profile  = $currentProfile
            idle_sec = $idle
            braking  = $braking
            night    = $isNight
        }
        Save-JsonUtf8NoBom -Object $state -Path $statePath
    } catch {
        Write-SoftminInstallLog $InstallPath ("[GOVERNOR] ERRO: {0}" -f $_.Exception.Message)
    }

    Start-Sleep -Seconds ([int]$ad.adaptive_check_seconds)
}
