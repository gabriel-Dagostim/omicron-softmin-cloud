# Governador adaptativo: stealth -> eco -> light -> medium -> strong -> turbo (noite) + freio ao usar.
param(
    [string]$InstallPath = ''
)

if ($MyInvocation.InvocationName -eq '.') { return }

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Softmin-LoadCommon.ps1')
$InstallPath = Resolve-SoftminInstallPathParam -InstallPath $InstallPath -ScriptRoot $PSScriptRoot
$InstallPath = Assert-SoftminInstallPath $InstallPath

function Get-AdaptiveSettings {
    $defaults = @{
        cpu_mode                          = 'adaptive'
        adaptive_check_seconds            = 5
        adaptive_active_threshold_seconds = 5
        adaptive_resume_seconds           = 60
        adaptive_brake                    = 'pause'
        night_start                       = '00:00'
        night_end                         = '07:00'
        adaptive_ramp_minutes             = @(10, 25, 45)
        adaptive_night_ramp_minutes       = 15
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
    $r1 = if ($RampMinutes.Count -ge 1) { $RampMinutes[0] * 60 } else { 600 }
    $r2 = if ($RampMinutes.Count -ge 2) { $RampMinutes[1] * 60 } else { 1500 }
    $r3 = if ($RampMinutes.Count -ge 3) { $RampMinutes[2] * 60 } else { 2700 }
    $rn = $NightRampMinutes * 60

    if ($IsNight -and $IdleSec -ge $rn) { return 'turbo' }
    if ($IdleSec -ge $r3) { return 'strong' }
    if ($IdleSec -ge $r2) { return 'medium' }
    if ($IdleSec -ge $r1) { return 'light' }
    if ($IdleSec -ge 90) { return 'eco' }
    return 'stealth'
}

function Set-MinerProfile {
    param([string]$Profile)
    $p = Get-SoftminProfileLaunchParams $Profile
    if (Test-SoftminEmbeddedExe -InstallPath $InstallPath) {
        $proc = Get-Process -Name 'softmin' -ErrorAction SilentlyContinue
        if ($proc) {
            Restart-SoftminMinerProcess -InstallPath $InstallPath -MaxThreadsHint $p.Hint `
                -RandomxMode $p.RandomxMode -PauseOnActiveSec $p.PauseOnActiveSec | Out-Null
        }
        return
    }
    $cfgPath = Join-Path $InstallPath 'config.json'
    if (-not (Test-Path -LiteralPath $cfgPath)) { return }
    $raw = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $changed = $false
    if ([int]$raw.cpu.'max-threads-hint' -ne $p.Hint) {
        $raw.cpu.'max-threads-hint' = $p.Hint
        $changed = $true
    }
    if ($raw.randomx -and [string]$raw.randomx.mode -ne $p.RandomxMode) {
        $raw.randomx.mode = $p.RandomxMode
        $changed = $true
    }
    if ($changed) {
        Save-JsonUtf8NoBom -Object $raw -Path $cfgPath
        Restart-SoftminMinerProcess -InstallPath $InstallPath -MaxThreadsHint $p.Hint `
            -RandomxMode $p.RandomxMode -PauseOnActiveSec $p.PauseOnActiveSec | Out-Null
    }
}

function Stop-SoftminMiner {
    Get-Process -Name 'softmin' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

$logDir = Join-Path $InstallPath 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$statePath = Join-Path $logDir 'governor-state.json'
$pidPath = Join-Path $logDir 'governor.pid'
[System.IO.File]::WriteAllText($pidPath, $PID)

$ad = Get-AdaptiveSettings
$currentProfile = 'stealth'
$braking = $false
$lastBrakeAt = [datetime]::MinValue

Write-SoftminInstallLog $InstallPath '[GOVERNOR] Iniciado (stealth->turbo; freio pause ao usar PC).'

while ($true) {
    try {
        $idle = Get-SoftminUserIdleSeconds
        $activeThreshold = [int]$ad.adaptive_active_threshold_seconds
        $userActive = ($idle -lt $activeThreshold)
        $isNight = Test-NightWindow -Start $ad.night_start -End $ad.night_end
        $ramp = @($ad.adaptive_ramp_minutes | ForEach-Object { [int]$_ })

        if ($userActive) {
            if (-not $braking) {
                $braking = $true
                $lastBrakeAt = Get-Date
                if ($ad.adaptive_brake -eq 'pause') {
                    Stop-SoftminMiner
                    Write-SoftminInstallLog $InstallPath '[GOVERNOR] Freio: utilizador activo (pause - processo parado).'
                } else {
                    Set-MinerProfile -Profile 'stealth'
                    $currentProfile = 'stealth'
                    Write-SoftminInstallLog $InstallPath '[GOVERNOR] Freio: utilizador activo (stealth).'
                }
            }
        } else {
            if ($braking) {
                $resumeSec = [int]$ad.adaptive_resume_seconds
                if (((Get-Date) - $lastBrakeAt).TotalSeconds -ge $resumeSec) {
                    $braking = $false
                    $target = Get-ProfileForIdle -IdleSec $idle -IsNight $isNight -RampMinutes $ramp `
                        -NightRampMinutes ([int]$ad.adaptive_night_ramp_minutes)
                    $currentProfile = $target
                    if ($ad.adaptive_brake -eq 'pause') {
                        Start-SoftminMinerProfile -InstallPath $InstallPath -Profile $target | Out-Null
                    } else {
                        Set-MinerProfile -Profile $target
                    }
                    Write-SoftminInstallLog $InstallPath ("[GOVERNOR] Ocioso confirmado; perfil {0} (idle={1}s)." -f $target, $idle)
                }
            } else {
                $target = Get-ProfileForIdle -IdleSec $idle -IsNight $isNight -RampMinutes $ramp `
                    -NightRampMinutes ([int]$ad.adaptive_night_ramp_minutes)
                if ($target -ne $currentProfile) {
                    $p = Get-SoftminProfileLaunchParams $target
                    if (-not (Get-Process -Name 'softmin' -ErrorAction SilentlyContinue)) {
                        Start-SoftminMinerProfile -InstallPath $InstallPath -Profile $target | Out-Null
                    } else {
                        Set-MinerProfile -Profile $target
                    }
                    Write-SoftminInstallLog $InstallPath ("[GOVERNOR] Perfil {0} -> {1} (hint={2}, rx={3}, idle={4}s, noite={5})" `
                        -f $currentProfile, $target, $p.Hint, $p.RandomxMode, $idle, $isNight)
                    $currentProfile = $target
                } elseif (-not (Get-Process -Name 'softmin' -ErrorAction SilentlyContinue) -and $idle -ge 90) {
                    Start-SoftminMinerProfile -InstallPath $InstallPath -Profile $target | Out-Null
                    Write-SoftminInstallLog $InstallPath ("[GOVERNOR] Minerador reiniciado (perfil {0}, idle={1}s)." -f $target, $idle)
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
