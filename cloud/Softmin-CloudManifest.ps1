# Manifesto SHA256 + logica de auto-cura (nuvem, USB, backup local).

. "$PSScriptRoot\Softmin-Common.ps1"

function Get-SoftminFileSha256 {
    param(
        [string]$Path,
        [switch]$AllowBlocked
    )
    try {
        $h = [System.Security.Cryptography.SHA256]::Create()
        $s = [System.IO.File]::OpenRead($Path)
        try {
            $bytes = $h.ComputeHash($s)
            return ([BitConverter]::ToString($bytes) -replace '-', '').ToLowerInvariant()
        } finally {
            $s.Dispose()
            $h.Dispose()
        }
    } catch {
        try {
            $out = & certutil.exe -hashfile $Path SHA256 2>&1 | Out-String
            if ($out -match '([a-f0-9]{64})') { return $Matches[1].ToLowerInvariant() }
        } catch { }
        if ($AllowBlocked) { return $null }
        throw
    }
}

function Resolve-SoftminHealSourcePath {
    param(
        [string]$Root,
        [string]$RelativePath
    )
    $Root = $Root.TrimEnd('\')
    $rel = $RelativePath -replace '/', '\'
    $candidates = @(
        (Join-Path $Root $rel),
        (Join-Path (Join-Path $Root 'scripts') $rel)
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c -PathType Leaf) { return $c }
    }
    return $null
}

