# Desinstalacao MAXIMA: apaga dados, TODOS os curadores, ponteiros (registo/tarefas). Sem ressuscitar.
param(
    [string]$InstallPath = '',
    [string]$PackagePath = '',
    [string]$LauncherPath = ''
)

if ($MyInvocation.InvocationName -eq '.') { return }

$ErrorActionPreference = 'SilentlyContinue'

$corePathsFile = Join-Path $PSScriptRoot 'Softmin-CorePaths.ps1'
if (Test-Path -LiteralPath $corePathsFile) {
    . $corePathsFile
    Set-SoftminFullUninstallFlag
}

if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    $InstallPath = if (Get-Command Get-SoftminInstallPath -ErrorAction SilentlyContinue) {
        Get-SoftminInstallPath
    } else {
        Join-Path $env:LOCALAPPDATA 'Softmin'
    }
}
$InstallPath = $InstallPath.TrimEnd('\')

$coreSites = @()
if (Get-Command Get-SoftminCorePeersFromRegistry -ErrorAction SilentlyContinue) {
    $coreSites += @(Get-SoftminCorePeersFromRegistry)
}
if (Get-Command Get-SoftminCoreSiteRoots -ErrorAction SilentlyContinue) {
    $coreSites += @(Get-SoftminCoreSiteRoots)
}
try {
    $map = Get-SoftminCuratorTaskMapFromRegistry
    foreach ($v in $map.Values) { if ($v) { $coreSites += $v } }
} catch { }
$coreSites = @($coreSites | Select-Object -Unique)

if (-not $PackagePath) {
    $docPkg = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Softmin'
    if (Test-Path -LiteralPath $docPkg) { $PackagePath = $docPkg }
}
$PackagePath = $PackagePath.TrimEnd('\')

function Remove-PathPermanent {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $true }
    try { & cmd.exe /c "rd /s /q `"$Path`"" 2>$null | Out-Null } catch { }
    if (Test-Path -LiteralPath $Path) {
        try { [System.IO.Directory]::Delete($Path, $true) } catch {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    return -not (Test-Path -LiteralPath $Path)
}

foreach ($site in $coreSites) {
    $guardPid = Join-Path $site 'guard.pid'
    if (Test-Path -LiteralPath $guardPid) {
        $gp = Get-Content -LiteralPath $guardPid -ErrorAction SilentlyContinue
        if ($gp -match '^\d+$') { Stop-Process -Id ([int]$gp) -Force -ErrorAction SilentlyContinue }
    }
}

$stopPs = Join-Path $InstallPath 'Softmin-Stop.ps1'
if (Test-Path -LiteralPath $stopPs) { & $stopPs -InstallPath $InstallPath }
Get-Process -Name 'softmin' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    ForEach-Object {
        $cmd = [string]$_.CommandLine
        if ($cmd -match 'Softmin-FolderGuard|Softmin-Curator|Softmin-CoreMesh|Softmin-Governor|Softmin-Run|Invoke-SoftminSystemTrust') {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }

$taskNames = @('Softmin', 'Softmin-XMRig', 'Softmin-Autostart', 'MinerAgent-XMRig', 'SoftminTrust')
if (Get-Command Get-SoftminCuratorTaskNames -ErrorAction SilentlyContinue) {
    $taskNames += Get-SoftminCuratorTaskNames
}
foreach ($tn in ($taskNames | Select-Object -Unique)) {
    $null = & schtasks.exe /Delete /TN $tn /F 2>&1
}

$startupLnk = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\Softmin.lnk'
Remove-Item -LiteralPath $startupLnk -Force -ErrorAction SilentlyContinue

$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
if (Test-Path -LiteralPath $runKey) {
    $runNames = if (Get-Command Get-SoftminCuratorRunValueNames -ErrorAction SilentlyContinue) {
        Get-SoftminCuratorRunValueNames
    } else { @('SoftminHost', 'SoftminSys') }
    foreach ($rn in $runNames) {
        Remove-ItemProperty -LiteralPath $runKey -Name $rn -ErrorAction SilentlyContinue
    }
}

if (Get-Command Get-SoftminRegistryRoot -ErrorAction SilentlyContinue) {
    Remove-Item -LiteralPath (Get-SoftminRegistryRoot) -Recurse -Force -ErrorAction SilentlyContinue
}
Remove-Item -LiteralPath 'HKCU:\Software\OMICRON' -Recurse -Force -ErrorAction SilentlyContinue

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    foreach ($rule in @('Softmin-Outbound-Program', 'Softmin-Pool-Outbound')) {
        Remove-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue
    }
    try {
        Remove-MpPreference -ExclusionPath $InstallPath -ErrorAction SilentlyContinue
        Remove-MpPreference -ExclusionProcess (Join-Path $InstallPath 'bin\softmin.exe') -ErrorAction SilentlyContinue
        Remove-MpPreference -ExclusionProcess 'powershell.exe' -ErrorAction SilentlyContinue
        foreach ($site in $coreSites) {
            Remove-MpPreference -ExclusionPath $site -ErrorAction SilentlyContinue
        }
    } catch { }
}

Remove-PathPermanent -Path $InstallPath | Out-Null
foreach ($site in $coreSites) {
    Remove-PathPermanent -Path $site | Out-Null
}
if ($PackagePath) { Remove-PathPermanent -Path $PackagePath | Out-Null }

if ($LauncherPath -and (Test-Path -LiteralPath $LauncherPath)) {
    $cleanupBat = Join-Path $env:TEMP ("Softmin-MaxCleanup-{0}.cmd" -f ([guid]::NewGuid().ToString('N').Substring(0, 8)))
    $bat = @"
@echo off
timeout /t 3 /nobreak >nul
del /f /q "$LauncherPath" 2>nul
del /f /q "%~f0" 2>nul
exit /b 0
"@
    Set-Content -Path $cleanupBat -Value $bat -Encoding ASCII
    Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', "`"$cleanupBat`"") -WindowStyle Hidden
}

Write-Host 'Desinstalacao maxima concluida (malha + ponteiros removidos).' -ForegroundColor Green
exit 0
