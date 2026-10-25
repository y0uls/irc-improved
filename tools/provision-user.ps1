<#
  Pre-renseigne le reseau IRC dans un compte The Lounge qui vient d'etre
  cree : lance scripts\provision-network.js dans le conteneur webclient.
  Appele par scripts\add-user.bat.

  Pourquoi en PowerShell : add-user.bat lisait le nom du reseau, le mot de
  passe de connexion et le salon par un for /f, sous enabledelayedexpansion.
  Le ! d'une valeur y etait mange au moment du set, et le ^ avec lui :
  Conn!ect^9x devenait Connect9x. Le compte enregistrait donc un mot de
  passe serveur faux et InspIRCd refusait la connexion, sans aucun message,
  alors que configure.ps1 accepte ces caracteres.

  Ici, les valeurs vont du .env au conteneur sans traverser ni une variable
  batch, ni une ligne de commande : elles sont placees dans l'environnement
  de ce processus, et docker compose les reprend par "-e NOM", sans
  valeur. Un nom de reseau contenant une espace ou un guillemet ne peut
  donc plus couper l'argument en deux (docker prenait alors le second mot
  pour le nom du service : "no such service").

  Usage :
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\provision-user.ps1 -User alice
#>
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$User)

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$cfg = @{}
$envFile = Join-Path $root '.env'
if (Test-Path -LiteralPath $envFile) {
  foreach ($line in [IO.File]::ReadAllLines($envFile, [Text.Encoding]::UTF8)) {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$') { $cfg[$Matches[1]] = $Matches[2] }
  }
}
function Cfg([string]$k, [string]$d) { if ($cfg.ContainsKey($k) -and $cfg[$k]) { return $cfg[$k] } return $d }

# Une valeur vide supprime la variable : docker compose ne la transmet alors
# pas, et provision-network.js retombe sur "" (serveur sans mot de passe).
$env:TL_USER     = $User
$env:TL_NETWORK  = Cfg 'IRC_NETWORK_NAME' 'IRC'
$env:TL_PASSWORD = Cfg 'CONNECT_PASSWORD' ''
$env:TL_CHANNEL  = Cfg 'DEFAULT_CHANNEL'  '#general'

# Le script est donne a node par l'entree standard : l'image The Lounge n'a
# pas de /tmp, et rien n'est ecrit dans le conteneur. PowerShell 5.1 encode
# ce qu'il envoie a un programme externe avec $OutputEncoding, ASCII par
# defaut : on force l'UTF-8 sans BOM, que node lit tel quel.
$js = [IO.File]::ReadAllText((Join-Path $root 'scripts\provision-network.js'), [Text.Encoding]::UTF8)
$OutputEncoding = New-Object Text.UTF8Encoding $false
$js | & docker compose exec -T -e TL_USER -e TL_NETWORK -e TL_PASSWORD -e TL_CHANNEL webclient node
exit $LASTEXITCODE
