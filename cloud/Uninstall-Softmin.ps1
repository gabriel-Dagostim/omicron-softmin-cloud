# Desinstalacao total: para processos, remove ficheiros, firewall, tarefas, lixeira, auto-apaga-se.
param(
    [string]$InstallPath = "$env:ProgramData\Softmin",
    [string]$PackagePath = '',
    [string]$LauncherPath = ''
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Softmin-Common.ps1"

$InstallPath = $InstallPath.TrimEnd('\')
if (-not $PackagePath) {
    $docPkg = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Softmin'
    if (Test-Path -LiteralPath $docPkg) { $PackagePath = $docPkg }
}
$PackagePath = $PackagePath.TrimEnd('\')

function Write-UninstallLog {
    param([string]$Msg)
    $logDir = Join-Path $env:TEMP 'Softmin-Uninstall'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $line = ('{0}  {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Msg)
    Add-Content -LiteralPath (Join-Path $logDir 'uninstall.log') -Value $line -Encoding UTF8
    Write-Host $line -ForegroundColor DarkGray
}

Write-UninstallLog '=== Desinstalacao Softmin iniciada ==='

# Parar minerador e governador
if (Test-Path -LiteralPath (Join-Path $InstallPath 'Softmin-Stop.ps1')) {
    & (Join-Path $InstallPath 'Softmin-Stop.ps1') -InstallPath $InstallPath
} else {
    & "$PSScriptRoot\Softmin-Stop.ps1" -InstallPath $InstallPath
}
Get-Process -Name 'softmin' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Write-UninstallLog 'Processos softmin/governador terminados.'

# Tarefas agendadas
$taskNames = @('Softmin', 'Softmin-XMRig', 'Softmin-Autostart', 'MinerAgent-XMRig')
$prev = $ErrorActionPreference
$ErrorActionPreference = 'SilentlyContinue'
foreach ($tn in $taskNames) {
    $null = & schtasks.exe /Delete /TN $tn /F 2>&1
}
$ErrorActionPreference = $prev
Write-UninstallLog 'Tarefas agendadas removidas.'

# Atalho Startup
$startupLnk = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\Softmin.lnk'
Remove-Item -LiteralPath $startupLnk -Force -ErrorAction SilentlyContinue

# Firewall (admin)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    foreach ($rule in @('Softmin-Outbound-Program', 'Softmin-Pool-Outbound')) {
        Remove-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue
    }
    try {
        Remove-MpPreference -ExclusionPath $InstallPath -ErrorAction SilentlyContinue
        Remove-MpPreference -ExclusionProcess (Join-Path $InstallPath 'bin\softmin.exe') -ErrorAction SilentlyContinue
    } catch { }
    Write-UninstallLog 'Regras firewall e exclusao Defender removidas.'
}

# Apagar pasta de instalacao
if (Test-Path -LiteralPath $InstallPath) {
    try {
        Remove-Item -LiteralPath $InstallPath -Recurse -Force -ErrorAction Stop
        Write-UninstallLog "Pasta removida: $InstallPath"
    } catch {
        Write-UninstallLog "WARN: nao foi possivel remover $InstallPath — $($_.Exception.Message)"
    }
}

# Apagar pacote Documentos se existir
if ($PackagePath -and (Test-Path -LiteralPath $PackagePath)) {
    try {
        Remove-Item -LiteralPath $PackagePath -Recurse -Force -ErrorAction Stop
        Write-UninstallLog "Pacote removido: $PackagePath"
    } catch {
        Write-UninstallLog "WARN: pacote $PackagePath — $($_.Exception.Message)"
    }
}

# Esvaziar lixeira
try {
    Clear-RecycleBin -Force -ErrorAction Stop
    Write-UninstallLog 'Lixeira esvaziada.'
} catch {
    Write-UninstallLog "Lixeira: $($_.Exception.Message)"
}

# Script de verificacao + auto-apagar (launcher e este script)
$cleanupBat = Join-Path $env:TEMP ("Softmin-Cleanup-{0}.cmd" -f ([guid]::NewGuid().ToString('N').Substring(0, 8)))
$pathsToVerify = @($InstallPath)
if ($PackagePath) { $pathsToVerify += $PackagePath }
if ($LauncherPath) { $pathsToVerify += (Split-Path $LauncherPath -Parent) }

$verifyList = ($pathsToVerify | Where-Object { $_ } | ForEach-Object { "`"$_`"" }) -join ' '
$selfBat = if ($LauncherPath) { $LauncherPath } else { $PSCommandPath }

$cleanupContent = @"
@echo off
setlocal EnableExtensions
set RETRIES=12
set WAIT=5
:loop
set /a RETRIES-=1
timeout /t %WAIT% /nobreak >nul
set LEFT=0
if exist "$InstallPath" set LEFT=1
if exist "$PackagePath" set LEFT=1
tasklist /FI "IMAGENAME eq softmin.exe" 2>nul | find /I "softmin.exe" >nul && set LEFT=1
if %LEFT%==0 goto done
if %RETRIES% LEQ 0 goto done
goto loop
:done
if exist "$InstallPath" rd /s /q "$InstallPath" 2>nul
if exist "$PackagePath" rd /s /q "$PackagePath" 2>nul
del /f /q "$selfBat" 2>nul
del /f /q "%~f0" 2>nul
exit /b 0
"@

Set-Content -Path $cleanupBat -Value $cleanupContent -Encoding ASCII
Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', "`"$cleanupBat`"") -WindowStyle Hidden
Write-UninstallLog "Verificacao final agendada (auto-apagar em ~60s): $cleanupBat"
Write-Host ''
Write-Host 'Desinstalacao concluida. Verificacao final em background (remove resquicios e apaga scripts).' -ForegroundColor Green
