<#
  Configuration interactive du fichier .env.

  Toute la saisie se fait ici, et non dans setup.bat, pour deux raisons :
   - un .bat passe les valeurs par la ligne de commande et par la code page
     de la console : une apostrophe, un $, un ! ou un accent cassait la
     valeur en silence (le script affichait quand meme [OK]) ;
   - PowerShell peut relire et reecrire le .env sans jamais interpreter la
     valeur saisie.

  Usage :
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\configure.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\configure.ps1 -Force
      -Force : repose TOUTES les questions (reconfiguration), au lieu de ne
      demander que ce qui n'a jamais ete renseigne.
#>
[CmdletBinding()]
param([switch]$Force)

$ErrorActionPreference = 'Stop'
try {
  [Console]::InputEncoding  = New-Object Text.UTF8Encoding $false
  [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false
} catch { }

$root    = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $root '.env'
$example = Join-Path $root '.env.example'

# --- lecture / ecriture du .env --------------------------------------------
function Read-EnvMap {
  $map = @{}
  if (Test-Path -LiteralPath $envFile) {
    foreach ($line in [IO.File]::ReadAllLines($envFile, [Text.Encoding]::UTF8)) {
      if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$') { $map[$Matches[1]] = $Matches[2] }
    }
  }
  return $map
}

function Set-EnvValue([string]$Key, [string]$Value) {
  if ($null -eq $Value) { $Value = '' }
  if ($Value -match "[`r`n]") { throw "La valeur de $Key contient un retour a la ligne." }
  $lines = @()
  if (Test-Path -LiteralPath $envFile) { $lines = @([IO.File]::ReadAllLines($envFile, [Text.Encoding]::UTF8)) }
  $out = New-Object System.Collections.Generic.List[string]
  $found = $false
  foreach ($line in $lines) {
    if ($line -match ('^\s*' + [regex]::Escape($Key) + '\s*=')) {
      if (-not $found) { $out.Add("$Key=$Value"); $found = $true }
    } else { $out.Add($line) }
  }
  if (-not $found) { $out.Add("$Key=$Value") }
  [IO.File]::WriteAllText($envFile, (($out -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding $false))
}

function Remove-EnvValue([string]$Key) {
  if (-not (Test-Path -LiteralPath $envFile)) { return }
  $lines = @([IO.File]::ReadAllLines($envFile, [Text.Encoding]::UTF8))
  $out = $lines | Where-Object { $_ -notmatch ('^\s*' + [regex]::Escape($Key) + '\s*=') }
  [IO.File]::WriteAllText($envFile, ((@($out) -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding $false))
}

function New-Password([int]$Length = 20) {
  # Alphabet volontairement alphanumerique : la valeur traverse un .env, une
  # config XML InspIRCd et un fichier de config HexChat.
  $alphabet = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
  $bytes = New-Object byte[] $Length
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  -join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] })
}

function Ask([string]$Question, [string]$Default) {
  if ($Default) { $prompt = "$Question [$Default]" } else { $prompt = $Question }
  $answer = Read-Host $prompt
  if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
  return $answer.Trim()
}

# --- .env ------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $envFile)) {
  if (-not (Test-Path -LiteralPath $example)) { throw ".env.example introuvable dans $root" }
  Copy-Item -LiteralPath $example -Destination $envFile
  Write-Host '[OK] Fichier .env cree depuis .env.example.'
}

$cfg = Read-EnvMap

# Valeurs sentinelles du modele : tant qu'elles sont la, la question n'a
# jamais recu de reponse.
#
# -AllowEmpty : pour une cle ou le vide est une reponse valable, et non une
# absence de reponse. Sans ca, choisir "aucun mot de passe de connexion"
# (reponse "-") faisait reposer la question a chaque lancement de setup.bat,
# y compris quand l'administrateur repondait N a "Revoir la configuration".
function Needs([string]$Key, [string[]]$Sentinels, [switch]$AllowEmpty) {
  if ($Force) { return $true }
  if (-not $cfg.ContainsKey($Key)) { return $true }
  $v = $cfg[$Key]
  if ([string]::IsNullOrWhiteSpace($v)) { return (-not $AllowEmpty) }
  return ($Sentinels -contains $v)
}

Write-Host ''
Write-Host '=== Configuration du serveur IRC ==='
Write-Host ''

