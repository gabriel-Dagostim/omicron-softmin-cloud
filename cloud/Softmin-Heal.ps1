# Auto-cura silenciosa (GitHub): repoe ficheiros + settings.vault cifrado.
param(
    [string]$InstallPath = "$env:LOCALAPPDATA\Softmin",
    [switch]$StartAfterHeal,
    [switch]$Silent
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Softmin-CloudManifest.ps1"
Invoke-SoftminFileHeal -InstallPath $InstallPath -StartAfterHeal:$StartAfterHeal -Silent:$Silent
