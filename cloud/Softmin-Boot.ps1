# Encaminha para o script unico Softmin-Run.ps1
param(
    [string]$InstallPath = '',
    [switch]$Silent
)

if ($MyInvocation.InvocationName -eq '.') { return }

. (Join-Path $PSScriptRoot 'Softmin-LoadCommon.ps1')
$InstallPath = Resolve-SoftminInstallPathParam -InstallPath $InstallPath -ScriptRoot $PSScriptRoot

$run = Join-Path $InstallPath 'Softmin-Run.ps1'
if (-not (Test-Path -LiteralPath $run)) {
    $run = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\Softmin-Run.ps1'
}
& $run -InstallPath $InstallPath -Silent:$Silent
