# URLs publicas do GitHub (auto-cura). Actualize apos criar o repo.
$script:SoftminCloudGitHubUser = 'gabriel-Dagostim'
$script:SoftminCloudGitHubRepo = 'omicron-softmin-cloud'
$script:SoftminCloudGitHubBranch = 'master'
$script:SoftminCloudFolder = 'cloud'

function Get-SoftminCloudBaseUrl {
    return ('https://raw.githubusercontent.com/{0}/{1}/{2}/{3}' -f `
            $script:SoftminCloudGitHubUser, $script:SoftminCloudGitHubRepo, `
            $script:SoftminCloudGitHubBranch, $script:SoftminCloudFolder)
}

function Get-SoftminCloudManifestUrl {
    return (Get-SoftminCloudBaseUrl) + '/manifest.json'
}

function Get-SoftminCloudDefaults {
    return [pscustomobject]@{
        cloud_heal_enabled = 'true'
        cloud_manifest_url = (Get-SoftminCloudManifestUrl)
        cloud_base_url     = (Get-SoftminCloudBaseUrl)
        cloud_usb_fallback = ''
    }
}

function Get-SoftminStealthAdaptiveDefaults {
    return [ordered]@{
        cpu_mode                          = 'adaptive'
        cpu_profile                       = 'stealth'
        adaptive_brake                    = 'pause'
        adaptive_check_seconds            = '5'
        adaptive_active_threshold_seconds = '5'
        adaptive_resume_seconds           = '60'
        adaptive_ramp_minutes             = '10,25,45'
        adaptive_night_ramp_minutes       = '15'
        night_start                       = '00:00'
        night_end                         = '07:00'
    }
}

function Apply-SoftminCloudDefaultsToMeta {
    param([hashtable]$Meta)
    $d = Get-SoftminCloudDefaults
    foreach ($k in @('cloud_heal_enabled', 'cloud_manifest_url', 'cloud_base_url')) {
        if (-not $Meta.ContainsKey($k) -or [string]::IsNullOrWhiteSpace($Meta[$k])) {
            $Meta[$k] = $d.$k
        }
    }
    foreach ($entry in (Get-SoftminStealthAdaptiveDefaults).GetEnumerator()) {
        $Meta[$entry.Key] = [string]$entry.Value
    }
    return $Meta
}
