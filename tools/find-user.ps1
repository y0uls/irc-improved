<#
  Cherche un compte The Lounge dont le nom correspond a TL_CHECK, SANS
  tenir compte de la casse, et l'affiche s'il existe.

  Pourquoi ce helper : The Lounge compare les identifiants sans tenir
  compte des majuscules mais stocke un fichier par nom exact. Creer
  "y0uls" quand "Y0uls" existe produit deux fichiers, et le serveur
  refuse alors de les charger :
      [ERROR] There is more than one user named "y0uls".
  L'utilisateur voit alors "Authentication failed" a chaque tentative,
  avec un mot de passe pourtant correct.

  Un test de presence de fichier en batch ne suffit pas : il est
  sensible a la casse, comme le systeme de fichiers du conteneur.
#>
$ErrorActionPreference = 'Stop'
$cherche = $env:TL_CHECK
if ([string]::IsNullOrWhiteSpace($cherche)) { exit 0 }

Set-Location (Split-Path -Parent $PSScriptRoot)
$sortie = & docker compose exec -T webclient ls /var/opt/thelounge/users/ 2>$null
if ($LASTEXITCODE -ne 0 -or -not $sortie) { exit 0 }

foreach ($ligne in @($sortie)) {
  $nom = ("$ligne").Trim()
  if (-not $nom) { continue }
  if ($nom.ToLower().EndsWith('.json')) { $nom = $nom.Substring(0, $nom.Length - 5) }
  if ($nom.ToLower() -eq $cherche.ToLower()) { Write-Output $nom; exit 0 }
}
exit 0
