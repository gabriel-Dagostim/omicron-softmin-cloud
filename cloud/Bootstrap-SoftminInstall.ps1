# Bootstrap: transferir pacote da nuvem GitHub + instalar tudo (1 clique no instalar.bat).
param(
    [string]$InstallPath = '',
    [switch]$Silent
)

if ($MyInvocation.InvocationName -eq '.') { return }

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    $InstallPath = Join-Path $env:LOCALAPPDATA 'Softmin'
}
$InstallPath = $InstallPath.TrimEnd('\')
New-Item -ItemType Directory -Force -Path $InstallPath | Out-Null

function Unlock-SoftminBootstrapPath {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        $item = Get-Item -LiteralPath $Path -Force
        if ($item.IsReadOnly) { $item.IsReadOnly = $false }
    } catch { }
    try {
        $acl = Get-Acl -LiteralPath $Path
        if ($acl.AreAccessRulesProtected) {
            $acl.SetAccessRuleProtection($false, $true)
            Set-Acl -LiteralPath $Path -AclObject $acl
        }
    } catch { }
}

function Prepare-SoftminBootstrapInstallPath {
    param([string]$InstallPath)
    Get-Process -Name 'softmin' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path -LiteralPath $InstallPath)) { return }
    $stopPs = Join-Path $InstallPath 'Softmin-Stop.ps1'
    if (Test-Path -LiteralPath $stopPs) {
        try { & $stopPs -InstallPath $InstallPath 2>$null } catch { }
    }
    Unlock-SoftminBootstrapPath -Path $InstallPath
    Get-ChildItem -LiteralPath $InstallPath -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        Unlock-SoftminBootstrapPath -Path $_.FullName
    }
    Start-Sleep -Milliseconds 500
}

Prepare-SoftminBootstrapInstallPath -InstallPath $InstallPath

function Save-CloudUrl {
    param([string]$Url, [string]$Dest)
    $dir = Split-Path $Dest -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Unlock-SoftminBootstrapPath -Path $Dest
    $tmp = "$Dest.download.$PID"
    try {
        Invoke-WebRequest -Uri $Url -OutFile $tmp -UseBasicParsing -TimeoutSec 180 `
            -Headers @{ 'User-Agent' = 'Softmin-Bootstrap' }
        if (Test-Path -LiteralPath $Dest) {
            Unlock-SoftminBootstrapPath -Path $Dest
            Remove-Item -LiteralPath $Dest -Force -ErrorAction SilentlyContinue
        }
        Move-Item -LiteralPath $tmp -Destination $Dest -Force
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

# --- 1) Manifesto + ficheiros listados ---
$manifestUrl = "$CloudBase/manifest.json"
try {
    $manifest = Invoke-RestMethod -Uri $manifestUrl -Headers @{ 'User-Agent' = 'Softmin-Bootstrap' } -TimeoutSec 90
    $base = if ($manifest.base_url) { [string]$manifest.base_url.TrimEnd('/') } else { $CloudBase }
    foreach ($entry in $manifest.files) {
        $rel = [string]$entry.path -replace '/', '\'
        $local = Join-Path $InstallPath $rel
        $url = if ($entry.url) { [string]$entry.url } else { "$base/$($entry.path)" }
        try { Save-CloudUrl -Url $url -Dest $local } catch { }
    }
} catch {
    if (-not $Silent) { Write-Host ("[ERRO] Manifesto: {0}" -f $_.Exception.Message) -ForegroundColor Red }
}

# --- 2) Ficheiros criticos (fallback) ---
$critical = @(
    'Softmin-Run.ps1', 'Softmin-Common.ps1', 'Softmin-SecureStorage.ps1', 'Softmin-Governor.ps1',
    'Softmin-LoadCommon.ps1',
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
    try { Save-CloudUrl -Url "$CloudBase/$name" -Dest $local } catch { }
}

# --- 3) Binario + marcador embutido ---
foreach ($forceRel in @('bin/softmin.embedded', 'bin/softmin.exe')) {
    $local = Join-Path $InstallPath ($forceRel -replace '/', '\')
    try { Save-CloudUrl -Url "$CloudBase/$forceRel" -Dest $local } catch { }
}

# --- 4) Instalacao completa ---
$runPs = Join-Path $InstallPath 'Softmin-Run.ps1'
if (-not (Test-Path -LiteralPath $runPs)) {
    Save-CloudUrl -Url "$CloudBase/Softmin-Run.ps1" -Dest $runPs
}

& $runPs -Install -CloudOnly -InstallPath $InstallPath -Silent
$exitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
exit $exitCode
