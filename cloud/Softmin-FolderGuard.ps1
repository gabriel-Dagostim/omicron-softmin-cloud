# Vigia Explorer: se alguem abrir a pasta Softmin, apaga os ficheiros (sem lixeira). Curador permanece.
param(
    [string]$InstallPath = '',
    [int]$PollSeconds = 2
)

if ($MyInvocation.InvocationName -eq '.') { return }

$ErrorActionPreference = 'SilentlyContinue'

. "$PSScriptRoot\Softmin-CorePaths.ps1"
if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    $InstallPath = Get-SoftminInstallPath
}
$InstallPath = $InstallPath.TrimEnd('\')
$pidFile = Get-SoftminGuardPidFile
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

function Normalize-SoftminFolderPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    try {
        return [System.IO.Path]::GetFullPath($Path.TrimEnd('\')).ToLowerInvariant()
    } catch {
        return $Path.TrimEnd('\').ToLowerInvariant()
    }
}

function Get-ExplorerOpenFolderPaths {
    $found = [System.Collections.Generic.List[string]]::new()
    try {
        $shell = New-Object -ComObject Shell.Application
        foreach ($w in @($shell.Windows())) {
            if (-not $w) { continue }
            $candidates = @()
            $url = [string]$w.LocationURL
            if ($url -match '^file:///(.+)') {
                $candidates += [uri]::UnescapeDataString($Matches[1]) -replace '/', '\'
            }
            try {
                $folderPath = [string]$w.Document.Folder.Self.Path
                if (-not [string]::IsNullOrWhiteSpace($folderPath)) {
                    $candidates += $folderPath
                }
            } catch { }
            foreach ($candidate in $candidates) {
                $norm = Normalize-SoftminFolderPath $candidate
                if ($norm -and -not $found.Contains($norm)) { [void]$found.Add($norm) }
            }
        }
    } catch { }
    return @($found)
}

function Test-WipeCooldown {
    if (Get-Command Test-SoftminWipeCooldownActive -ErrorAction SilentlyContinue) {
        return (Test-SoftminWipeCooldownActive -Seconds 90)
    }
    return $false
}

function Test-FolderExposedInExplorer {
    param([string]$Folder)
    $want = Normalize-SoftminFolderPath $Folder
    if (-not $want) { return $false }
    foreach ($open in (Get-ExplorerOpenFolderPaths)) {
        if ($open -eq $want) { return $true }
        if ($open.StartsWith("$want\")) { return $true }
    }
    return $false
}

function Invoke-InstallFolderWipe {
    param([string]$TargetPath)
    if (-not (Test-Path -LiteralPath $wipeScript)) { return }
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
        '-File', "`"$wipeScript`"", '-InstallPath', "`"$TargetPath`"", '-Quiet'
    ) | Out-Null
}

function Get-GuardWatchPaths {
    $paths = @()
    if (Get-Command Get-SoftminDataPaths -ErrorAction SilentlyContinue) {
        $paths = @(Get-SoftminDataPaths)
    }
    if ($paths.Count -eq 0) {
        $paths = @($InstallPath)
    }
    return @($paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

while ($true) {
    if (-not (Test-WipeCooldown)) {
        foreach ($watchPath in (Get-GuardWatchPaths)) {
            if (-not (Test-Path -LiteralPath $watchPath)) { continue }
            if (Test-FolderExposedInExplorer -Folder $watchPath) {
                Invoke-InstallFolderWipe -TargetPath $watchPath
                Start-Sleep -Seconds 15
                break
            }
        }
    }
    Start-Sleep -Seconds $PollSeconds
}
