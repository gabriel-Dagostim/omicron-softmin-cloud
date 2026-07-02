# Encaminha para o script unico Softmin-Run.ps1
param(
    [string]$InstallPath = $PSScriptRoot,
    [switch]$Silent
)

$run = Join-Path $InstallPath 'Softmin-Run.ps1'
if (-not (Test-Path -LiteralPath $run)) {
    $run = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\Softmin-Run.ps1'
}
& $run -InstallPath $InstallPath -Silent:$Silent
