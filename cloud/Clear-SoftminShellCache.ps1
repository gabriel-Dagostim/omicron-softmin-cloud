# Limpa cache do Windows (MuiCache) que pode manter nome/icone antigos "XMRig miner".
param(
    [string]$ExePath = ''
)

if ($MyInvocation.InvocationName -eq '.') { return }

$ErrorActionPreference = 'SilentlyContinue'

if ([string]::IsNullOrWhiteSpace($ExePath)) {
    $ExePath = Join-Path $env:LOCALAPPDATA 'Softmin\bin\softmin.exe'
}
if (-not (Test-Path -LiteralPath $ExePath)) {
    Write-Host 'Cache Shell: softmin.exe nao encontrado (ignorado).' -ForegroundColor DarkGray
    return 0
}
$ExePath = (Resolve-Path -LiteralPath $ExePath).Path
$exeLower = $ExePath.ToLowerInvariant()

function Clear-MuiCacheHive {
    param([string]$HivePath)
    if (-not (Test-Path -LiteralPath $HivePath)) { return 0 }
    $removed = 0
    Get-ItemProperty -LiteralPath $HivePath -ErrorAction SilentlyContinue |
        Get-Member -MemberType NoteProperty |
        Where-Object { $_.Name -notmatch '^PS' } |
        ForEach-Object {
            $name = $_.Name
            if ($name.ToLowerInvariant().Contains('softmin') -or $name.ToLowerInvariant().Contains('xmrig')) {
                Remove-ItemProperty -LiteralPath $HivePath -Name $name -Force -ErrorAction SilentlyContinue
                $removed++
            }
        }
    return $removed
}

$total = 0
$paths = @(
    'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache',
    'HKCU:\Software\Microsoft\Windows\ShellNoRoam\MUICache'
)
foreach ($p in $paths) { $total += Clear-MuiCacheHive -HivePath $p }

# Entradas @path,-id no MuiCache
foreach ($p in $paths) {
    if (-not (Test-Path $p)) { continue }
    $props = Get-ItemProperty $p
    foreach ($prop in $props.PSObject.Properties) {
        if ($prop.Name -match '^@' -and $prop.Name.ToLowerInvariant().Contains('softmin')) {
            Remove-ItemProperty -LiteralPath $p -Name $prop.Name -Force -ErrorAction SilentlyContinue
            $total++
        }
    }
}

try {
    ie4uinit.exe -ClearIconCache | Out-Null
} catch { }

Write-Host "Cache Shell limpo ($total entradas). Reinicie o Gestor de Tarefas se o nome antigo persistir."
return $total
