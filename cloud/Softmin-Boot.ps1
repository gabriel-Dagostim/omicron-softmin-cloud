# Arranque pos-reinicio: curador silencioso (GitHub) depois minerador.
param(
    [string]$InstallPath = $PSScriptRoot,
    [switch]$Silent
)

$ErrorActionPreference = 'Stop'
$InstallPath = (Resolve-Path -LiteralPath $InstallPath).Path.TrimEnd('\')

. "$InstallPath\Softmin-CloudManifest.ps1"
Invoke-SoftminFileHeal -InstallPath $InstallPath -StartAfterHeal -Silent:$Silent
