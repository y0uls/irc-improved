<#
  Affiche le recapitulatif de fin de setup.bat : tout ce qu'il faut pour
  faire entrer quelqu'un (adresse web, salon, /OPER, mot de passe serveur,
  invitations).

  Pourquoi en PowerShell : setup.bat lisait ces valeurs par un for /f, sous
  enabledelayedexpansion. Le ! d'une valeur y etait mange au moment du set,
  et le ^ avec lui : Pass!word42 s'affichait Password42 et Conn!ect^9x
  Connect9x. Le recapitulatif donnait donc un /OPER et un mot de passe
  serveur faux, alors que configure.ps1 accepte ces caracteres. Ici, la
  valeur va du .env a l'ecran sans etre interpretee.

  Usage (depuis setup.bat) :
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\show-summary.ps1 -Onion xxx.onion [-FirstUser alice]
#>
[CmdletBinding()]
param(
  [string]$Onion,
  [string]$FirstUser
)

$root = Split-Path -Parent $PSScriptRoot

$cfg = @{}
$envFile = Join-Path $root '.env'
if (Test-Path -LiteralPath $envFile) {
  foreach ($line in [IO.File]::ReadAllLines($envFile, [Text.Encoding]::UTF8)) {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$') { $cfg[$Matches[1]] = $Matches[2] }
  }
}
function Cfg([string]$k, [string]$d) { if ($cfg.ContainsKey($k) -and $cfg[$k]) { return $cfg[$k] } return $d }

$chan   = Cfg 'DEFAULT_CHANNEL'  ''
$oper   = Cfg 'OPER_PASSWORD'    ''
$conn   = Cfg 'CONNECT_PASSWORD' ''
$wcPort = Cfg 'WEBCLIENT_PORT'   '8080'

$sep = '=' * 70
Write-Host ''
Write-Host $sep
Write-Host ' Serveur IRC demarre'
Write-Host $sep
Write-Host ' A donner aux utilisateurs - Tor Browser, niveau de securite Standard :'
Write-Host "     http://$Onion/"
Write-Host ''
Write-Host " Salon        : $chan"
Write-Host " Admin        : /OPER admin $oper"
Write-Host " Adresse IRC  : ${Onion}:6667   (HexChat, WeeChat...)"
if ($conn) {
  Write-Host " Mot de passe serveur : $conn   (clients IRC classiques)"
} else {
  Write-Host ' Mot de passe serveur : aucun'
}
Write-Host " Interface web locale : http://localhost:$wcPort   (administrateur)"
Write-Host ''
if ($FirstUser) {
  # invite.txt ne contient AUCUN identifiant : ceux du compte qui vient
  # d'etre cree sont dans son fichier personnel. Envoyer invite.txt a
  # cette personne la laisserait sans mot de passe.
  Write-Host " Invitation a envoyer a $FirstUser : invite-$FirstUser.txt"
  Write-Host ' Invitation sans identifiants       : invite.txt (+ invite-qr.png)'
} else {
  Write-Host ' Invitation : invite.txt (+ invite-qr.png) - sans identifiants,'
  Write-Host '              scripts\add-user.bat en genere une par personne.'
}
Write-Host ''
Write-Host ' Ajouter quelqu''un : scripts\add-user.bat'
Write-Host ' Package Windows   : client-package\build-client.bat'
Write-Host ''
Write-Host ' Logs      : docker compose logs -f irc'
Write-Host ' Sauvegarde: scripts\backup-onion.bat  (l''adresse .onion est unique'
Write-Host '             et irrecuperable si le volume tor_keys est perdu)'
Write-Host $sep
exit 0
