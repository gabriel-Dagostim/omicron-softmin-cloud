function Get-SoftminAutoVaultCredentials {
    $p = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('T21pY3JvblZhdWx0MjAyNiE='))
    $c = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('R0hPU1Q='))
    return @{ Password = $p; Codigo = $c }
}
