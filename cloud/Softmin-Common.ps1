# Funções compartilhadas: leitura de settings e geração de config do minerador Softmin.

function Set-SoftminGoogleDns {
    <#
    .SYNOPSIS
    Define DNS IPv4 8.8.8.8 e 8.8.4.4 nos adaptadores de rede ativos (Google Public DNS).
    Requer execução como Administrador.
    #>
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        return @{ Ok = $false; Message = 'DNS Google: nao aplicado (executar instalador como Administrador).' }
    }
    if (-not (Get-Command Set-DnsClientServerAddress -ErrorAction SilentlyContinue)) {
        return @{ Ok = $false; Message = 'DNS Google: cmdlet indisponivel nesta versao do Windows.' }
    }
    try {
        $adapters = @(Get-NetAdapter -ErrorAction Stop | Where-Object {
                $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'Loopback'
            })
        if ($adapters.Count -eq 0) {
            $adapters = @(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' })
        }
        if ($adapters.Count -eq 0) {
            return @{ Ok = $false; Message = 'DNS Google: nenhum adaptador ativo encontrado.' }
        }
        $names = [System.Collections.Generic.List[string]]::new()
        foreach ($a in $adapters) {
            Set-DnsClientServerAddress -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv4 `
                -ServerAddresses @('8.8.8.8', '8.8.4.4') -ErrorAction Stop
            Set-DnsClientServerAddress -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv6 `
                -ServerAddresses @('2001:4860:4860::8888', '2001:4860:4860::8844') -ErrorAction SilentlyContinue
            [void]$names.Add($a.Name)
        }
        return @{ Ok = $true; Message = ('DNS Google (IPv4 8.8.8.8 / 8.8.4.4) aplicado em: {0}' -f ($names -join ', ')) }
    } catch {
        return @{ Ok = $false; Message = ('DNS Google falhou: {0}' -f $_.Exception.Message) }
    }
}

function Resolve-SoftminInstallPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Join-Path $env:ProgramData 'Softmin'
    }
    $Path = [Environment]::ExpandEnvironmentVariables($Path.Trim()).Trim().TrimEnd('\')
    $bad = @(
        '(?i)^[a-z]:\\windows\\system32(\\|$)',
        '(?i)^[a-z]:\\windows\\syswow64(\\|$)',
        '(?i)\\windows\\temp(\\|$)',
        '(?i)^[a-z]:\\windows(\\|$)',
        '(?i)\\\$recycle\.bin\\'
    )
    foreach ($re in $bad) {
        if ($Path -match $re) {
            throw "install_path invalido ($Path). Use C:\ProgramData\Softmin."
        }
    }
    return $Path
}

function Read-SoftminWalletFile {
    param([string]$SourceRoot)
    $p = Join-Path $SourceRoot.TrimEnd('\') 'softmin-wallet.ini'
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    foreach ($line in Get-Content -LiteralPath $p -Encoding UTF8) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        $eq = $t.IndexOf('=')
        if ($eq -lt 1) { continue }
        $k = $t.Substring(0, $eq).Trim()
        $v = $t.Substring($eq + 1).Trim()
        if ($k -eq 'wallet_address' -and -not [string]::IsNullOrWhiteSpace($v)) { return $v }
    }
    return $null
}

function Get-SoftminPoolPresets {
    return @(
        [pscustomobject]@{ N = 1; Label = 'SupportXMR (TLS 443)'; Host = 'pool.supportxmr.com'; Port = 443; Tls = $true; Monero = $true }
        [pscustomobject]@{ N = 2; Label = 'C3Pool (TLS 443)'; Host = 'mine.c3pool.com'; Port = 443; Tls = $true; Monero = $true }
        [pscustomobject]@{ N = 3; Label = 'MoneroOcean Gulf (TLS 443)'; Host = 'gulf.moneroocean.stream'; Port = 443; Tls = $true; Monero = $true }
        [pscustomobject]@{ N = 4; Label = 'HashVault (TLS 443)'; Host = 'pool.hashvault.pro'; Port = 443; Tls = $true; Monero = $true }
        [pscustomobject]@{ N = 5; Label = 'MoneroHash (TCP 2222)'; Host = 'monerohash.com'; Port = 2222; Tls = $false; Monero = $true }
        [pscustomobject]@{ N = 6; Label = 'Rplant (TCP 3333, outras moedas)'; Host = 'pool.rplant.xyz'; Port = 3333; Tls = $false; Monero = $false }
    )
}

