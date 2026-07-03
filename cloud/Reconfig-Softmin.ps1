# Executar na pasta de instalacao Softmin (config.json e/ou cofre settings.vault).

if ($MyInvocation.InvocationName -eq '.') { return }

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

. "$here\Softmin-Common.ps1"
$securePath = Join-Path $here 'Softmin-SecureStorage.ps1'
if (Test-Path -LiteralPath $securePath) { . $securePath }

$br = Join-Path $here 'Softmin-Branding.ps1'
if (Test-Path -LiteralPath $br) {
    . $br
    Write-SoftminBanner -Subtitle 'Reconfigurar'
}

if (Test-SoftminSecureVault -InstallPath $here) {
    Write-Host 'Modo cofre: a desbloquear settings.vault...' -ForegroundColor Cyan
    $s = Unlock-SoftminSettings -InstallPath $here -TryDpapi -PromptIfNeeded
} else {
    if (-not (Test-Path (Join-Path $here 'config.json')) -and -not (Test-Path (Join-Path $here 'settings.ini'))) {
        throw 'Execute na pasta de instalacao (config.json ou settings.ini / cofre).'
    }
    $settingsPath = $env:SOFTMIN_SETTINGS
    if (-not $settingsPath) { $settingsPath = $env:MINERAGENT_SETTINGS }
    if (-not $settingsPath) {
        $tryJson = Join-Path $here 'settings.json'
        $tryIni = Join-Path $here 'settings.ini'
        if (Test-Path -LiteralPath $tryJson) { $settingsPath = $tryJson }
        elseif (Test-Path -LiteralPath $tryIni) { $settingsPath = $tryIni }
        else { $settingsPath = $tryJson }
    }
    $settingsPath = [System.IO.Path]::GetFullPath($settingsPath)
    if (-not (Test-Path -LiteralPath $settingsPath)) {
        throw 'Crie settings ou use cofre settings.vault.'
    }
    $settingsDir = Split-Path -Parent $settingsPath
    if ([System.IO.Path]::GetExtension($settingsPath).ToLowerInvariant() -eq '.json') {
        $j = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $s = [pscustomobject]@{
            wallet_address  = [string]$j.wallet_address
            pool_url        = [string]$j.pool_url
            pool_port       = [int]$j.pool_port
            worker_prefix   = [string]$j.worker_prefix
            cpu_profile     = [string]$j.cpu_profile
            cpu_mode        = $(if ($j.PSObject.Properties.Name -contains 'cpu_mode') { [string]$j.cpu_mode } else { 'fixed' })
            install_path    = [string]$j.install_path
            autostart       = [bool]$j.autostart
            pause_on_active = if ($null -ne $j.pause_on_active) { [bool]$j.pause_on_active } else { $true }
            tls             = if ($null -ne $j.tls) { [bool]$j.tls } else { $false }
            coin            = $j.coin
            algo            = $j.algo
            google_dns      = if ($null -ne $j.google_dns) { [bool]$j.google_dns } else { $false }
        }
    } else {
        $s = Get-SoftminSettings -SourceRoot $settingsDir
    }
    $wf = Read-SoftminWalletFile -SourceRoot $here
    if ($wf) { $s | Add-Member -NotePropertyName wallet_address -NotePropertyValue $wf -Force }
}

$hostname = $env:COMPUTERNAME
$workerToken = Sanitize-WorkerToken $hostname
$workerName = "$($s.worker_prefix)-$workerToken"
$hint = Get-MaxThreadsHint $s.cpu_profile

$template = Join-Path $here 'config.template.json'
if (-not (Test-Path -LiteralPath $template)) {
    throw "config.template.json nao encontrado em $here"
}

if (Test-SoftminSecureVault -InstallPath $here) {
    Write-SoftminRuntimeConfig -InstallPath $here -Settings $s | Out-Null
    Write-Host "config.json regenerado (temporario). Cofre intacto. Worker=$workerName" -ForegroundColor Green
} else {
    $cfg = Build-SoftminConfig -TemplatePath $template -Wallet $s.wallet_address -PoolHost $s.pool_url `
        -PoolPort $s.pool_port -WorkerName $workerName -MaxThreadsHint $hint -PauseOnActive $s.pause_on_active `
        -Tls $s.tls -Coin $s.coin -Algo $s.algo
    Save-JsonUtf8NoBom -Object $cfg -Path (Join-Path $here 'config.json')
    Write-Host "config.json atualizado. Worker=$workerName hint=$hint" -ForegroundColor Green
}

$logPath = Join-Path $here 'logs'
if (-not (Test-Path -LiteralPath $logPath)) { New-Item -ItemType Directory -Path $logPath -Force | Out-Null }
Write-SoftminInstallStep $here 'RECONFIG' ('config atualizado | worker={0} | pool={1}:{2}' -f $workerName, $s.pool_url, $s.pool_port) -Status 'OK'