# Valeurs interdites : une valeur entierement numerique est transmise a
# The Lounge par « -c cle=valeur », qui la convertit en NOMBRE. La fusion de
# configuration refuse alors le type (« Incorrect type for "password" ») et
# garde la valeur par defaut, en silence cote utilisateur : le formulaire de
# connexion part avec un mot de passe vide et la connexion echoue.
# Verifie sur The Lounge 4.5.2.
function Test-AllDigits([string]$Value) {
  return ($Value -and $Value -match '^[0-9]+$')
}

# Caracteres a refuser dans un mot de passe. Chacun casse la valeur en
# silence quelque part sur son trajet :
#   $  docker compose developpe $NOM dans les valeurs du .env. Le serveur
#      recoit la chaine tronquee, alors que tools\get-env.ps1 (donc
#      l'invitation et le compte pre-rempli) renvoie le texte brut : les
#      deux ne correspondent plus et la connexion est refusee.
#   "  et &  partent dans la configuration XML d'InspIRCd.
function Test-BadChars([string]$Value) {
  return ($Value -and $Value -match '[\$"&]')
}

# 1. Nom du reseau
if (Needs 'IRC_NETWORK_NAME' @('MonReseau', 'CHANGEME')) {
  do {
    $v = Ask 'Nom du reseau IRC' 'MonReseau'
    if (Test-AllDigits $v) {
      Write-Host '[ERREUR] Un nom entierement numerique est ignore par l''interface web.'
      Write-Host '         Ajoutez au moins une lettre.'
    }
  } while (Test-AllDigits $v)
  Set-EnvValue 'IRC_NETWORK_NAME' $v
  Write-Host "[OK] Reseau : $v"
}

# 2. Mot de passe de connexion au serveur
if (Needs 'CONNECT_PASSWORD' @('CHANGEME') -AllowEmpty) {
  Write-Host ''
  Write-Host 'Mot de passe demande pour se connecter au serveur.'
  Write-Host 'Entree = en generer un ; "-" = aucun mot de passe (serveur ouvert).'
  do {
    $v = Read-Host 'Mot de passe de connexion'
    if ([string]::IsNullOrWhiteSpace($v)) { $v = New-Password 16; Write-Host "[OK] Genere : $v" }
    elseif ($v.Trim() -eq '-') { $v = ''; Write-Host '[INFO] Aucun mot de passe de connexion.' }
    elseif (Test-AllDigits $v.Trim()) {
      $v = $v.Trim()
      Write-Host '[ERREUR] Un mot de passe entierement numerique est ignore par'
      Write-Host '         l''interface web : la connexion echouerait sans message.'
      Write-Host '         Ajoutez au moins une lettre.'
    }
    elseif (Test-BadChars $v.Trim()) {
      $v = $v.Trim()
      Write-Host '[ERREUR] Les caracteres $ " et & cassent la valeur en silence'
      Write-Host '         (developpement de variable, configuration XML).'
      Write-Host '         Choisissez un autre mot de passe.'
    }
    else { $v = $v.Trim(); Write-Host '[OK] Mot de passe de connexion enregistre.' }
  } while ((Test-AllDigits $v) -or (Test-BadChars $v))
  Set-EnvValue 'CONNECT_PASSWORD' $v
}

# 3. Mot de passe oper (/OPER admin ...)
#    L'ancienne version demandait un mot de passe puis lancait
#    « inspircd --mkpasswd hmac-sha256 » pour le hasher : cette option
#    n'existe plus depuis InspIRCd 4, la commande echouait, et le .bat
#    ecrivait la chaine litterale « *Password: = » dans le .env sans rien
#    detecter. /OPER etait donc impossible, sans aucun message d'erreur.
if (Needs 'OPER_PASSWORD' @('CHANGEME')) {
  Write-Host ''
  Write-Host 'Mot de passe administrateur du serveur (commande /OPER admin <mdp>).'
  Write-Host 'Entree = en generer un.'
  do {
    $v = Read-Host 'Mot de passe oper'
    if ([string]::IsNullOrWhiteSpace($v)) { $v = New-Password 20; Write-Host "[OK] Genere : $v" }
    elseif (Test-BadChars $v.Trim()) {
      $v = $v.Trim()
      Write-Host '[ERREUR] Les caracteres $ " et & cassent la valeur en silence'
      Write-Host '         (developpement de variable, configuration XML).'
      Write-Host '         Choisissez un autre mot de passe.'
    }
    else { $v = $v.Trim(); Write-Host '[OK] Mot de passe oper enregistre.' }
  } while (Test-BadChars $v)
  Set-EnvValue 'OPER_PASSWORD' $v
  Set-EnvValue 'OPER_HASH' 'plaintext'
}
# Cle morte de l'ancienne version : sa presence empechait opers.sh de lire
# OPER_PASSWORD (il ne le reprend que si le hash est vide).
Remove-EnvValue 'OPER_PASSWORD_HASH'

