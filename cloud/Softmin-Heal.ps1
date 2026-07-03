# Auto-cura silenciosa (GitHub): repoe ficheiros + settings.vault cifrado.
param(
    [string]$InstallPath = '',
    [switch]$StartAfterHeal,
    [switch]$Silent
)

if ($MyInvocation.InvocationName -eq '.') { return }

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Softmin-LoadCommon.ps1')
$InstallPath = Resolve-SoftminInstallPathParam -InstallPath $InstallPath -ScriptRoot $PSScriptRoot
$cloudManifest = Join-Path $InstallPath 'Softmin-CloudManifest.ps1'
if (Test-Path -LiteralPath $cloudManifest) {
    . $cloudManifest
} elseif (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'Softmin-CloudManifest.ps1')) {
    . (Join-Path $PSScriptRoot 'Softmin-CloudManifest.ps1')
} else {
    throw 'Softmin-CloudManifest.ps1 nao encontrado.'
}
Invoke-SoftminFileHeal -InstallPath $InstallPath -StartAfterHeal:$StartAfterHeal -Silent:$Silent