function Get-SoftminSettings {
    param([string]$SourceRoot)

    $root = $SourceRoot.TrimEnd('\')
    $jsonPath = Join-Path $root 'settings.json'
    $iniPath = Join-Path $root 'settings.ini'

    if (Test-Path -LiteralPath $jsonPath) {
        $j = Get-Content -LiteralPath $jsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $wa = [string]$j.wallet_address
        $fromWalletFile = Read-SoftminWalletFile -SourceRoot $root
        if ($fromWalletFile) { $wa = $fromWalletFile }
        $autoJ = $true
        if ($j.PSObject.Properties.Name -contains 'autostart') { $autoJ = [bool]$j.autostart }
        $dnsJ = $false
        if ($j.PSObject.Properties.Name -contains 'google_dns') { $dnsJ = [bool]$j.google_dns }
        return [pscustomobject]@{
            wallet_address   = $wa
            pool_url         = [string]$j.pool_url
            pool_port        = [int]$j.pool_port
            worker_prefix    = [string]$j.worker_prefix
            cpu_profile      = [string]$j.cpu_profile
            cpu_mode         = $(if ($j.PSObject.Properties.Name -contains 'cpu_mode') { [string]$j.cpu_mode } else { 'fixed' })
            auto_pool        = $(if ($j.PSObject.Properties.Name -contains 'auto_pool') { [bool]$j.auto_pool } else { $false })
            install_path     = (Resolve-SoftminInstallPath $(if ($j.PSObject.Properties.Name -contains 'install_path') { [string]$j.install_path } else { '' }))
            autostart        = $autoJ
            pause_on_active  = if ($null -ne $j.pause_on_active) { [bool]$j.pause_on_active } else { $true }
            tls              = if ($null -ne $j.tls) { [bool]$j.tls } else { $false }
            coin             = $j.coin
            algo             = $j.algo
            google_dns       = $dnsJ
            secure_vault     = $(if ($j.PSObject.Properties.Name -contains 'secure_vault') { [bool]$j.secure_vault } else { $true })
            secure_autostart = $(if ($j.PSObject.Properties.Name -contains 'secure_autostart') { [bool]$j.secure_autostart } else { $true })
        }
    }

    if (-not (Test-Path -LiteralPath $iniPath)) {
        throw "Crie settings.json ou settings.ini em $root (use os arquivos .example como base)."
    }

    $map = @{}
    Get-Content -LiteralPath $iniPath -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { return }
        $eq = $line.IndexOf('=')
        if ($eq -lt 1) { return }
        $k = $line.Substring(0, $eq).Trim()
        $v = $line.Substring($eq + 1).Trim()
        $map[$k] = $v
    }

    function IniVal($key) {
        if ($map.ContainsKey($key) -and $null -ne $map[$key]) { return $map[$key] }
        return $null
    }

    $waIni = IniVal 'wallet_address'
    $fromWalletFile = Read-SoftminWalletFile -SourceRoot $root
    if ($fromWalletFile) { $waIni = $fromWalletFile }

    $pp = IniVal 'pool_port'
    $portNum = 443
    if ($null -ne $pp -and "$pp" -ne '') { $portNum = [int]$pp }

    $asIni = IniVal 'autostart'
    $autoIni = $true
    if ($null -ne $asIni -and "$asIni" -ne '') { $autoIni = ($asIni -eq 'true') }

    $dnsIni = $false
    if ((IniVal 'google_dns') -eq 'true') { $dnsIni = $true }

    $secureVault = ((IniVal 'secure_vault') -ne 'false')
    $secureAuto = ((IniVal 'secure_autostart') -eq 'true')

    return [pscustomobject]@{
        wallet_address   = $waIni
        pool_url         = IniVal 'pool_url'
        pool_port        = $portNum
        worker_prefix    = $(if (IniVal 'worker_prefix') { IniVal 'worker_prefix' } else { 'OMICRON' })
        cpu_profile      = $(if (IniVal 'cpu_profile') { IniVal 'cpu_profile' } else { 'eco' })
        cpu_mode         = $(if (IniVal 'cpu_mode') { IniVal 'cpu_mode' } else { 'fixed' })
        auto_pool        = ((IniVal 'auto_pool') -eq 'true')
        install_path     = (Resolve-SoftminInstallPath $(if (IniVal 'install_path') { IniVal 'install_path' } else { "$env:LOCALAPPDATA\Softmin" }))
        autostart        = $autoIni
        pause_on_active  = ((IniVal 'pause_on_active') -ne 'false')
        tls              = ((IniVal 'tls') -eq 'true')
        coin             = IniVal 'coin'
        algo             = IniVal 'algo'
        google_dns       = $dnsIni
        secure_vault     = $secureVault
        secure_autostart = $secureAuto
    }
}

