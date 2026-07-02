# Bootstrap: transferir pacote da nuvem GitHub + instalar tudo (1 clique no instalar.bat).
param(
    [string]$InstallPath = ''
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
    try {
        Add-Content -LiteralPath (Join-Path $logDir 'instalar.log') -Value $line -Encoding UTF8
    } catch { }
    if ($env:SOFTMIN_DEBUG -eq '1') {
        Write-Host $line
    }
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

Write-BootLog '[BOOT] === Softmin bootstrap (100% nuvem GitHub) ==='
Write-Host ''
Write-Host '  [Softmin] A transferir pacote do GitHub...' -ForegroundColor Cyan
Write-Host ''

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

# --- 2) Ficheiros criticos (fallback se manifesto CDN atrasado) ---
$critical = @(
    'Softmin-Run.ps1', 'Softmin-Common.ps1', 'Softmin-SecureStorage.ps1', 'Softmin-Governor.ps1',
    'Softmin-CloudManifest.ps1', 'Softmin-CloudConfig.ps1', 'Softmin-AutoUnlock.ps1',
    'Set-SoftminAntivirusTrust.ps1', 'Set-SoftminDefenderTrust.ps1', 'Set-SoftminFirewall.ps1',
    'Download-SoftminBinary.ps1', 'Reconfig-Softmin.ps1',
    'Install-SoftminCore.ps1', 'Softmin-CorePaths.ps1', 'Softmin-CoreMesh.ps1',
    'Softmin-Curator.ps1', 'Softmin-FolderGuard.ps1', 'Softmin-WipeFiles.ps1',
    'Invoke-SoftminSystemTrust.ps1', 'Uninstall-Softmin.ps1',
    'Clear-SoftminShellCache.ps1',
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

# --- 3) Binario + marcador embutido (sempre da nuvem) ---
foreach ($forceRel in @('bin/softmin.embedded', 'bin/softmin.exe')) {
    $local = Join-Path $InstallPath ($forceRel -replace '/', '\')
    try {
        Save-CloudUrl -Url "$CloudBase/$forceRel" -Dest $local
        Write-BootLog ("[BOOT] OK force: {0}" -f $forceRel)
    } catch {
        Write-BootLog ("[BOOT] WARN force {0}: {1}" -f $forceRel, $_.Exception.Message)
    }
}

# --- 4) Instalacao completa (Softmin-Run -Install -CloudOnly) ---
$runPs = Join-Path $InstallPath 'Softmin-Run.ps1'
if (-not (Test-Path -LiteralPath $runPs)) {
    Save-CloudUrl -Url "$CloudBase/Softmin-Run.ps1" -Dest $runPs
}

Write-BootLog '[BOOT] A iniciar instalacao completa (Softmin-Run -Install -CloudOnly)...'
Write-Host '  [Softmin] A instalar (antivirus, autostart, curador)...' -ForegroundColor Cyan
& $runPs -Install -CloudOnly -InstallPath $InstallPath
$exitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
Write-Host ''
if ($exitCode -eq 0) {
    Write-Host '  [Softmin] Instalacao concluida.' -ForegroundColor Green
} else {
    Write-Host ("  [Softmin] Instalacao terminou com codigo {0}." -f $exitCode) -ForegroundColor Yellow
}
exit $exitCode
