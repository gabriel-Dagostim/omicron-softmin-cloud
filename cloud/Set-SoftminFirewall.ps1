# Regras de firewall Windows para outbound do Softmin (requer admin).
param(
    [string]$InstallPath = '',
    [string]$PoolHost = '',
    [int]$PoolPort = 443,
    [switch]$ElevatedRetry
)

if ($MyInvocation.InvocationName -eq '.') { return }

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Softmin-LoadCommon.ps1')
$InstallPath = Resolve-SoftminInstallPathParam -InstallPath $InstallPath -ScriptRoot $PSScriptRoot

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    if (-not $ElevatedRetry) {
        $elevPs = Join-Path $PSScriptRoot 'Softmin-Elevation.ps1'
        if (Test-Path -LiteralPath $elevPs) {
            . $elevPs
            Write-Host '[ADMIN] A pedir permissoes para firewall (UAC)...' -ForegroundColor Yellow
            $argList = @('-InstallPath', "`"$InstallPath`"", '-ElevatedRetry')
            if ($PoolHost) { $argList += '-PoolHost', "`"$PoolHost`"" }
            if ($PoolPort -gt 0) { $argList += '-PoolPort', $PoolPort }
            $r = Invoke-SoftminElevated -ScriptPath $PSCommandPath -ArgumentList $argList `
                -Reason 'Criar regras de firewall para Softmin.'
            if ($r.Ok) {
                return @{ Ok = $true; Message = 'Firewall: regras criadas (admin).' }
            }
            return @{ Ok = $false; Message = $(if ($r.Message) { $r.Message } else { 'Firewall: requer administrador.' }) }
        }
    }
    return @{ Ok = $false; Message = 'Firewall: requer administrador.' }
}

$installPath = Assert-SoftminInstallPath $InstallPath
$exe = Join-Path $installPath 'bin\softmin.exe'
$rules = [System.Collections.Generic.List[string]]::new()

try {
    if (Test-Path -LiteralPath $exe) {
        $name = 'Softmin-Outbound-Program'
        $existing = Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue
        if ($existing) { Remove-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue }
        New-NetFirewallRule -DisplayName $name -Direction Outbound -Action Allow `
            -Program $exe -Profile Any -Enabled True | Out-Null
        [void]$rules.Add($name)
    }

    if ($PoolHost -and $PoolPort -gt 0) {
        $name2 = 'Softmin-Pool-Outbound'
        $existing2 = Get-NetFirewallRule -DisplayName $name2 -ErrorAction SilentlyContinue
        if ($existing2) { Remove-NetFirewallRule -DisplayName $name2 -ErrorAction SilentlyContinue }
        New-NetFirewallRule -DisplayName $name2 -Direction Outbound -Action Allow `
            -Protocol TCP -RemotePort $PoolPort -Profile Any -Enabled True | Out-Null
        [void]$rules.Add($name2)
    }

    return @{ Ok = $true; Message = ('Firewall: regras criadas ({0})' -f ($rules -join ', ')) }
} catch {
    return @{ Ok = $false; Message = ('Firewall falhou: {0}' -f $_.Exception.Message) }
}