# 4. Channel par defaut
if (Needs 'DEFAULT_CHANNEL' @('DEFAULTCHANNEL', 'CHANGEME')) {
  $v = Ask 'Channel par defaut' '#general'
  if ($v -notmatch '^[#&]') { $v = "#$v" }
  Set-EnvValue 'DEFAULT_CHANNEL' $v
  $t = Ask "Topic du channel $v" 'Bienvenue !'
  Set-EnvValue 'DEFAULT_TOPIC' $t
  Write-Host "[OK] Channel $v configure."
}

# 5. Interface web (The Lounge).
#    Elle n'est plus optionnelle : l'adresse .onion la publie en meme temps
#    que le serveur IRC (HiddenServicePort 80), et c'est devenu le chemin
#    d'acces principal — Tor Browser et une URL, rien a installer.
#    Le profil "web" est donc retire du .env s'il y traine encore : sans ca,
#    COMPOSE_PROFILES=web ferait aussi demarrer... rien de plus, mais la
#    valeur serait trompeuse.
if ($cfg.ContainsKey('COMPOSE_PROFILES') -and $cfg['COMPOSE_PROFILES'] -match 'web') {
  $cleaned = (($cfg['COMPOSE_PROFILES'] -split ',' | Where-Object { $_.Trim() -and $_.Trim() -ne 'web' }) -join ',')
  Set-EnvValue 'COMPOSE_PROFILES' $cleaned
  Write-Host '[INFO] L''interface web n''est plus un profil : elle demarre toujours.'
}
if (-not $cfg.ContainsKey('COMPOSE_PROFILES')) { Set-EnvValue 'COMPOSE_PROFILES' '' }
if (-not $cfg.ContainsKey('WEBCLIENT_PORT')) { Set-EnvValue 'WEBCLIENT_PORT' '8080' }

# Le port local de l'interface web est publie sans condition maintenant que
# webclient n'est plus optionnel. S'il est deja pris par un autre logiciel,
# le conteneur ne demarre pas du tout - et c'est l'interface web, donc
# l'adresse .onion web, qui disparait. On previent avant le demarrage
# plutot que de laisser l'administrateur devant un "port is already
# allocated" de docker. Le port est souvent occupe par notre PROPRE
# conteneur, auquel cas il n'y a rien a signaler.
$wcPort = 8080
$after0 = Read-EnvMap
if ($after0.ContainsKey('WEBCLIENT_PORT') -and $after0['WEBCLIENT_PORT'] -match '^\d+$') {
  $wcPort = [int]$after0['WEBCLIENT_PORT']
}
$portBusy = $false
try {
  $l = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback), $wcPort
  $l.Start(); $l.Stop()
} catch { $portBusy = $true }
if ($portBusy) {
  $ours = $false
  try {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $id = (& docker compose ps -q webclient 2>&1)
    $ErrorActionPreference = $old
    if ($LASTEXITCODE -eq 0 -and $id) { $ours = $true }
  } catch { }
  if (-not $ours) {
    Write-Host ''
    Write-Host "[ATTENTION] Le port $wcPort est deja utilise sur cette machine."
    Write-Host '            L''interface web ne pourra pas demarrer, et c''est elle'
    Write-Host '            que publie l''adresse .onion. Changez WEBCLIENT_PORT'
    Write-Host '            dans le .env (par exemple 8090) avant de continuer.'
  }
}

# 6. Controle final : un .env ecrit a la main (ou par une ancienne version)
#    peut contenir une valeur entierement numerique, que l'interface web
#    ignorerait sans rien dire a l'utilisateur. On le signale plutot que de
#    modifier le mot de passe de quelqu'un dans son dos.
$after = Read-EnvMap
foreach ($k in @('CONNECT_PASSWORD', 'IRC_NETWORK_NAME')) {
  if ($after.ContainsKey($k) -and (Test-AllDigits $after[$k])) {
    Write-Host ''
    Write-Host "[ATTENTION] $k ne contient que des chiffres."
    Write-Host '            L''interface web ignorera cette valeur (elle la lit'
    Write-Host '            comme un nombre) et la connexion echouera sans message.'
    Write-Host '            Relancez setup.bat et repondez O pour la corriger.'
  }
}

Write-Host ''
Write-Host '[OK] Configuration enregistree dans .env'
exit 0
