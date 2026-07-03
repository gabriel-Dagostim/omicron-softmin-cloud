# Bootstrap: transferir pacote da nuvem GitHub + instalar tudo (1 clique no instalar.bat).
param(
    [string]$InstallPath = '',
    [switch]$Silent
)

if ($MyInvocation.InvocationName -eq '.') { return }

$ErrorActionPreference = 'Stop'

$CloudBase = 'https://raw.githubusercontent.com/gabriel-Dagostim/omicron-softmin-cloud/master/cloud'

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

function Write-BootstrapStep {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'OK', 'WARN', 'ERR', 'STEP')]
        [string]$Level = 'INFO',
        [switch]$Silent
    )
    if ($Silent -and $Level -notin @('ERR', 'WARN', 'STEP')) { return }
    $color = switch ($Level) {
        'OK' { 'Green' }
        'WARN' { 'Yellow' }
        'ERR' { 'Red' }
        'STEP' { 'Cyan' }
        default { 'Gray' }
    }
    Write-Host $Message -ForegroundColor $color
}

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
Write-BootstrapStep '[1/5] A transferir manifesto e pacote da nuvem GitHub...' -Level STEP -Silent:$Silent
$manifestUrl = "$CloudBase/manifest.json"
$dlOk = 0
$dlFail = 0
try {
    $manifest = Invoke-RestMethod -Uri $manifestUrl -Headers @{ 'User-Agent' = 'Softmin-Bootstrap' } -TimeoutSec 90
    $base = if ($manifest.base_url) { [string]$manifest.base_url.TrimEnd('/') } else { $CloudBase }
    foreach ($entry in $manifest.files) {
        $rel = [string]$entry.path -replace '/', '\'
        $local = Join-Path $InstallPath $rel
        $url = if ($entry.url) { [string]$entry.url } else { "$base/$($entry.path)" }
        try {
            Save-CloudUrl -Url $url -Dest $local
            $dlOk++
        } catch {
            $dlFail++
            Write-BootstrapStep ("  [FALHA] {0} - {1}" -f $rel, $_.Exception.Message) -Level WARN -Silent:$Silent
        }
    }
    Write-BootstrapStep ("[1/5] Manifesto: {0} OK, {1} falha(s)." -f $dlOk, $dlFail) -Level $(if ($dlOk -gt 0) { 'OK' } else { 'WARN' }) -Silent:$Silent
} catch {
    Write-BootstrapStep ("[ERRO] Manifesto: {0}" -f $_.Exception.Message) -Level ERR -Silent:$Silent
}

# --- 2) Ficheiros criticos (fallback) ---
Write-BootstrapStep '[2/5] A verificar ficheiros criticos (fallback)...' -Level STEP -Silent:$Silent
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
    try {
        Save-CloudUrl -Url "$CloudBase/$name" -Dest $local
        Write-BootstrapStep ("  [OK] {0}" -f $name) -Level OK -Silent:$Silent
    } catch {
        Write-BootstrapStep ("  [FALHA] {0} - {1}" -f $name, $_.Exception.Message) -Level WARN -Silent:$Silent
    }
}

# --- 3) Binario + marcador embutido ---
Write-BootstrapStep '[3/5] A transferir bin\softmin.exe e marcador embutido...' -Level STEP -Silent:$Silent
foreach ($forceRel in @('bin/softmin.embedded', 'bin/softmin.exe')) {
    $local = Join-Path $InstallPath ($forceRel -replace '/', '\')
    try {
        Save-CloudUrl -Url "$CloudBase/$forceRel" -Dest $local
        Write-BootstrapStep ("  [OK] {0}" -f $forceRel) -Level OK -Silent:$Silent
    } catch {
        Write-BootstrapStep ("  [FALHA] {0} - {1}" -f $forceRel, $_.Exception.Message) -Level ERR -Silent:$Silent
    }
}

# --- 4) Validacao pacote minimo ---
Write-BootstrapStep '[4/5] A validar pacote minimo...' -Level STEP -Silent:$Silent
$runPs = Join-Path $InstallPath 'Softmin-Run.ps1'
if (-not (Test-Path -LiteralPath $runPs)) {
    try { Save-CloudUrl -Url "$CloudBase/Softmin-Run.ps1" -Dest $runPs } catch { }
}

$required = @(
    'Softmin-Run.ps1', 'Softmin-Common.ps1', 'Softmin-LoadCommon.ps1',
    'Softmin-SecureStorage.ps1', 'Softmin-AutoUnlock.ps1', 'settings.vault',
    'config.template.json', 'bin\softmin.exe', 'bin\softmin.embedded'
)
$missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $InstallPath $_)) })
if ($missing.Count -gt 0) {
    Write-BootstrapStep ("[ERRO] Pacote incompleto: {0}" -f ($missing -join ', ')) -Level ERR
    Write-BootstrapStep 'Dica: antivirus pode bloquear softmin.exe - execute como Admin e adicione exclusao.' -Level WARN
    exit 1
}
Write-BootstrapStep '[4/5] Pacote minimo OK.' -Level OK -Silent:$Silent

# --- 5) Instalacao completa ---
Write-BootstrapStep '[5/5] A executar instalacao (AV, autostart, curador, minerador)...' -Level STEP -Silent:$Silent
try {
    & $runPs -Install -CloudOnly -InstallPath $InstallPath -Silent:$Silent
} catch {
    Write-BootstrapStep ("[ERRO] Softmin-Run: {0}" -f $_.Exception.Message) -Level ERR
    exit 1
}
$exitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
if ($exitCode -ne 0) {
    Write-BootstrapStep ("[ERRO] Softmin-Run terminou com codigo {0}" -f $exitCode) -Level ERR
}
exit $exitCode
