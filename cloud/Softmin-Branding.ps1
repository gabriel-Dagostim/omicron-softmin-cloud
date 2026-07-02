# Identidade visual Softmin: banner em texto + imagem opcional no instalador.

. "$PSScriptRoot\Softmin-BrandingConfig.ps1"

function Get-InstallerBannerImagePath {
    param([string]$SourceRoot)
    if (-not $SourceRoot) { return $null }
    $root = $SourceRoot.TrimEnd('\')

    $exact = @(
        (Join-Path $root 'assets\installer-banner.png'),
        (Join-Path $root 'Minha-Logo.png'),
        (Join-Path $root 'Minha.Logo.png'),
        (Join-Path $root 'minha-logo.png'),
        (Join-Path $root 'minha.logo.png'),
        (Join-Path $root 'Minha-Logo.jpg'),
        (Join-Path $root 'Minha.Logo.jpg'),
        (Join-Path $root 'minha-logo.jpg'),
        (Join-Path $root 'minha.logo.jpg')
    )
    foreach ($c in $exact) {
        if (Test-Path -LiteralPath $c) {
            return (Resolve-Path -LiteralPath $c).Path
        }
    }

    $wildPng = Get-ChildItem -Path $root -Filter 'Minha*.png' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($wildPng) { return $wildPng.FullName }

    $wildJpg = Get-ChildItem -Path $root -Filter 'Minha*.jpg' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($wildJpg) { return $wildJpg.FullName }

    return $null
}

function Write-SoftminBanner {
    param(
        [string]$Subtitle = ''
    )
    $b = Get-SoftminBranding
    Write-Host ''
    Write-Host ('     {0}' -f $b.CompanyName) -ForegroundColor Magenta
    Write-Host ('     {0}' -f $b.ProductName) -ForegroundColor Cyan
    Write-Host ('     {0}' -f $b.Author) -ForegroundColor DarkGray
    if ($Subtitle) {
        Write-Host "         $Subtitle" -ForegroundColor DarkGray
    }
    Write-Host ''
}

function Show-InstallerBannerIfPresent {
    param([string]$SourceRoot)
    $path = Get-InstallerBannerImagePath -SourceRoot $SourceRoot
    if (-not $path) { return }
    $b = Get-SoftminBranding
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop | Out-Null
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop | Out-Null
        $img = [System.Drawing.Image]::FromFile($path)
        $w = [Math]::Min(640, [Math]::Max(360, $img.Width + 24))
        $h = [Math]::Min(480, [Math]::Max(160, $img.Height + 48))
        $f = New-Object System.Windows.Forms.Form
        $f.Text = ('{0} — {1}' -f $b.ProductName, $b.CompanyName)
        $f.BackColor = [System.Drawing.Color]::White
        $f.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
        $f.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $f.MaximizeBox = $false
        $f.MinimizeBox = $false
        $f.TopMost = $true
        $f.ClientSize = New-Object System.Drawing.Size -ArgumentList @($w, $h)
        $pb = New-Object System.Windows.Forms.PictureBox
        $pb.Dock = [System.Windows.Forms.DockStyle]::Fill
        $pb.BackColor = [System.Drawing.Color]::White
        $pb.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
        $pb.Image = $img
        $f.Controls.Add($pb)
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Dock = [System.Windows.Forms.DockStyle]::Bottom
        $lbl.Height = 28
        $lbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $lbl.Text = $b.Author
        $lbl.ForeColor = [System.Drawing.Color]::DimGray
        $f.Controls.Add($lbl)
        $t = New-Object System.Windows.Forms.Timer
        $t.Interval = 2800
        $formRef = $f
        $timerRef = $t
        $t.add_Tick({
                $timerRef.Stop()
                $formRef.Close()
            })
        $f.add_Shown({ $timerRef.Start() })
        [void]$f.ShowDialog()
        $img.Dispose()
        $f.Dispose()
        $t.Dispose()
    } catch {
        Write-Warning ('Banner de imagem ignorado: {0}' -f $_.Exception.Message)
    }
}

function Show-InstallerBannerPngIfPresent {
    param([string]$SourceRoot)
    Show-InstallerBannerIfPresent -SourceRoot $SourceRoot
}

function Copy-SoftminLogoToInstall {
    param(
        [string]$SourceRoot,
        [string]$InstallPath
    )
    $src = Get-InstallerBannerImagePath -SourceRoot $SourceRoot
    if (-not $src) { return }
    $destDir = Join-Path $InstallPath 'assets'
    if (-not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    $ext = [System.IO.Path]::GetExtension($src)
    Copy-Item -LiteralPath $src -Destination (Join-Path $destDir ('branding{0}' -f $ext)) -Force
    $b = Get-SoftminBranding
    $meta = [pscustomobject]@{
        company = $b.CompanyName
        author  = $b.Author
        product = $b.ProductName
    }
    $metaPath = Join-Path $destDir 'branding.json'
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($metaPath, ($meta | ConvertTo-Json -Compress), $utf8)
}
