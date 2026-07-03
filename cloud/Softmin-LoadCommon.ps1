# Carrega Softmin-Common.ps1 a partir da pasta do script ou instalacao.
param([string]$ScriptRoot = $PSScriptRoot)

if (Get-Command Resolve-SoftminInstallPathParam -ErrorAction SilentlyContinue) { return }

foreach ($p in @(
        (Join-Path $ScriptRoot 'Softmin-Common.ps1'),
        (Join-Path (Join-Path $env:LOCALAPPDATA 'Softmin') 'Softmin-Common.ps1')
    )) {
    if ($p -and (Test-Path -LiteralPath $p)) {
        . $p
        return
    }
}
throw 'Softmin-Common.ps1 nao encontrado.'
