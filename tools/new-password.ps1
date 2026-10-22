<#
  Genere un mot de passe aleatoire.

  Alphabet volontairement alphanumerique et sans caracteres ambigus : la
  valeur traverse une ligne de commande .bat, un "docker compose exec" et
  un fichier texte remis a l'utilisateur.

  Usage :
    for /f "usebackq delims=" %%P in (`powershell -NoProfile -ExecutionPolicy Bypass -File tools\new-password.ps1 -Length 14`) do set "PWD=%%P"
#>
[CmdletBinding()]
param([int]$Length = 14)

$ErrorActionPreference = 'Stop'
$alphabet = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
$bytes = New-Object byte[] $Length
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
Write-Output (-join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] }))
