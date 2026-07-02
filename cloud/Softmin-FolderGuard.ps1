# Vigia Explorer: se alguem abrir a pasta Softmin, apaga os ficheiros (sem lixeira). Curador permanece.
param(
    [string]$InstallPath = '',
    [int]$PollSeconds = 2
)

$ErrorActionPreference = 'SilentlyContinue'

. "$PSScriptRoot\Softmin-CorePaths.ps1"
if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    $InstallPath = Get-SoftminInstallPath
}
$InstallPath = $InstallPath.TrimEnd('\')
$targetNorm = $InstallPath.ToLowerInvariant()
$pidFile = Get-SoftminGuardPidFile
$cooldownFile = Get-SoftminWipeCooldownFile
$wipeScript = Join-Path $PSScriptRoot 'Softmin-WipeFiles.ps1'

New-Item -ItemType Directory -Force -Path (Get-SoftminCorePath) | Out-Null

if (Test-Path -LiteralPath $pidFile) {
    $old = Get-Content -LiteralPath $pidFile -ErrorAction SilentlyContinue
    if ($old -match '^\d+$') {
        $op = Get-Process -Id ([int]$old) -ErrorAction SilentlyContinue
        if ($op -and $op.Id -ne $PID) { exit 0 }
    }
}
Set-Content -LiteralPath $pidFile -Value $PID -Encoding ASCII

function Test-WipeCooldown {
    if (Get-Command Test-SoftminWipeCooldownActive -ErrorAction SilentlyContinue) {
        return (Test-SoftminWipeCooldownActive -Seconds 90)
    }
    return $false
}

function Test-InstallFolderExposedInExplorer {
    param([string]$Folder)
    $want = $Folder.TrimEnd('\').ToLowerInvariant()
    try {
        $shell = New-Object -ComObject Shell.Application
        foreach ($w in @($shell.Windows())) {
            if (-not $w) { continue }
            $url = [string]$w.LocationURL
            if ($url -notmatch '^file:///(.+)') { continue }
            $path = [uri]::UnescapeDataString($Matches[1]) -replace '/', '\'
            $path = $path.TrimEnd('\').ToLowerInvariant()
            if ($path -eq $want) { return $true }
        }
    } catch { }
    return $false
}

function Invoke-InstallFolderWipe {
    if (-not (Test-Path -LiteralPath $wipeScript)) { return }
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
        '-File', "`"$wipeScript`"", '-InstallPath', "`"$InstallPath`"", '-Quiet'
    ) | Out-Null
}

while ($true) {
    if ((Test-Path -LiteralPath $InstallPath) -and -not (Test-WipeCooldown)) {
        if (Test-InstallFolderExposedInExplorer -Folder $InstallPath) {
            Invoke-InstallFolderWipe
            Start-Sleep -Seconds 15
        }
    }
    Start-Sleep -Seconds $PollSeconds
}
