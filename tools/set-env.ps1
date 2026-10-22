<#
  Ecrit une valeur dans le fichier .env, sans jamais interpreter la valeur.

  Pourquoi ce script existe : setup.bat et build-client.bat utilisaient
    powershell -Command "(Get-Content '.env') -replace 'CLE=.*', 'CLE=!VALEUR!' | Set-Content '.env'"
  ce qui casse en silence des que la valeur contient :
    '   -> ParserError PowerShell, le .env n'est PAS modifie (et le .bat
          affichait quand meme [OK])
    $   -> interprete comme reference de capture regex ($$ -> $, $& -> toute
          la correspondance) : Pa$$w0rd etait enregistre en Pa$w0rd
    accent -> Set-Content ecrit en ANSI, docker compose relit la valeur en
          !!binary et le serveur refuse de demarrer

  Ici la valeur arrive par une variable d'environnement (-ValueFrom) et
  n'est jamais interpolee dans du code. Le fichier est reecrit en UTF-8
  sans BOM, fins de ligne CRLF.

  Usage :
    set "VAL=mon mot de passe & co"
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\set-env.ps1 -Key CONNECT_PASSWORD -ValueFrom VAL
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Key,
  [string]$ValueFrom,
  [string]$Value,
  [string]$EnvFile
)

$ErrorActionPreference = 'Stop'

if (-not $EnvFile) { $EnvFile = Join-Path (Split-Path -Parent $PSScriptRoot) '.env' }

if ($ValueFrom) {
  $v = [Environment]::GetEnvironmentVariable($ValueFrom)
  if ($null -eq $v) { $v = '' }
} else {
  $v = $Value
  if ($null -eq $v) { $v = '' }
}

if ($Key -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
  Write-Error "Nom de variable invalide : $Key"
  exit 1
}
if ($v -match "[`r`n]") {
  Write-Error "La valeur de $Key contient un retour a la ligne."
  exit 1
}

if (-not (Test-Path -LiteralPath $EnvFile)) {
  Write-Error "Fichier introuvable : $EnvFile"
  exit 1
}

$lines = @([IO.File]::ReadAllLines($EnvFile, [Text.Encoding]::UTF8))
$found = $false
$out = New-Object System.Collections.Generic.List[string]
foreach ($line in $lines) {
  if ($line -match ('^\s*' + [regex]::Escape($Key) + '\s*=')) {
    if (-not $found) { $out.Add("$Key=$v") ; $found = $true }
    # les doublons eventuels de la cle sont supprimes
  } else {
    $out.Add($line)
  }
}
if (-not $found) { $out.Add("$Key=$v") }

$utf8NoBom = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($EnvFile, (($out -join "`r`n") + "`r`n"), $utf8NoBom)
exit 0
