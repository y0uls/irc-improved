<#
  Lit une valeur du .env et l'affiche telle quelle (une seule ligne, sans
  guillemets ajoutes). Remplace les
    for /f "tokens=2 delims==" %%P in ('findstr ...')
  des scripts .bat, qui tronquent toute valeur contenant un "=".

  Usage : for /f "usebackq delims=" %%V in (`powershell -NoProfile -File tools\get-env.ps1 -Key CONNECT_PASSWORD`) do set "VAL=%%V"
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Key,
  [string]$EnvFile
)
$ErrorActionPreference = 'Stop'
if (-not $EnvFile) { $EnvFile = Join-Path (Split-Path -Parent $PSScriptRoot) '.env' }
if (-not (Test-Path -LiteralPath $EnvFile)) { exit 1 }
foreach ($line in [IO.File]::ReadAllLines($EnvFile, [Text.Encoding]::UTF8)) {
  if ($line -match ('^\s*' + [regex]::Escape($Key) + '\s*=(.*)$')) {
    Write-Output $Matches[1]
    exit 0
  }
}
exit 1
