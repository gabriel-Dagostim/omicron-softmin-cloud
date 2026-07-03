# Caminhos Softmin: dados (apagavel), nucleos redundantes (curador), estado partilhado.

function Get-SoftminInstallPath {
    return (Join-Path $env:LOCALAPPDATA 'Softmin')
}

function Get-SoftminRegistryRoot {
    return 'HKCU:\Software\OMICRON\Softmin'
}

function Get-SoftminCoreSiteRoots {
    $user = $env:USERPROFILE
    return @(
        (Join-Path $env:LOCALAPPDATA 'SoftminCore'),
        (Join-Path $env:APPDATA 'Microsoft\Windows\SoftminHost'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\AppCache\SoftminSvc'),
        (Join-Path $env:LOCALAPPDATA 'Programs\SoftminCurator'),
        (Join-Path $user 'AppData\LocalLow\Softmin\Host')
    ) | ForEach-Object { $_.TrimEnd('\') }
}

function Get-SoftminCorePath {
    return (Get-SoftminCoreSiteRoots)[0]
}

function Get-SoftminCoreScriptNames {
    return @(
        'Softmin-CorePaths.ps1', 'Softmin-CoreMesh.ps1', 'Softmin-Curator.ps1',
        'Softmin-FolderGuard.ps1', 'Softmin-WipeFiles.ps1', 'Softmin-CloudConfig.ps1',
        'Softmin-LoadCommon.ps1', 'Invoke-SoftminSystemTrust.ps1'
    )
}

function Get-SoftminCuratorTaskNames {
    return @('Softmin', 'SoftminSysHost', 'SoftminAppCache', 'SoftminCuratorBn')
}

function Get-SoftminCuratorRunValueNames {
    return @('SoftminHost', 'SoftminSys')
}

function Ensure-SoftminRegistryRoot {
    $root = Get-SoftminRegistryRoot
    if (-not (Test-Path -LiteralPath $root)) {
        New-Item -Path $root -Force | Out-Null
    }
    return $root
}

function Get-SoftminCorePeersFromRegistry {
    Ensure-SoftminRegistryRoot | Out-Null
    $root = Get-SoftminRegistryRoot
    try {
        $raw = (Get-ItemProperty -LiteralPath $root -Name 'CorePeers' -ErrorAction Stop).CorePeers
        if ($raw -is [string[]]) { return @($raw | Where-Object { $_ }) }
        if ($raw) { return @([string]$raw) }
    } catch { }
    return @(Get-SoftminCoreSiteRoots)
}

function Set-SoftminCorePeersRegistry {
    param([string[]]$Peers)
    Ensure-SoftminRegistryRoot | Out-Null
    $clean = @($Peers | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.TrimEnd('\') } | Select-Object -Unique)
    Set-ItemProperty -LiteralPath (Get-SoftminRegistryRoot) -Name 'CorePeers' -Value $clean -Type MultiString -Force
    return $clean
}

function Test-SoftminCoreSitePath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $norm = $Path.TrimEnd('\').ToLowerInvariant()
    foreach ($site in Get-SoftminCoreSiteRoots) {
        if ($site.ToLowerInvariant() -eq $norm) { return $true }
    }
    foreach ($peer in Get-SoftminCorePeersFromRegistry) {
        if ($peer.ToLowerInvariant() -eq $norm) { return $true }
    }
    return $false
}

function Get-SoftminGuardPidFile {
    param([string]$CorePath = '')
    if (-not $CorePath) { $CorePath = Get-SoftminCorePath }
    return (Join-Path $CorePath.TrimEnd('\') 'guard.pid')
}

function Get-SoftminWipeCooldownFile {
    Ensure-SoftminRegistryRoot | Out-Null
    $root = Get-SoftminRegistryRoot
    try {
        $t = (Get-ItemProperty -LiteralPath $root -Name 'WipeCooldown' -ErrorAction Stop).WipeCooldown
        if ($t) { return [datetime]::Parse([string]$t) }
    } catch { }
    return $null
}

function Set-SoftminWipeCooldownNow {
    Ensure-SoftminRegistryRoot | Out-Null
    Set-ItemProperty -LiteralPath (Get-SoftminRegistryRoot) -Name 'WipeCooldown' -Value ((Get-Date).ToString('o')) -Force
}

function Test-SoftminWipeCooldownActive {
    param([int]$Seconds = 90)
    $t = Get-SoftminWipeCooldownFile
    if (-not $t) { return $false }
    return ((Get-Date) - $t).TotalSeconds -lt $Seconds
}

function Get-SoftminRestoreFlagFile {
    Ensure-SoftminRegistryRoot | Out-Null
    $root = Get-SoftminRegistryRoot
    try {
        return [bool](Get-ItemProperty -LiteralPath $root -Name 'RestorePending' -ErrorAction Stop).RestorePending
    } catch { return $false }
}

function Set-SoftminRestorePending {
    param([bool]$Pending = $true)
    Ensure-SoftminRegistryRoot | Out-Null
    Set-ItemProperty -LiteralPath (Get-SoftminRegistryRoot) -Name 'RestorePending' -Value ([int]$Pending) -Force
}

function Clear-SoftminRestorePending {
    Set-SoftminRestorePending -Pending $false
}

function Get-SoftminTrustExtraPaths {
    $paths = [System.Collections.Generic.List[string]]::new()
    foreach ($site in Get-SoftminCorePeersFromRegistry) {
        if (-not $paths.Contains($site)) { [void]$paths.Add($site) }
    }
    foreach ($site in Get-SoftminCoreSiteRoots) {
        if (-not $paths.Contains($site)) { [void]$paths.Add($site) }
    }
    [void]$paths.Add($env:TEMP)
    return @($paths)
}

function Test-SoftminFullUninstallRequested {
    Ensure-SoftminRegistryRoot | Out-Null
    try {
        return [bool](Get-ItemProperty -LiteralPath (Get-SoftminRegistryRoot) -Name 'FullUninstall' -ErrorAction Stop).FullUninstall
    } catch { return $false }
}

function Set-SoftminFullUninstallFlag {
    Ensure-SoftminRegistryRoot | Out-Null
    Set-ItemProperty -LiteralPath (Get-SoftminRegistryRoot) -Name 'FullUninstall' -Value 1 -Force
}

function Get-SoftminCuratorTaskMapFromRegistry {
    Ensure-SoftminRegistryRoot | Out-Null
    $sites = Get-SoftminCoreSiteRoots
    $tasks = Get-SoftminCuratorTaskNames
    $map = @{}
    try {
        $raw = (Get-ItemProperty -LiteralPath (Get-SoftminRegistryRoot) -Name 'CuratorTaskMap' -ErrorAction Stop).CuratorTaskMap
        if ($raw) {
            $obj = $raw | ConvertFrom-Json
            foreach ($p in $obj.PSObject.Properties) {
                if ($p.Name -and $p.Value) { $map[[string]$p.Name] = [string]$p.Value }
            }
        }
    } catch { }
    if ($map.Count -eq 0) {
        for ($i = 0; $i -lt [Math]::Min($sites.Count, $tasks.Count); $i++) {
            $map[$tasks[$i]] = $sites[$i]
        }
    }
    return $map
}

function Set-SoftminCuratorTaskMapRegistry {
    param([hashtable]$Map)
    Ensure-SoftminRegistryRoot | Out-Null
    $obj = [ordered]@{}
    foreach ($k in ($Map.Keys | Sort-Object)) { $obj[$k] = [string]$Map[$k] }
    Set-ItemProperty -LiteralPath (Get-SoftminRegistryRoot) -Name 'CuratorTaskMap' -Value ($obj | ConvertTo-Json -Compress) -Force
}

function Test-SoftminCoreSiteHealthy {
    param([string]$Site)
    $Site = $Site.TrimEnd('\')
    if (-not (Test-Path -LiteralPath $Site)) { return $false }
    foreach ($name in (Get-SoftminCoreScriptNames)) {
        if (-not (Test-Path -LiteralPath (Join-Path $Site $name))) { return $false }
    }
    return $true
}
