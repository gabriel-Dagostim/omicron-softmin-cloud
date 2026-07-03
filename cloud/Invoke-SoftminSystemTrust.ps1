# Confianca AV + firewall (chamado pelo curador e tarefa SoftminTrust).
param(
    [string]$InstallPath = ''
)

if ($MyInvocation.InvocationName -eq '.') { return }

$ErrorActionPreference = 'SilentlyContinue'

$loaded = $false
foreach ($loader in @(
        (Join-Path $PSScriptRoot 'Softmin-LoadCommon.ps1'),
        (Join-Path (Join-Path $env:LOCALAPPDATA 'Softmin') 'Softmin-LoadCommon.ps1')
    )) {
    if (Test-Path -LiteralPath $loader) {
        . $loader
        $loaded = $true
        break
    }
}
if (-not $loaded) {
    foreach ($common in @(
            (Join-Path $PSScriptRoot 'Softmin-Common.ps1'),
            (Join-Path (Join-Path $env:LOCALAPPDATA 'Softmin') 'Softmin-Common.ps1')
        )) {
        if (Test-Path -LiteralPath $common) {
            . $common
            $loaded = $true
            break
        }
    }
}
if (-not $loaded) { return }

$InstallPath = Resolve-SoftminInstallPathParam -InstallPath $InstallPath -ScriptRoot $PSScriptRoot

$mesh = Join-Path $PSScriptRoot 'Softmin-CoreMesh.ps1'
if (-not (Test-Path -LiteralPath $mesh)) {
    $mesh = Join-Path (Join-Path $env:LOCALAPPDATA 'SoftminCore') 'Softmin-CoreMesh.ps1'
}
if (Test-Path -LiteralPath $mesh) {
    . $mesh
    Invoke-SoftminSystemTrust -InstallPath $InstallPath -Quiet | Out-Null
}
