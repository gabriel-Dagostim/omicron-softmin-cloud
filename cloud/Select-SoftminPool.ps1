# Testa latencia (ping + tracert) nas pools predefinidas e escolhe a melhor.
param(
    [string]$LogInstallPath = '',
    [switch]$MoneroOnly = $true
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Softmin-Common.ps1"

function Write-PoolLog {
    param([string]$Msg)
    if ($LogInstallPath) {
        Write-SoftminInstallLog -InstallPath $LogInstallPath -Message $Msg
    }
    Write-Host $Msg -ForegroundColor DarkGray
}

function Get-PoolLatencyScore {
    param(
        [string]$PoolHost,
        [int]$Port
    )
    $pingMs = 9999.0
    $hops = 99
    $resolved = $false

    try {
        $ping = Test-Connection -ComputerName $PoolHost -Count 2 -ErrorAction Stop |
            Where-Object { $_.ResponseTime -gt 0 } |
            Measure-Object -Property ResponseTime -Average
        if ($ping.Count -gt 0) {
            $pingMs = [double]$ping.Average
            $resolved = $true
        }
    } catch {
        Write-PoolLog ("  ping {0}: falhou ({1})" -f $PoolHost, $_.Exception.Message)
    }

    try {
        $tracert = & tracert.exe -d -h 20 -w 800 $PoolHost 2>&1 | Out-String
        $hopLines = @($tracert -split "`n" | Where-Object { $_ -match '^\s*\d+\s' })
        if ($hopLines.Count -gt 0) {
            $hops = $hopLines.Count
            if (-not $resolved) { $resolved = $true; $pingMs = 1500 + ($hops * 40) }
        }
    } catch {
        Write-PoolLog ("  tracert {0}: falhou" -f $PoolHost)
    }

    if (-not $resolved) {
        return [pscustomobject]@{ Host = $PoolHost; Port = $Port; PingMs = 99999; Hops = 99; Score = 99999; Ok = $false }
    }

    $score = $pingMs + ($hops * 5)
    return [pscustomobject]@{ Host = $PoolHost; Port = $Port; PingMs = [math]::Round($pingMs, 1); Hops = $hops; Score = [math]::Round($score, 1); Ok = $true }
}

$pools = @(Get-SoftminPoolPresets)
if ($MoneroOnly) {
    $pools = @($pools | Where-Object { $_.Monero })
}

Write-PoolLog '[POOL] A medir latencia (ping + tracert) nas pools candidatas...'
$results = [System.Collections.Generic.List[object]]::new()
foreach ($p in $pools) {
    Write-PoolLog ("  testando {0}:{1} ({2})..." -f $p.Host, $p.Port, $p.Label)
    $m = Get-PoolLatencyScore -PoolHost $p.Host -Port $p.Port
    $row = [pscustomobject]@{
        Label  = $p.Label
        Host   = $p.Host
        Port   = $p.Port
        Tls    = $p.Tls
        PingMs = $m.PingMs
        Hops   = $m.Hops
        Score  = $m.Score
        Ok     = $m.Ok
    }
    [void]$results.Add($row)
    Write-PoolLog ("    -> ping={0}ms hops={1} score={2}" -f $m.PingMs, $m.Hops, $m.Score)
}

$best = @($results | Where-Object { $_.Ok } | Sort-Object Score, PingMs | Select-Object -First 1)
if (-not $best) {
    $best = @($results | Sort-Object Score | Select-Object -First 1)
}

Write-PoolLog ("[POOL] Escolhida: {0}:{1} ({2}) score={3}" -f $best.Host, $best.Port, $best.Label, $best.Score)
return $best
