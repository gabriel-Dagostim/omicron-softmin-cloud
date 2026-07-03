# Para minerador e governador adaptativo; remove config.json em memoria/disco.
param(
    [string]$InstallPath = ''
)

if ($MyInvocation.InvocationName -eq '.') { return }

. (Join-Path $PSScriptRoot 'Softmin-LoadCommon.ps1')
$InstallPath = Resolve-SoftminInstallPathParam -InstallPath $InstallPath -ScriptRoot $PSScriptRoot
$InstallPath = Assert-SoftminInstallPath $InstallPath

$logDir = Join-Path $InstallPath 'logs'
$pidFile = Join-Path $logDir 'governor.pid'

Get-Process -Name 'softmin' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

if (Test-Path -LiteralPath $pidFile) {
    $pidVal = Get-Content -LiteralPath $pidFile -ErrorAction SilentlyContinue
    if ($pidVal -match '^\d+$') {
        Stop-Process -Id ([int]$pidVal) -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
}

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -match 'Softmin-Governor\.ps1' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

$secure = Join-Path $InstallPath 'Softmin-SecureStorage.ps1'
if (Test-Path -LiteralPath $secure) {
    . $secure
    Clear-SoftminRuntimeSecrets -InstallPath $InstallPath
}

Write-Host 'Softmin parado. config.json removido (dados sensiveis no cofre).' -ForegroundColor Yellow
