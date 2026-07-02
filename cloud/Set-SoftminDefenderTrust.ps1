# Exclusoes Windows Defender para instalacao Softmin (requer Administrador).
# Modelo: C:\ProgramData\Softmin + exclusao oficial antes de copiar o binario.

. "$PSScriptRoot\Softmin-Common.ps1"

function Test-SoftminAdmin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-SoftminDefenderTrustPaths {
    param(
        [string]$InstallPath,
        [string]$SourceRoot = ''
    )
    $InstallPath = Resolve-SoftminInstallPath $InstallPath
    $paths = [System.Collections.Generic.List[string]]::new()
    foreach ($p in @($InstallPath, (Join-Path $InstallPath 'bin'), (Join-Path $InstallPath '_backup'))) {
        if (-not $paths.Contains($p)) { [void]$paths.Add($p) }
    }
    if ($SourceRoot) {
        $SourceRoot = $SourceRoot.TrimEnd('\')
        foreach ($p in @($SourceRoot, (Join-Path $SourceRoot 'bin'))) {
            if (-not $paths.Contains($p)) { [void]$paths.Add($p) }
        }
    }
    return @($paths)
}

function Test-SoftminDefenderTrust {
    param([string[]]$Paths)
    try {
        $prefs = Get-MpPreference -ErrorAction Stop
        $existing = @($prefs.ExclusionPath)
        $missing = @()
        foreach ($p in $Paths) {
            $norm = $p.TrimEnd('\')
            $ok = $false
            foreach ($e in $existing) {
                if ($e.TrimEnd('\').Equals($norm, [StringComparison]::OrdinalIgnoreCase)) { $ok = $true; break }
            }
            if (-not $ok) { [void]$missing.Add($norm) }
        }
        return [pscustomobject]@{ Ok = ($missing.Count -eq 0); Missing = $missing }
    } catch {
        return [pscustomobject]@{ Ok = $false; Missing = $Paths; Error = $_.Exception.Message }
    }
}

function Set-SoftminDefenderTrust {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallPath,
        [string]$SourceRoot = '',
        [string]$LogInstallPath = ''
    )

    $InstallPath = Resolve-SoftminInstallPath $InstallPath
    $paths = Get-SoftminDefenderTrustPaths -InstallPath $InstallPath -SourceRoot $SourceRoot
    $minerProc = Join-Path $InstallPath 'bin\softmin.exe'

    if (-not (Test-SoftminAdmin)) {
        return [pscustomobject]@{
            Ok      = $false
            Message = 'Sem permissoes de administrador — exclusao Defender nao aplicada.'
            Paths   = $paths
        }
    }

    $errors = [System.Collections.Generic.List[string]]::new()
    foreach ($p in $paths) {
        try {
            if (-not (Test-Path -LiteralPath $p)) {
                New-Item -ItemType Directory -Force -Path $p | Out-Null
            }
            Add-MpPreference -ExclusionPath $p -ErrorAction Stop
        } catch {
            [void]$errors.Add(('{0}: {1}' -f $p, $_.Exception.Message))
        }
    }
    try {
        Add-MpPreference -ExclusionProcess $minerProc -ErrorAction SilentlyContinue
    } catch { }

    $check = Test-SoftminDefenderTrust -Paths $paths
    $msg = if ($check.Ok) {
        'Exclusoes Windows Defender aplicadas (pasta + processo softmin.exe).'
    } else {
        ('Defender parcial: {0} caminho(s) em falta.' -f $check.Missing.Count)
    }
    if ($errors.Count -gt 0) { $msg += ' ' + ($errors -join ' | ') }

    if ($LogInstallPath) {
        Write-SoftminInstallStep $LogInstallPath 'DEFENDER' $msg -Status $(if ($check.Ok) { 'OK' } else { 'WARN' })
    }

    return [pscustomobject]@{
        Ok      = $check.Ok
        Message = $msg
        Paths   = $paths
        Missing = $check.Missing
    }
}

function Copy-SoftminMinerBinary {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceRoot,
        [Parameter(Mandatory = $true)]
        [string]$InstallPath,
        [string]$LogInstallPath = '',
        [switch]$ApplyDefenderTrust
    )

    $InstallPath = Resolve-SoftminInstallPath $InstallPath
    $srcExe = Join-Path $SourceRoot 'bin\softmin.exe'
    $dstDir = Join-Path $InstallPath 'bin'
    $dstExe = Join-Path $dstDir 'softmin.exe'

    if (-not (Test-Path -LiteralPath $srcExe)) {
        throw "softmin.exe nao encontrado em $srcExe"
    }

    if ($ApplyDefenderTrust) {
        Set-SoftminDefenderTrust -InstallPath $InstallPath -SourceRoot $SourceRoot -LogInstallPath $LogInstallPath | Out-Null
    }

    New-Item -ItemType Directory -Force -Path $dstDir | Out-Null

    for ($i = 1; $i -le 3; $i++) {
        Copy-Item -Path (Join-Path $SourceRoot 'bin\*') -Destination $dstDir -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $dstExe) {
            $size = (Get-Item -LiteralPath $dstExe).Length
            if ($LogInstallPath) {
                Write-SoftminInstallStep $LogInstallPath 'BIN' ("softmin.exe copiado ({0:N0} bytes, tentativa {1})" -f $size, $i) -Status 'OK'
            }
            return [pscustomobject]@{ Ok = $true; Path = $dstExe; Size = $size }
        }
        if ($ApplyDefenderTrust -and (Test-SoftminAdmin)) {
            Set-SoftminDefenderTrust -InstallPath $InstallPath -SourceRoot $SourceRoot -LogInstallPath $LogInstallPath | Out-Null
            Start-Sleep -Seconds 2
        }
    }

    if ($LogInstallPath) {
        Write-SoftminInstallStep $LogInstallPath 'BIN' 'Defender bloqueou softmin.exe — execute instalar-completo.bat como Admin.' -Status 'ERR'
    }
    throw "Falha ao copiar softmin.exe para $dstExe (antivirus pode ter removido o ficheiro)."
}