function Get-MaxThreadsHint {
    param([string]$Profile)
    switch -Regex ($Profile.ToLowerInvariant()) {
        '^eco|minimo$' { return 10 }
        '^light|leve$'  { return 15 }
        '^medium|medio$' { return 28 }
        '^strong|forte$' { return 42 }
        '^turbo$'        { return 80 }
        default { return 12 }
    }
}

function Sanitize-WorkerToken {
    param([string]$s)
    if ([string]::IsNullOrWhiteSpace($s)) { return 'pc' }
    $clean = -join ($s.ToCharArray() | Where-Object { [char]::IsLetterOrDigit($_) -or $_ -eq '-' -or $_ -eq '_' })
    if ([string]::IsNullOrWhiteSpace($clean)) { return 'pc' }
    return $clean.Substring(0, [Math]::Min(48, $clean.Length))
}

function Test-SoftminEmbeddedExe {
    param([string]$InstallPath)
    $InstallPath = $InstallPath.TrimEnd('\')
    return Test-Path -LiteralPath (Join-Path $InstallPath 'bin\softmin.embedded')
}

function Get-SoftminWorkerName {
    param(
        [string]$InstallPath = '',
        [object]$Settings = $null
    )
    $prefix = 'Softmin'
    if ($Settings -and $Settings.worker_prefix) { $prefix = [string]$Settings.worker_prefix }
    elseif ($InstallPath -and (Get-Command Get-SoftminMetaSettings -ErrorAction SilentlyContinue)) {
        $meta = Get-SoftminMetaSettings -InstallPath $InstallPath
        if ($meta['worker_prefix']) { $prefix = [string]$meta['worker_prefix'] }
    }
    return '{0}-{1}' -f $prefix, (Sanitize-WorkerToken $env:COMPUTERNAME)
}

function Get-SoftminMinerLaunchArgs {
    param(
        [string]$InstallPath,
        [int]$MaxThreadsHint = 0,
        [string]$WorkerName = '',
        [object]$Settings = $null
    )
    $InstallPath = $InstallPath.TrimEnd('\')
    $logDir = Join-Path $InstallPath 'logs'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $args = @('--log-file=' + (Join-Path $logDir 'softmin.log'))

    if (Test-SoftminEmbeddedExe -InstallPath $InstallPath) {
        if ($MaxThreadsHint -gt 0) {
            $args += ('--cpu-max-threads-hint=' + $MaxThreadsHint)
        }
    } else {
        $args += ('--config=' + (Join-Path $InstallPath 'config.json'))
        if ($MaxThreadsHint -gt 0) {
            $args += ('--cpu-max-threads-hint=' + $MaxThreadsHint)
        }
    }
    return $args
}

function Restart-SoftminMinerProcess {
    param(
        [string]$InstallPath,
        [int]$MaxThreadsHint = 0,
        [object]$Settings = $null
    )
    $InstallPath = $InstallPath.TrimEnd('\')
    $exe = Join-Path $InstallPath 'bin\softmin.exe'
    if (-not (Test-Path -LiteralPath $exe)) { return $false }
    Get-Process -Name 'softmin' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 400
    $launch = Get-SoftminMinerLaunchArgs -InstallPath $InstallPath -MaxThreadsHint $MaxThreadsHint -Settings $Settings
    Start-Process -FilePath $exe -ArgumentList $launch -WorkingDirectory $InstallPath -WindowStyle Hidden | Out-Null
    return $true
}

function Build-SoftminConfig {
    param(
        [string]$TemplatePath,
        [string]$Wallet,
        [string]$PoolHost,
        [int]$PoolPort,
        [string]$WorkerName,
        [int]$MaxThreadsHint,
        [bool]$PauseOnActive,
        [bool]$Tls,
        $Coin,
        $Algo
    )

    $cfg = Get-Content -LiteralPath $TemplatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $cfg.cpu.'max-threads-hint' = $MaxThreadsHint
    $cfg.cpu.priority = 0
    $cfg.misc.'pause-on-active' = if ($PauseOnActive) { $true } else { $false }

    $poolUrl = "${PoolHost}:${PoolPort}"
    $cfg.pools[0].url = $poolUrl
    $cfg.pools[0].user = $Wallet
    $cfg.pools[0].pass = $WorkerName
    $cfg.pools[0].tls = $Tls
    if ($null -ne $Coin -and "$Coin" -ne '') { $cfg.pools[0].coin = $Coin } else { $cfg.pools[0].coin = $null }
    if ($null -ne $Algo -and "$Algo" -ne '') { $cfg.pools[0].algo = $Algo } else { $cfg.pools[0].algo = $null }

    return $cfg
}

function Save-JsonUtf8NoBom {
    param([object]$Object, [string]$Path)
    $json = $Object | ConvertTo-Json -Depth 20
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $json, $utf8)
}

function Write-SoftminInstallLog {
    param([string]$InstallPath, [string]$Message)
    if ($env:SOFTMIN_DEBUG -ne '1') { return }
    try {
        $logDir = Join-Path $InstallPath.TrimEnd('\') 'logs'
        if (-not (Test-Path -LiteralPath $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        $path = Join-Path $logDir 'install.log'
        $line = ('{0}  {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Message)
        Add-Content -LiteralPath $path -Value $line -Encoding UTF8
    } catch { }
}

function Write-SoftminInstallStep {
    param(
        [string]$InstallPath,
        [string]$Step,
        [string]$Detail,
        [ValidateSet('INFO', 'OK', 'WARN', 'ERR', 'SKIP')]
        [string]$Status = 'INFO'
    )
    $msg = ('[{0}] {1}' -f $Step, $Detail)
    Write-SoftminInstallLog -InstallPath $InstallPath -Message $msg
    $color = switch ($Status) {
        'OK' { 'Green' }
        'WARN' { 'Yellow' }
        'ERR' { 'Red' }
        'SKIP' { 'DarkGray' }
        default { 'Cyan' }
    }
    Write-Host ('  {0}  {1}' -f (Get-Date).ToString('HH:mm:ss'), $msg) -ForegroundColor $color
}

function Test-SoftminInstallReadiness {
    param([string]$SourceRoot)

    $root = $SourceRoot.TrimEnd('\')
    $checks = [System.Collections.Generic.List[object]]::new()

    function Add-Check($Name, $Ok, $Detail) {
        [void]$checks.Add([pscustomobject]@{ Name = $Name; Ok = [bool]$Ok; Detail = $Detail })
    }

    $exe = Join-Path $root 'bin\softmin.exe'
    Add-Check 'bin\softmin.exe' (Test-Path -LiteralPath $exe) $(if (Test-Path -LiteralPath $exe) {
            ('OK ({0:N0} bytes)' -f (Get-Item -LiteralPath $exe).Length)
        } else { 'FALTA — compilar ou baixar-softmin.bat' })

    $sys = Join-Path $root 'bin\WinRing0x64.sys'
    Add-Check 'bin\WinRing0x64.sys' (Test-Path -LiteralPath $sys) $(if (Test-Path -LiteralPath $sys) { 'OK (MSR opcional)' } else { 'Opcional — desempenho CPU reduzido sem MSR' })

    $tpl = Join-Path $root 'config.template.json'
    Add-Check 'config.template.json' (Test-Path -LiteralPath $tpl) $(if (Test-Path -LiteralPath $tpl) { 'OK' } else { 'FALTA' })

    $hasSettings = (Test-Path (Join-Path $root 'settings.ini')) -or (Test-Path (Join-Path $root 'settings.json'))
    Add-Check 'settings.ini ou settings.json' $hasSettings $(if ($hasSettings) { 'OK' } else { 'FALTA — copie settings.example.ini' })

    try {
        $s = Get-SoftminSettings -SourceRoot $root
        $waOk = -not [string]::IsNullOrWhiteSpace($s.wallet_address) -and $s.wallet_address -notmatch 'SEU_ENDERECO'
        Add-Check 'wallet_address' $waOk $(if ($waOk) { ('definida ({0} chars)' -f $s.wallet_address.Length) } else { 'FALTA — edite settings ou softmin-wallet.ini' })
        Add-Check 'pool_url' (-not [string]::IsNullOrWhiteSpace($s.pool_url)) $s.pool_url
        Add-Check 'pool_port' ($s.pool_port -gt 0) $s.pool_port
        Add-Check 'install_path' (-not [string]::IsNullOrWhiteSpace($s.install_path)) $s.install_path
    } catch {
        Add-Check 'settings validos' $false $_.Exception.Message
    }

    $scriptOk = (Test-Path (Join-Path $root 'scripts\Install-Softmin-Unified.ps1'))
    Add-Check 'scripts\Install-Softmin-Unified.ps1' $scriptOk $(if ($scriptOk) { 'OK' } else { 'FALTA' })

    return $checks
}

