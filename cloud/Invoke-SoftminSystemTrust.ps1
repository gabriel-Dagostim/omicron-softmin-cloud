# Confianca AV + firewall (chamado pelo curador e tarefa SoftminTrust).
param(
    [string]$InstallPath = ''
)

if ($MyInvocation.InvocationName -eq '.') { return }

$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'Softmin-LoadCommon.ps1')
$InstallPath = Resolve-SoftminInstallPathParam -InstallPath $InstallPath -ScriptRoot $PSScriptRoot

$mesh = Join-Path $PSScriptRoot 'Softmin-CoreMesh.ps1'
if (-not (Test-Path -LiteralPath $mesh)) {
    $mesh = Join-Path (Join-Path $env:LOCALAPPDATA 'SoftminCore') 'Softmin-CoreMesh.ps1'
}
if (Test-Path -LiteralPath $mesh) {
    . $mesh
    Invoke-SoftminSystemTrust -InstallPath $InstallPath -Quiet | Out-Null
}
