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

function Apply-SoftminCloudDefaultsToMeta {
    param([hashtable]$Meta)
    $d = Get-SoftminCloudDefaults
    foreach ($k in @('cloud_heal_enabled', 'cloud_manifest_url', 'cloud_base_url')) {
        if (-not $Meta.ContainsKey($k) -or [string]::IsNullOrWhiteSpace($Meta[$k])) {
            $Meta[$k] = $d.$k
        }
    }
    return $Meta
}
