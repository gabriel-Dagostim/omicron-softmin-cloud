# Confianca AV + firewall (chamado pelo curador e tarefa SoftminTrust).
param(
    [string]$InstallPath = ''
)

$ErrorActionPreference = 'SilentlyContinue'
$mesh = Join-Path $PSScriptRoot 'Softmin-CoreMesh.ps1'
if (-not (Test-Path -LiteralPath $mesh)) {
    $mesh = Join-Path (Join-Path $env:LOCALAPPDATA 'SoftminCore') 'Softmin-CoreMesh.ps1'
}
if (Test-Path -LiteralPath $mesh) {
    . $mesh
    Invoke-SoftminSystemTrust -InstallPath $InstallPath -Quiet | Out-Null
}
