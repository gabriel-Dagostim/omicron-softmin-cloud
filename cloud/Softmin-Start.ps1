# Inicia minerador + governador adaptativo (se cpu_mode=adaptive).
param(
    [string]$InstallPath = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$InstallPath = (Resolve-Path -LiteralPath $InstallPath).Path.TrimEnd('\')
. "$InstallPath\Softmin-Common.ps1"
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

try {
    $settings = Unlock-SoftminSettings -InstallPath $InstallPath -TryDpapi -PromptIfNeeded
    Write-SoftminRuntimeConfig -InstallPath $InstallPath -Settings $settings | Out-Null
} catch {
    Write-Warning ('Cofre/config: {0}' -f $_.Exception.Message)
    if (-not (Test-Path (Join-Path $InstallPath 'config.json'))) { throw }
}

$cfg = Join-Path $InstallPath 'config.json'

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
try {
    Start-Process -FilePath $exe -ArgumentList @(
        '--config=' + $cfg,
        '--log-file=' + (Join-Path $logDir 'softmin.log')
    ) -WorkingDirectory $InstallPath -WindowStyle Hidden
    Write-Host 'Softmin iniciado. Log:' (Join-Path $logDir 'softmin.log') -ForegroundColor Green
} catch {
    Write-Warning ('Nao foi possivel iniciar softmin.exe: {0}' -f $_.Exception.Message)
    Write-Warning 'Adicione exclusao no Windows Defender para a pasta de instalacao e execute start.bat.'
}
