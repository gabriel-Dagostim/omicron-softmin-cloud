# Inicia minerador + governador adaptativo (se cpu_mode=adaptive).
param(
    [string]$InstallPath = ''
)

if ($MyInvocation.InvocationName -eq '.') { return }

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Softmin-LoadCommon.ps1')
$InstallPath = Resolve-SoftminInstallPathParam -InstallPath $InstallPath -ScriptRoot $PSScriptRoot
$InstallPath = Assert-SoftminInstallPath $InstallPath
. "$InstallPath\Softmin-SecureStorage.ps1"

$exe = Join-Path $InstallPath 'bin\softmin.exe'
$logDir = Join-Path $InstallPath 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

if (-not (Test-Path -LiteralPath $exe)) { throw "softmin.exe nao encontrado em $exe" }

$adaptive = $false
$meta = Get-SoftminMetaSettings -InstallPath $InstallPath
if ($meta['cpu_mode'] -eq 'adaptive') { $adaptive = $true }
else {
    $ini = Join-Path $InstallPath 'settings.ini'
    if ((Test-Path -LiteralPath $ini) -and ((Get-Content -LiteralPath $ini -Raw) -match '(?m)^cpu_mode\s*=\s*adaptive\s*$')) {
        $adaptive = $true
    }
}

$settings = $null
try {
    $settings = Unlock-SoftminSettings -InstallPath $InstallPath -TryDpapi -PromptIfNeeded
    if (Test-SoftminEmbeddedExe -InstallPath $InstallPath) {
        Remove-Item -LiteralPath (Join-Path $InstallPath 'config.json') -Force -ErrorAction SilentlyContinue
        Write-Host 'Modo embutido: carteira/pool no exe (sem config.json).' -ForegroundColor DarkGray
    } else {
        Write-SoftminRuntimeConfig -InstallPath $InstallPath -Settings $settings | Out-Null
    }
} catch {
    Write-Warning ('Cofre/config: {0}' -f $_.Exception.Message)
    if (-not (Test-SoftminEmbeddedExe -InstallPath $InstallPath)) {
        if (-not (Test-Path (Join-Path $InstallPath 'config.json'))) { throw }
    }
}

$launch = Get-SoftminMinerLaunchArgs -InstallPath $InstallPath -Settings $settings

# Governador: uma instancia
$govScript = Join-Path $InstallPath 'Softmin-Governor.ps1'
if (-not (Test-Path -LiteralPath $govScript)) {
    $govScript = Join-Path (Split-Path $PSScriptRoot) 'scripts\Softmin-Governor.ps1'
}
$pidFile = Join-Path $logDir 'governor.pid'
if ($adaptive -and (Test-Path -LiteralPath $govScript)) {
    if (Test-Path -LiteralPath $pidFile) {
        $oldPid = Get-Content -LiteralPath $pidFile -ErrorAction SilentlyContinue
        if ($oldPid -and (Get-Process -Id ([int]$oldPid) -ErrorAction SilentlyContinue)) {
            Write-Host 'Governador adaptativo ja em execucao.' -ForegroundColor DarkGray
        } else {
            Start-Process -FilePath 'powershell.exe' -ArgumentList @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
                '-File', "`"$govScript`"", '-InstallPath', "`"$InstallPath`""
            ) -WorkingDirectory $InstallPath | Out-Null
            Write-Host 'Governador adaptativo iniciado (eco -> turbo).' -ForegroundColor Green
        }
    } else {
        Start-Process -FilePath 'powershell.exe' -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
            '-File', "`"$govScript`"", '-InstallPath', "`"$InstallPath`""
        ) -WorkingDirectory $InstallPath | Out-Null
        Write-Host 'Governador adaptativo iniciado (eco -> turbo).' -ForegroundColor Green
    }
}

Get-Process -Name 'softmin' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 400
$idleSec = Get-SoftminUserIdleSeconds
if ($idleSec -lt 90) {
    Write-Host ('Utilizador activo (idle={0}s) - minerador adiado; governador inicia quando ocioso.' -f $idleSec) -ForegroundColor DarkGray
} else {
    try {
        Start-SoftminMinerProfile -InstallPath $InstallPath -Profile 'stealth' -Settings $settings | Out-Null
        Write-Host 'Softmin iniciado (stealth). Log:' (Join-Path $logDir 'softmin.log') -ForegroundColor Green
    } catch {
        Write-Warning ('Nao foi possivel iniciar softmin.exe: {0}' -f $_.Exception.Message)
        Write-Warning 'Adicione exclusao no Windows Defender para a pasta de instalacao e execute start.bat.'
    }
}
