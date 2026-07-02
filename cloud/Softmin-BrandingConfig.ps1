# Identidade Softmin — fonte única (empresa, autor, produto, caminhos).
# Usado por Softmin-Branding.ps1, Apply-SoftminBranding.ps1 e instaladores.

function Get-SoftminBranding {
    [ordered]@{
        ProductName    = 'Softmin'
        CompanyName    = 'OMICRON'
        SiteUrl        = 'www.softmin.com'
        Author         = 'Pedro Piovezan - GHOST'
        Copyright      = 'Copyright (C) 2026 OMICRON - Pedro Piovezan - GHOST'
        ProductDesc    = 'Softmin | www.softmin.com'
        AppId          = 'softmin'
        AppVersion     = '6.26.0'
        ExeName        = 'softmin.exe'
        ScheduledTask  = 'Softmin'
        InstallFolder  = 'Softmin'
        DefaultWorker  = 'OMICRON'
        UserAgent      = 'Softmin-OMICRON'
    }
}

function Get-SoftminBrandingHeaderLines {
    $b = Get-SoftminBranding
    return @(
        "  $($b.CompanyName)",
        "  $($b.ProductName)",
        "  $($b.Author)"
    )
}
