# Apaga permanentemente a pasta de dados Softmin (sem lixeira). Nao remove curador/autostart.
param(
    [string]$InstallPath = '',
    [switch]$Quiet
)

$ErrorActionPreference = 'SilentlyContinue'

$corePaths = Join-Path $PSScriptRoot 'Softmin-CorePaths.ps1'
if (Test-Path -LiteralPath $corePaths) { . $corePaths }
if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    $InstallPath = Get-SoftminInstallPath
}
$InstallPath = $InstallPath.TrimEnd('\')
$corePath = Get-SoftminCorePath

function Write-WipeMsg {
    param([string]$Msg)
    if (-not $Quiet) { Write-Host $Msg -ForegroundColor DarkGray }
}

function Stop-SoftminInstallProcesses {
    param([string]$Root)
    foreach ($name in @('softmin')) {
        Get-Process -Name $name -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                if ($_.Path -and ($_.Path -like "$Root*")) {
                    Stop-Process -Id $_.Id -Force -ErrorAction Stop
                }
            } catch { }
        }
    }
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        ForEach-Object {
            $cmd = [string]$_.CommandLine
            if ($cmd -match [regex]::Escape($Root) -and $cmd -match 'Softmin-Governor|Softmin-Run') {
                Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            }
        }
}

function Remove-PathPermanent {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    try {
        & cmd.exe /c "rd /s /q `"$Path`"" 2>$null | Out-Null
    } catch { }
    if (Test-Path -LiteralPath $Path) {
        try {
            [System.IO.Directory]::Delete($Path, $true)
        } catch {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    return -not (Test-Path -LiteralPath $Path)
}

if ($InstallPath.TrimEnd('\').ToLowerInvariant() -eq $corePath.TrimEnd('\').ToLowerInvariant()) {
    Write-WipeMsg 'Recusado: nao apaga SoftminCore (curador).'
    exit 1
}
if (Get-Command Test-SoftminCoreSitePath -ErrorAction SilentlyContinue) {
    if (Test-SoftminCoreSitePath -Path $InstallPath) {
        Write-WipeMsg 'Recusado: caminho e nucleo curador.'
        exit 1
    }
}

Write-WipeMsg "Wipe permanente: $InstallPath"
Stop-SoftminInstallProcesses -Root $InstallPath
Start-Sleep -Milliseconds 400

$ok = Remove-PathPermanent -Path $InstallPath
if (-not $ok) {
    $cleanupBat = Join-Path $env:TEMP ("Softmin-Wipe-{0}.cmd" -f ([guid]::NewGuid().ToString('N').Substring(0, 8)))
    $bat = @"
@echo off
set RETRIES=8
:loop
set /a RETRIES-=1
taskkill /F /IM softmin.exe 2>nul
timeout /t 1 /nobreak >nul
rd /s /q "$InstallPath" 2>nul
if not exist "$InstallPath" goto done
if %RETRIES% LEQ 0 goto done
goto loop
:done
del /f /q "%~f0" 2>nul
exit /b 0
"@
    Set-Content -Path $cleanupBat -Value $bat -Encoding ASCII
    Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', "`"$cleanupBat`"") -WindowStyle Hidden | Out-Null
    Start-Sleep -Seconds 3
    $ok = -not (Test-Path -LiteralPath $InstallPath)
}
if ($ok) {
    if (Get-Command Set-SoftminRestorePending -ErrorAction SilentlyContinue) {
        Set-SoftminRestorePending -Pending $true
    }
    if (Get-Command Set-SoftminWipeCooldownNow -ErrorAction SilentlyContinue) {
        Set-SoftminWipeCooldownNow
    }
}
exit $(if ($ok) { 0 } else { 1 })
