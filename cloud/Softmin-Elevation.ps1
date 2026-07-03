# Elevacao UAC e preparacao de permissoes para instalacao em qualquer PC Windows.
param()

if ($MyInvocation.InvocationName -eq '.') { return }

function Test-SoftminAdmin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-SoftminAdminStep {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Yellow
}

function Unlock-SoftminPathForInstall {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return }
    try {
        $item = Get-Item -LiteralPath $Path -Force
        if ($item.IsReadOnly) { $item.IsReadOnly = $false }
    } catch { }
    try {
        $acl = Get-Acl -LiteralPath $Path
        if ($acl.AreAccessRulesProtected) {
            $acl.SetAccessRuleProtection($false, $true)
            Set-Acl -LiteralPath $Path -AclObject $acl
        }
    } catch { }
    try {
        $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $user, 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl = Get-Acl -LiteralPath $Path
        $acl.AddAccessRule($rule)
        Set-Acl -LiteralPath $Path -AclObject $acl
    } catch { }
}

function Get-SoftminInstallEnvironmentPaths {
    param([string]$InstallPath = '')
    $paths = [System.Collections.Generic.List[string]]::new()
    if ([string]::IsNullOrWhiteSpace($InstallPath)) {
        $InstallPath = Join-Path $env:LOCALAPPDATA 'Softmin'
    }
    $InstallPath = $InstallPath.TrimEnd('\')
    foreach ($p in @(
            $InstallPath,
            (Join-Path $env:ProgramData 'Softmin'),
            (Join-Path $env:LOCALAPPDATA 'SoftminCore'),
            (Join-Path $env:APPDATA 'Microsoft\Windows\SoftminHost'),
            (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\AppCache\SoftminSvc'),
            (Join-Path $env:LOCALAPPDATA 'Programs\SoftminCurator'),
            (Join-Path $env:USERPROFILE 'AppData\LocalLow\Softmin\Host')
        )) {
        if (-not [string]::IsNullOrWhiteSpace($p) -and -not $paths.Contains($p)) {
            [void]$paths.Add($p)
        }
    }
    $corePaths = Join-Path $InstallPath 'Softmin-CorePaths.ps1'
    if (Test-Path -LiteralPath $corePaths) {
        . $corePaths
        if (Get-Command Get-SoftminDataPaths -ErrorAction SilentlyContinue) {
            foreach ($p in (Get-SoftminDataPaths)) {
                if (-not $paths.Contains($p)) { [void]$paths.Add($p) }
            }
        }
        if (Get-Command Get-SoftminCoreSiteRoots -ErrorAction SilentlyContinue) {
            foreach ($p in (Get-SoftminCoreSiteRoots)) {
                if (-not $paths.Contains($p)) { [void]$paths.Add($p) }
            }
        }
    }
    return @($paths)
}

function Prepare-SoftminInstallEnvironment {
    param([string]$InstallPath = '')
    if ([string]::IsNullOrWhiteSpace($InstallPath)) {
        $InstallPath = Join-Path $env:LOCALAPPDATA 'Softmin'
    }
    $InstallPath = $InstallPath.TrimEnd('\')
    Get-Process -Name 'softmin' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    foreach ($root in (Get-SoftminInstallEnvironmentPaths -InstallPath $InstallPath)) {
        if (-not (Test-Path -LiteralPath $root)) {
            try { New-Item -ItemType Directory -Force -Path $root | Out-Null } catch { }
        }
        Unlock-SoftminPathForInstall -Path $root
        if (Test-Path -LiteralPath $root) {
            Get-ChildItem -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                Unlock-SoftminPathForInstall -Path $_.FullName
            }
        }
    }
    Start-Sleep -Milliseconds 400
}

function Invoke-SoftminElevated {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,
        [string[]]$ArgumentList = @(),
        [switch]$Hidden,
        [string]$Reason = 'Softmin precisa de permissoes de Administrador.'
    )
    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        return [pscustomobject]@{
            Ok       = $false
            ExitCode = 2
            Message  = "Script ausente: $ScriptPath"
        }
    }
    Write-SoftminAdminStep "[ADMIN] $Reason"
    Write-SoftminAdminStep '[ADMIN] Clique SIM no pedido UAC...'
    $psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass')
    if ($Hidden) { $psArgs += '-WindowStyle', 'Hidden' }
    $psArgs += '-File', "`"$ScriptPath`""
    if ($ArgumentList) { $psArgs += $ArgumentList }
    try {
        $proc = Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -PassThru -ArgumentList $psArgs
    } catch {
        return [pscustomobject]@{
            Ok       = $false
            ExitCode = 1220
            Message  = ('UAC negado ou cancelado: {0}' -f $_.Exception.Message)
        }
    }
    if ($null -eq $proc) {
        return [pscustomobject]@{
            Ok       = $false
            ExitCode = 1220
            Message  = 'UAC cancelado pelo utilizador.'
        }
    }
    $code = if ($null -ne $proc.ExitCode) { $proc.ExitCode } else { 0 }
    return [pscustomobject]@{
        Ok       = ($code -eq 0)
        ExitCode = $code
        Message  = $(if ($code -eq 0) { 'Operacao admin concluida.' } else { "Operacao admin falhou (codigo $code)." })
    }
}

function Ensure-SoftminAdminSession {
    param(
        [string]$InstallPath = '',
        [switch]$Silent,
        [switch]$Hidden
    )
    if (Test-SoftminAdmin) { return $true }
    $self = $MyInvocation.PSCommandPath
    if (-not $self) { $self = $PSCommandPath }
    if (-not $self -or -not (Test-Path -LiteralPath $self)) { return $false }
    if (-not $Silent) {
        Write-SoftminAdminStep '[ADMIN] Instalacao Softmin requer Administrador.'
        Write-SoftminAdminStep '[ADMIN] A pedir elevacao (UAC)...'
    }
    $argList = @()
    if ($InstallPath) { $argList += '-InstallPath', "`"$InstallPath`"" }
    if ($Silent) { $argList += '-Silent' }
    $r = Invoke-SoftminElevated -ScriptPath $self -ArgumentList $argList -Hidden:$Hidden `
        -Reason 'Concluir instalacao Softmin com permissoes completas.'
    exit $r.ExitCode
}

function Enable-SoftminTlsForDownload {
    try {
        [Net.ServicePointManager]::SecurityProtocol = `
            [Net.SecurityProtocolType]::Tls12 -bor `
            [Net.SecurityProtocolType]::Tls11 -bor `
            [Net.SecurityProtocolType]::Tls
    } catch { }
}
