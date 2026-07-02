# Instala malha redundante de curadores + guarda + confianca AV/firewall.
param(
    [string]$InstallPath = '',
    [string]$ScriptsSource = ''
)

$ErrorActionPreference = 'SilentlyContinue'

$meshPs = Join-Path $PSScriptRoot 'Softmin-CoreMesh.ps1'
if (-not (Test-Path -LiteralPath $meshPs)) {
    $meshPs = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts') 'Softmin-CoreMesh.ps1'
}
$corePaths = Join-Path $PSScriptRoot 'Softmin-CorePaths.ps1'
if (Test-Path -LiteralPath $corePaths) { . $corePaths }

if (Test-Path -LiteralPath $meshPs) {
    . $meshPs
    return (Install-SoftminCoreMesh -InstallPath $InstallPath -ScriptsSource $(if ($ScriptsSource) { $ScriptsSource } else { $PSScriptRoot }))
}

# Fallback legado (um unico nucleo)
. $corePaths
if ([string]::IsNullOrWhiteSpace($InstallPath)) { $InstallPath = Get-SoftminInstallPath }
$corePath = Get-SoftminCorePath
New-Item -ItemType Directory -Force -Path $corePath | Out-Null
return $corePath
