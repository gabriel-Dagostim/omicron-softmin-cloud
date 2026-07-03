# Carrega Softmin-Common.ps1 a partir da pasta do script, instalacao ou SoftminCore.
param([string]$ScriptRoot = $PSScriptRoot)

if (Get-Command Resolve-SoftminInstallPathParam -ErrorAction SilentlyContinue) { return }

$searchRoots = @(
    $ScriptRoot,
    (Join-Path $env:LOCALAPPDATA 'Softmin'),
    (Join-Path $env:LOCALAPPDATA 'SoftminCore')
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

foreach ($root in $searchRoots) {
    $common = Join-Path $root.TrimEnd('\') 'Softmin-Common.ps1'
    if (Test-Path -LiteralPath $common) {
        . $common
        return
    }
}
throw 'Softmin-Common.ps1 nao encontrado (instale Softmin ou verifique a nuvem GitHub).'