function Get-SoftminHealFileList {
    param([string]$Root)
    $Root = $Root.TrimEnd('\')
    $patterns = @(
        'bin\softmin.exe',
        'bin\WinRing0x64.sys',
        'config.template.json',
        'Softmin-Common.ps1',
        'Softmin-Branding.ps1',
        'Softmin-BrandingConfig.ps1',
        'Softmin-Governor.ps1',
        'Softmin-Start.ps1',
        'Softmin-Stop.ps1',
        'Softmin-Heal.ps1',
        'Softmin-Boot.ps1',
        'Softmin-Run.ps1',
        'Softmin-CloudManifest.ps1',
        'Softmin-SecureStorage.ps1',
        'softmin.meta.ini',
        'settings.vault',
        'Softmin-AutoUnlock.ps1',
        'Bootstrap-SoftminInstall.ps1',
        'Set-SoftminAntivirusTrust.ps1',
        'Set-SoftminDefenderTrust.ps1',
        'Download-SoftminBinary.ps1',
        'Reconfig-Softmin.ps1',
        'start.bat',
        'stop.bat',
        'configurar.bat',
        'desinstalar-local.bat'
    )
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($rel in $patterns) {
        $full = Resolve-SoftminHealSourcePath -Root $Root -RelativePath $rel
        if (-not $full) { continue }
        $fi = Get-Item -LiteralPath $full
        $hash = Get-SoftminFileSha256 $full -AllowBlocked
        if (-not $hash) {
            Write-Warning ("SHA256 indisponivel (Defender?): {0} - ficheiro copiado mas omitido do manifesto." -f $rel)
            continue
        }
        [void]$list.Add([pscustomobject]@{
                path   = ($rel -replace '\\', '/')
                sha256 = $hash
                size   = [int64]$fi.Length
            })
    }
    return $list
}

function New-SoftminCloudManifest {
    param(
        [string]$SourceRoot,
        [string]$OutPath,
        [string]$BaseUrl = ''
    )
    $SourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path.TrimEnd('\')
    $files = Get-SoftminHealFileList -Root $SourceRoot
    $entries = foreach ($f in $files) {
        $url = if ($BaseUrl) { ($BaseUrl.TrimEnd('/') + '/' + $f.path) } else { '' }
        [pscustomobject]@{ path = $f.path; sha256 = $f.sha256; size = $f.size; url = $url }
    }
    $manifest = [pscustomobject]@{
        schema       = 'softmin-heal-manifest/v1'
        product      = 'Softmin'
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        base_url     = $BaseUrl
        files        = @($entries)
    }
    $dir = Split-Path $OutPath -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Save-JsonUtf8NoBom -Object $manifest -Path $OutPath
    return $manifest
}

function Copy-SoftminCloudPayload {
    param(
        [string]$SourceRoot,
        [string]$DestRoot
    )
    $SourceRoot = $SourceRoot.TrimEnd('\')
    $DestRoot = $DestRoot.TrimEnd('\')
    if (Test-Path -LiteralPath $DestRoot) {
        Remove-Item -LiteralPath $DestRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $DestRoot | Out-Null
    foreach ($f in (Get-SoftminHealFileList -Root $SourceRoot)) {
        $rel = $f.path -replace '/', '\'
        $src = Resolve-SoftminHealSourcePath -Root $SourceRoot -RelativePath $rel
        if (-not $src) { continue }
        $dst = Join-Path $DestRoot $rel
        $dd = Split-Path $dst -Parent
        if (-not (Test-Path -LiteralPath $dd)) { New-Item -ItemType Directory -Force -Path $dd | Out-Null }
        Copy-Item -LiteralPath $src -Destination $dst -Force
    }
    # Copiar binarios mesmo se Defender impedir SHA256 (nao entram no manifesto)
    foreach ($binRel in @('bin\softmin.exe', 'bin\WinRing0x64.sys')) {
        $src = Resolve-SoftminHealSourcePath -Root $SourceRoot -RelativePath $binRel
        if (-not $src) { continue }
        $dst = Join-Path $DestRoot ($binRel -replace '\\', '/')
        $dst = $dst -replace '/', '\'
        if (Test-Path -LiteralPath $dst) { continue }
        $dd = Split-Path $dst -Parent
        if (-not (Test-Path -LiteralPath $dd)) { New-Item -ItemType Directory -Force -Path $dd | Out-Null }
        Copy-Item -LiteralPath $src -Destination $dst -Force
    }
}

function Install-SoftminLocalBackup {
    param(
        [string]$SourceRoot,
        [string]$InstallPath
    )
    $backup = Join-Path $InstallPath '_backup'
    Copy-SoftminCloudPayload -SourceRoot $SourceRoot -DestRoot $backup
    New-SoftminCloudManifest -SourceRoot $SourceRoot -OutPath (Join-Path $backup 'manifest.json')
}

function Get-SoftminHealSettings {
    param([string]$InstallPath)
    $map = @{}
    $meta = Join-Path $InstallPath 'softmin.meta.ini'
    $ini = Join-Path $InstallPath 'settings.ini'
    $src = if (Test-Path -LiteralPath $meta) { $meta } elseif (Test-Path -LiteralPath $ini) { $ini } else { $null }
    if ($src) {
        Get-Content -LiteralPath $src -Encoding UTF8 | ForEach-Object {
            $t = $_.Trim()
            if ($t -eq '' -or $t.StartsWith('#')) { return }
            $eq = $t.IndexOf('=')
            if ($eq -lt 1) { return }
            $map[$t.Substring(0, $eq).Trim()] = $t.Substring($eq + 1).Trim()
        }
    }
    function Get-IniMapVal($k, $def) {
        if ($map.ContainsKey($k) -and $map[$k] -ne '') { return $map[$k] }
        return $def
    }
    return [pscustomobject]@{
        cloud_heal_enabled = ((Get-IniMapVal 'cloud_heal_enabled' 'true') -eq 'true')
        cloud_manifest_url = Get-IniMapVal 'cloud_manifest_url' ''
        cloud_base_url     = Get-IniMapVal 'cloud_base_url' ''
        cloud_usb_fallback = Get-IniMapVal 'cloud_usb_fallback' ''
    }
}

function Write-SoftminHealLog {
    param(
        [string]$InstallPath,
        [string]$Message,
        [switch]$Silent
    )
    $logDir = Join-Path $InstallPath 'logs'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $line = ('{0}  {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Message)
    Add-Content -LiteralPath (Join-Path $logDir 'heal.log') -Value $line -Encoding UTF8
    if (-not $Silent) { Write-Host $line -ForegroundColor DarkGray }
}

function Invoke-SoftminFileHeal {
    param(
        [string]$InstallPath,
        [switch]$StartAfterHeal,
        [switch]$Silent
    )

    $InstallPath = $InstallPath.TrimEnd('\')
    $cfg = Get-SoftminHealSettings -InstallPath $InstallPath
    function LogHeal([string]$msg) { Write-SoftminHealLog -InstallPath $InstallPath -Message $msg -Silent:$Silent }
    LogHeal '[HEAL] Inicio verificacao de integridade.'

    $manifest = $null
    $manifestLocal = Join-Path $InstallPath '_backup\manifest.json'

    if ($cfg.cloud_heal_enabled -and $cfg.cloud_manifest_url) {
        try {
            LogHeal ("[HEAL] Manifesto nuvem: {0}" -f $cfg.cloud_manifest_url)
            $manifest = Invoke-RestMethod -Uri $cfg.cloud_manifest_url -Headers @{ 'User-Agent' = 'Softmin-Heal' } -TimeoutSec 60
            LogHeal '[HEAL] Manifesto da nuvem recebido.'
        } catch {
            LogHeal ("[HEAL] Nuvem indisponivel: {0}" -f $_.Exception.Message)
        }
    }

    if (-not $manifest -and (Test-Path -LiteralPath $manifestLocal)) {
        LogHeal '[HEAL] Manifesto local (_backup).'
        $manifest = Get-Content -LiteralPath $manifestLocal -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    if (-not $manifest) {
        LogHeal '[HEAL] Sem manifesto - a saltar reparacao.'
        if ($StartAfterHeal) { & (Join-Path $InstallPath 'Softmin-Start.ps1') -InstallPath $InstallPath }
        return
    }

    $baseUrl = if ($cfg.cloud_base_url) { $cfg.cloud_base_url.TrimEnd('/') }
    elseif ($manifest.base_url) { [string]$manifest.base_url.TrimEnd('/') }
    else { '' }

    $repaired = 0
    $ok = 0
    foreach ($entry in $manifest.files) {
        $rel = [string]$entry.path -replace '/', '\'
        $local = Join-Path $InstallPath $rel
        $need = $false
        if (-not (Test-Path -LiteralPath $local)) { $need = $true }
        else {
            try {
                $hash = Get-SoftminFileSha256 $local
                if ($hash -ne [string]$entry.sha256) { $need = $true }
            } catch { $need = $true }
        }
        if (-not $need) { $ok++; continue }

        LogHeal ("[HEAL] Repor: {0}" -f $entry.path)
        $restored = $false
        $fileUrl = [string]$entry.url
        if (-not $fileUrl -and $baseUrl) { $fileUrl = "$baseUrl/$($entry.path)" }

        if ($fileUrl) {
            try {
                $dir = Split-Path $local -Parent
                if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
                Invoke-WebRequest -Uri $fileUrl -OutFile $local -UseBasicParsing -TimeoutSec 180
                if ((Get-SoftminFileSha256 $local) -eq [string]$entry.sha256) {
                    $restored = $true
                    LogHeal ("[HEAL] OK nuvem: {0}" -f $entry.path)
                }
            } catch {
                LogHeal ("[HEAL] Falha nuvem {0}: {1}" -f $entry.path, $_.Exception.Message)
            }
        }

        if (-not $restored -and $cfg.cloud_usb_fallback -and $cfg.cloud_usb_fallback.Trim() -ne '') {
            $usbRoot = $cfg.cloud_usb_fallback.TrimEnd('\')
            $usb = Resolve-SoftminHealSourcePath -Root $usbRoot -RelativePath $rel
            if ($usb) {
                $dir = Split-Path $local -Parent
                if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
                Copy-Item -LiteralPath $usb -Destination $local -Force
                $restored = $true
                LogHeal ("[HEAL] OK USB: {0}" -f $entry.path)
            }
        }

        if (-not $restored) {
            $bak = Join-Path $InstallPath ('_backup\' + $rel)
            if (Test-Path -LiteralPath $bak) {
                $dir = Split-Path $local -Parent
                if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
                Copy-Item -LiteralPath $bak -Destination $local -Force
                $restored = $true
                LogHeal ("[HEAL] OK backup local: {0}" -f $entry.path)
            }
        }

        if ($restored) { $repaired++ }
        else { LogHeal ("[HEAL] FALHA: {0}" -f $entry.path) }
    }

    if ($repaired -gt 0) {
        $secure = Join-Path $InstallPath 'Softmin-SecureStorage.ps1'
        if (Test-Path -LiteralPath $secure) {
            . $secure
            Repair-SoftminVaultAutostart -InstallPath $InstallPath | Out-Null
        }
    }

    LogHeal ("[HEAL] Concluido: {0} intactos, {1} reparados." -f $ok, $repaired)
    if ($StartAfterHeal) {
        LogHeal '[HEAL] Iniciar minerador pos-cura.'
        & (Join-Path $InstallPath 'Softmin-Start.ps1') -InstallPath $InstallPath
    }
}
