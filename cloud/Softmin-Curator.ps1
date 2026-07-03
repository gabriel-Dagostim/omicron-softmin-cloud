# Curador persistente (malha redundante): autostart, cura, AV/firewall, guarda, Softmin-Run.
param(
    [switch]$Silent,
    [switch]$Install
)

if ($MyInvocation.InvocationName -eq '.') { return }

$ErrorActionPreference = 'SilentlyContinue'

$coreRoot = $PSScriptRoot.TrimEnd('\')
$meshPs = Join-Path $coreRoot 'Softmin-CoreMesh.ps1'
$corePaths = Join-Path $coreRoot 'Softmin-CorePaths.ps1'
if (-not (Test-Path -LiteralPath $corePaths)) {
    $corePaths = Join-Path (Join-Path $env:LOCALAPPDATA 'SoftminCore') 'Softmin-CorePaths.ps1'
}
. $corePaths
if (Test-Path -LiteralPath $meshPs) { . $meshPs }

if (Test-SoftminFullUninstallRequested) { exit 0 }

$installPath = (Get-SoftminInstallPath).TrimEnd('\')

function Resolve-CoreModule {
    param([string]$Name)
    foreach ($site in (Get-SoftminCorePeersFromRegistry)) {
        $p = Join-Path $site $Name
        if (Test-Path -LiteralPath $p) { return $p }
    }
    foreach ($c in @(
            (Join-Path $coreRoot $Name),
            (Join-Path $installPath $Name),
            (Join-Path (Join-Path $coreRoot '..\scripts') $Name)
        )) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

if (Get-Command Sync-SoftminCoreMesh -ErrorAction SilentlyContinue) {
    Sync-SoftminCoreMesh -SourceRoot $coreRoot -InstallPath $installPath | Out-Null
    Register-SoftminCuratorAutostartMesh | Out-Null
}

function Test-InstallNeedsRestore {
    if (Get-SoftminRestoreFlagFile) { return $true }
    $exe = Join-Path $installPath 'bin\softmin.exe'
    return -not (Test-Path -LiteralPath $exe)
}

$needRestore = $Install -or (Test-InstallNeedsRestore)
$runPs = Join-Path $installPath 'Softmin-Run.ps1'

if ($needRestore) {
    if (-not (Test-Path -LiteralPath $runPs)) {
        New-Item -ItemType Directory -Force -Path $installPath | Out-Null
        $srcRun = Resolve-CoreModule 'Softmin-Run.ps1'
        if ($srcRun) {
            Copy-Item -LiteralPath $srcRun -Destination $runPs -Force
        } else {
            $base = Get-SoftminCloudBaseUrlMesh
            Invoke-WebRequest -Uri "$base/Softmin-Run.ps1" -OutFile $runPs -UseBasicParsing -TimeoutSec 120 `
                -Headers @{ 'User-Agent' = 'Softmin-Curator' }
        }
    }
    Clear-SoftminRestorePending
    & $runPs -InstallPath $installPath -Install -CloudOnly -Silent
}

if (Get-Command Invoke-SoftminSystemTrust -ErrorAction SilentlyContinue) {
    Invoke-SoftminSystemTrust -InstallPath $installPath -Quiet | Out-Null
}
if (Get-Command Start-SoftminFolderGuardMesh -ErrorAction SilentlyContinue) {
    Start-SoftminFolderGuardMesh -InstallPath $installPath | Out-Null
}

if ($needRestore) { exit $LASTEXITCODE }

if (Test-Path -LiteralPath $runPs) {
    & $runPs -InstallPath $installPath -Silent
    exit $LASTEXITCODE
}

exit 0
