#Requires -Version 3
<#
.SYNOPSIS
  Genere client-package\IRC-Client.zip, le package client pret a distribuer.

.DESCRIPTION
  Tout est fait en PowerShell, et c'est volontaire. La version precedente
  lisait le .env avec "for /f tokens=2 delims==" et injectait les valeurs dans
  une ligne de commande powershell, ce qui corrompait silencieusement le zip :
    - un mot de passe contenant "=" etait tronque au premier "=" ;
    - un "&" pouvait executer une commande ;
    - un "!" etait avale par la delayed expansion ;
    - une apostrophe cassait le .Replace(...) et le zip partait avec le
      placeholder __CONN_PASS__ tel quel, donc un client sans mot de passe.
  Ici les valeurs ne traversent jamais une ligne de commande et ne servent
  jamais de chaine de remplacement a un -replace : on utilise
  [string]::Replace, litteral des deux cotes.

  Le script se termine par une verification du zip produit (contenu de
  servlist.tmpl, mot de passe intact, aucun placeholder oublie, fichiers
  attendus presents).

.PARAMETER EnvFile
  Fichier .env a lire. Defaut : le .env a la racine du projet.

.PARAMETER ZipPath
  Zip a produire. Defaut : client-package\IRC-Client.zip.

.PARAMETER Onion
  Adresse .onion a utiliser au lieu de l'interroger via docker. Sert aux
  tests du script sans serveur demarre.
#>

[CmdletBinding()]
param(
    [string]$EnvFile,
    [string]$ZipPath,
    [string]$Onion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PackageFormat = '2'          # a incrementer si la structure du zip change

$Here        = $PSScriptRoot
$ProjectRoot = Split-Path -Parent $Here
$SrcConfig   = Join-Path $Here 'config'
if (-not $EnvFile) { $EnvFile = Join-Path $ProjectRoot '.env' }
if (-not $ZipPath) { $ZipPath = Join-Path $Here 'IRC-Client.zip' }
$StageDir    = Join-Path $Here 'build-stage'

function Write-Step([string]$m) { Write-Host "[..] $m" }
function Write-Ok  ([string]$m) { Write-Host "[OK] $m" }
function Write-Warn([string]$m) { Write-Host "[!!] $m" }
function Fail      ([string]$m) { Write-Host "[XX] $m" ; throw $m }

# --------------------------------------------------------------------------
#  Lecture du .env
# --------------------------------------------------------------------------
# Decoupage sur le PREMIER "=" seulement, pour qu'un mot de passe contenant
# des "=" arrive entier. Guillemets optionnels comme chez docker compose :
# une valeur entre ' ou " est prise telle quelle, une valeur nue va jusqu'a
# la fin de la ligne (un " #" en fin de ligne est traite comme un commentaire,
# comme le fait compose).
function Read-DotEnv([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { Fail "Fichier .env introuvable : $Path" }
    $map = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        if ($t.StartsWith('export ')) { $t = $t.Substring(7).TrimStart() }
        $eq = $t.IndexOf('=')
        if ($eq -lt 1) { continue }
        $key = $t.Substring(0, $eq).Trim()
        $val = $t.Substring($eq + 1)
        if ($key -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { continue }
        if ($val.Length -ge 2 -and
            (($val.StartsWith('"') -and $val.EndsWith('"')) -or
             ($val.StartsWith("'") -and $val.EndsWith("'")))) {
            $val = $val.Substring(1, $val.Length - 2)
        } else {
            $cut = $val.IndexOf(' #')
            if ($cut -ge 0) { $val = $val.Substring(0, $cut) }
            $val = $val.TrimEnd()
        }
        $map[$key] = $val
    }
    return $map
}

function Get-EnvValue([hashtable]$Map, [string]$Key, [string]$Default) {
    if ($Map.ContainsKey($Key) -and $Map[$Key] -ne '') { return [string]$Map[$Key] }
    return $Default
}

# Substitution litterale, cote motif comme cote valeur.
function Expand-Template([string]$Source, [string]$Destination, [hashtable]$Values) {
    $text = [System.IO.File]::ReadAllText($Source)
    foreach ($key in $Values.Keys) {
        $text = $text.Replace($key, [string]$Values[$key])
    }
    [System.IO.File]::WriteAllText($Destination, $text)
}

function Write-TextFile([string]$Path, [string[]]$Lines) {
    [System.IO.File]::WriteAllText($Path, (($Lines -join "`r`n") + "`r`n"))
}

# --------------------------------------------------------------------------
#  Adresse .onion
# --------------------------------------------------------------------------
function Get-OnionFromDocker {
    Write-Step 'Lecture de l adresse .onion dans le container tor...'
    Push-Location $ProjectRoot
    try {
        # -T : sans lui, docker compose exec veut un TTY et le script echoue
        # des qu'il tourne sans console interactive (tache planifiee, CI...).
        $out = & docker compose exec -T tor cat /var/lib/tor/hidden_service/hostname 2>&1
        $code = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    if ($code -ne 0) {
        Write-Warn 'docker compose a repondu :'
        foreach ($l in @($out)) { Write-Host "       $l" }
        Fail 'Impossible de lire l adresse .onion. Les containers sont-ils demarres (setup.bat) ?'
    }
    return (($out | Out-String).Trim())
}

# --------------------------------------------------------------------------
#  Verification du zip produit
# --------------------------------------------------------------------------
# Placeholders qui DOIVENT rester dans le zip : ils sont resolus a l execution
# par start.ps1, pas a la construction.
$AllowedPlaceholders = @{
    'profile/servlist.tmpl' = @('__NICK__')
    'profile/hexchat.conf'  = @('__NICK__', '__NICK2__', '__NICK3__', '__SOCKSPORT__')
    'tor/torrc.tmpl'        = @('__TORDIR__', '__SOCKSPORT__')
}

$ExpectedEntries = @(
    'start.bat', 'start.ps1', 'uninstall.bat', 'README.txt', 'PACKAGE-INFO.txt',
    'profile/hexchat.conf', 'profile/servlist.tmpl',
    'tor/torrc.tmpl', 'tor/tor/tor.exe'
)

function Get-ZipEntryText($Zip, [string]$Name) {
    $entry = $Zip.GetEntry($Name)
    if ($null -eq $entry) { return $null }
    $stream = $entry.Open()
    $reader = New-Object System.IO.StreamReader($stream)
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() ; $stream.Dispose() }
}

function Test-Package([string]$Zip, [string]$OnionAddr, [string]$Password, [string]$Channel) {
    Write-Host ''
    Write-Step 'Verification du zip produit...'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($Zip)
    $problems = New-Object System.Collections.ArrayList
    try {
        $names = @($archive.Entries | ForEach-Object { $_.FullName })

        foreach ($expected in $ExpectedEntries) {
            if ($names -notcontains $expected) {
                [void]$problems.Add("fichier manquant dans le zip : $expected")
            }
        }

        $servlist = Get-ZipEntryText $archive 'profile/servlist.tmpl'
        if ($null -eq $servlist) {
            [void]$problems.Add('profile/servlist.tmpl illisible')
        } else {
            $lines = $servlist -split "`r?`n"
            function Get-Field([string[]]$Lines, [string]$Prefix) {
                foreach ($l in $Lines) { if ($l.StartsWith($Prefix)) { return $l.Substring($Prefix.Length) } }
                return $null
            }
            $sField = Get-Field $lines 'S='
            $pField = Get-Field $lines 'P='
            $jField = Get-Field $lines 'J='
            $fField = Get-Field $lines 'F='

            if ($sField -ne "$OnionAddr/6667") {
                [void]$problems.Add("S= attendu '$OnionAddr/6667', trouve '$sField'")
            }
            if ($Password -ne '') {
                if ($null -eq $pField -or $pField -eq '') {
                    [void]$problems.Add('P= vide alors que CONNECT_PASSWORD est renseigne')
                } elseif ($pField -ne $Password) {
                    # Comparaison exacte : c'est le test qui aurait attrape la
                    # troncature au premier "=" et la perte des "!".
                    [void]$problems.Add("P= ne correspond pas au mot de passe du .env (longueur $($pField.Length) au lieu de $($Password.Length))")
                }
            }
            if ($jField -ne $Channel) {
                [void]$problems.Add("J= attendu '$Channel', trouve '$jField'")
            }
            # 27 = cycle(1) + infos globales(2) + auto-connexion(8) + proxy(16).
            # Le bit 8 fait la connexion automatique, le bit 16 force le passage
            # par le proxy SOCKS : sans lui HexChat resoudrait le .onion en
            # direct (fuite DNS, et echec de resolution).
            if ($fField -ne '27') {
                [void]$problems.Add("F= attendu '27', trouve '$fField'")
            }
        }

        foreach ($name in $AllowedPlaceholders.Keys) {
            $text = Get-ZipEntryText $archive $name
            if ($null -eq $text) { continue }
            $found = [regex]::Matches($text, '__[A-Z0-9_]+__') |
                     ForEach-Object { $_.Value } | Sort-Object -Unique
            foreach ($ph in $found) {
                if ($AllowedPlaceholders[$name] -notcontains $ph) {
                    [void]$problems.Add("placeholder non resolu $ph dans $name")
                }
            }
        }
    } finally {
        $archive.Dispose()
    }

    if ($problems.Count -gt 0) {
        Write-Host ''
        foreach ($p in $problems) { Write-Host "       - $p" }
        Fail "$($problems.Count) probleme(s) dans le zip : package NON distribuable."
    }
    Write-Ok 'Zip verifie : adresse, mot de passe, channel, auto-connexion, fichiers.'
}

# ==========================================================================
#  Deroulement
# ==========================================================================
Write-Host ''
Write-Host '=== Generation du package client IRC ==='
Write-Host ''

$envMap   = Read-DotEnv $EnvFile
$password = Get-EnvValue $envMap 'CONNECT_PASSWORD' ''
$channel  = Get-EnvValue $envMap 'DEFAULT_CHANNEL'  '#general'
$netName  = Get-EnvValue $envMap 'IRC_NETWORK_NAME' 'MonServeurIRC'
Write-Ok "Configuration lue : $EnvFile"

if (-not $Onion) { $Onion = Get-OnionFromDocker }
$Onion = $Onion.Trim()
if ($Onion -notmatch '^[a-z2-7]{56}\.onion$') {
    Fail "Adresse .onion inattendue : '$Onion'"
}
Write-Ok "Adresse .onion : $Onion"
Write-Ok "Reseau : $netName    Channel : $channel"
if ($password -eq '') {
    Write-Warn 'CONNECT_PASSWORD est vide : le serveur sera joignable sans mot de passe.'
} else {
    Write-Ok "Mot de passe de connexion : present ($($password.Length) caracteres)"
}

# ---- Arborescence de construction ----------------------------------------
if (Test-Path -LiteralPath $StageDir) { Remove-Item -LiteralPath $StageDir -Recurse -Force }
New-Item -ItemType Directory -Path $StageDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $StageDir 'profile')  -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $StageDir 'tor\tor') -Force | Out-Null

# ---- servlist.tmpl : tout sauf le pseudo, injecte au lancement -----------
Expand-Template (Join-Path $SrcConfig 'servlist.tmpl') `
                (Join-Path $StageDir 'profile\servlist.tmpl') @{
    '__NAMESERV__' = $netName
    '__ONION__'    = $Onion
    '__CONN_PASS__'= $password
    '__CHAN__'     = $channel
}

# ---- Fichiers repris tels quels ------------------------------------------
Copy-Item (Join-Path $SrcConfig 'hexchat.conf')  (Join-Path $StageDir 'profile\hexchat.conf') -Force
Copy-Item (Join-Path $SrcConfig 'torrc.tmpl')    (Join-Path $StageDir 'tor\torrc.tmpl')       -Force
Copy-Item (Join-Path $SrcConfig 'start.bat')     (Join-Path $StageDir 'start.bat')            -Force
Copy-Item (Join-Path $SrcConfig 'start.ps1')     (Join-Path $StageDir 'start.ps1')            -Force
Copy-Item (Join-Path $SrcConfig 'uninstall.bat') (Join-Path $StageDir 'uninstall.bat')        -Force

$torSrc = Join-Path $SrcConfig 'tor\tor\tor.exe'
if (-not (Test-Path -LiteralPath $torSrc)) { Fail "tor.exe introuvable : $torSrc" }
Copy-Item $torSrc (Join-Path $StageDir 'tor\tor\tor.exe') -Force
Write-Ok 'Tor embarque (tor.exe seul : ni geoip, ni transports enfichables).'

$torVersion = 'inconnue'
try {
    $out = & $torSrc --version 2>&1 | Select-Object -First 1
    if ($out -match 'Tor version ([0-9][^ ]*)') { $torVersion = $Matches[1] }
} catch { }

# ---- PACKAGE-INFO.txt ----------------------------------------------------
# Permet a l utilisateur de savoir si son package correspond encore au
# serveur : l adresse .onion change si le volume des cles Tor est recree.
Write-TextFile (Join-Path $StageDir 'PACKAGE-INFO.txt') @(
    'Package client IRC',
    '------------------',
    "Genere le          : $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
    "Reseau             : $netName",
    "Channel            : $channel",
    "Serveur (.onion)   : $($Onion.Substring(0,8))... (8 premiers caracteres)",
    "Mot de passe       : $(if ($password -eq '') { 'aucun' } else { 'oui, inclus dans le package' })",
    "Version de Tor     : $torVersion",
    "Format du package  : $PackageFormat",
    '',
    'Si la personne qui gere le serveur annonce une nouvelle adresse dont les',
    '8 premiers caracteres ne correspondent pas a ceux ci-dessus, ton package',
    'est perime : demande-lui le zip a jour.'
)

# ---- README.txt ----------------------------------------------------------
Write-TextFile (Join-Path $StageDir 'README.txt') @(
    '====================================================================',
    " Client IRC prive -- $netName",
    '====================================================================',
    '',
    'DEMARRER',
    '--------',
    '1. Extraire TOUT le zip dans un dossier ou tu peux ecrire : tes',
    '   Documents, le Bureau, une cle USB. Surtout PAS dans',
    '   C:\Program Files : HexChat et Tor doivent ecrire leur',
    '   configuration et leurs journaux a cote de start.bat.',
    '2. Double-cliquer start.bat.',
    '3. Au premier lancement, le script demande ton pseudo. Une seule',
    "   fois : il est ensuite retenu dans nick.txt, a cote de start.bat.",
    '4. Attendre que la barre de progression de Tor atteigne 100 %',
    '   (de quelques secondes a 2-3 minutes selon ta connexion).',
    '   HexChat s ouvre alors et se connecte tout seul au serveur.',
    '',
    'IMPORTANT : laisse la fenetre noire OUVERTE pendant toute la session.',
    'C est elle qui fait tourner Tor. La fermer coupe la connexion.',
    'Pour quitter : ferme HexChat, la fenetre noire se referme ensuite',
    'toute seule et arrete Tor.',
    '',
    'RELANCER',
    '--------',
    'Double-cliquer start.bat a nouveau. Le pseudo n est plus demande.',
    'Les lancements suivants sont plus rapides : Tor garde son cache.',
    'Pour changer de pseudo : modifier nick.txt, ou le supprimer pour que',
    'la question revienne au prochain lancement.',
    '',
    'SI WINDOWS OU L ANTIVIRUS SE PLAINT',
    '-----------------------------------',
    'Un zip recu par mail ou Discord est marque "venu d Internet".',
    '',
    '* "Windows a protege votre ordinateur" (SmartScreen) sur start.bat :',
    '  cliquer "Informations complementaires" puis "Executer quand meme".',
    '  Ou, avant d extraire : clic droit sur le zip > Proprietes > cocher',
    '  "Debloquer" > OK, puis extraire.',
    '',
    '* L antivirus met tor.exe en quarantaine : tor.exe n est pas signe',
    '  numeriquement, certains antivirus s en mefient par principe. Il faut',
    '  l autoriser (ou ajouter le dossier aux exclusions). Sans lui, pas de',
    '  connexion possible.',
    '',
    'SI CA NE MARCHE PAS',
    '-------------------',
    '* "Tor n a pas fini de demarrer" : relancer start.bat. Si ca bloque',
    '  encore, le reseau filtre peut-etre Tor (wifi d entreprise, hotel,',
    '  certains operateurs mobiles) : essayer depuis un autre reseau ou un',
    '  partage de connexion telephone.',
    '* HexChat s ouvre mais reste sur "Connexion..." : normal pendant',
    '  quelques dizaines de secondes, le temps de trouver le service cache.',
    '  HexChat reessaie tout seul.',
    '* La liste des serveurs s ouvre au lieu de la connexion : le dossier',
    '  HexChatProfile est abime. Le supprimer et relancer start.bat.',
    '',
    'TOUT ENLEVER',
    '------------',
    'Double-cliquer uninstall.bat, puis supprimer le dossier.',
    'uninstall.bat enleve le cache de Tor et le profil HexChat de ce',
    'package. Il ne desinstalle HexChat que si c est ce package qui l a',
    'installe, et il ne touche pas a ta configuration HexChat personnelle',
    'dans %APPDATA%\HexChat.',
    '',
    'CE QUE CONTIENT CE DOSSIER',
    '--------------------------',
    'start.bat / start.ps1  le lanceur',
    'uninstall.bat          la desinstallation',
    'profile\               les modeles de configuration HexChat',
    'tor\tor\tor.exe        le client Tor portable',
    'PACKAGE-INFO.txt       date, serveur et channel de ce package',
    '',
    'Cree a l execution : nick.txt, HexChatProfile\, tor\torrc,',
    'tor\tor.log, tor\data\ (cache Tor, quelques dizaines de Mo).',
    '',
    'A SAVOIR',
    '--------',
    'Ce package contient l adresse .onion du serveur et son mot de passe de',
    'connexion en clair. Quiconque recupere ce zip peut se connecter au',
    'serveur : ne le redistribue pas.'
)

# ---- Zip -----------------------------------------------------------------
Write-Step 'Compression...'
# Les deux assemblages sont necessaires : ZipArchive/ZipArchiveMode viennent de
# System.IO.Compression, CreateEntryFromFile de System.IO.Compression.FileSystem.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }

# Les entrees sont ajoutees une par une, avec des noms separes par des "/".
# ZipFile::CreateFromDirectory, sous PowerShell 5 (.NET Framework), ecrit les
# chemins imbriques avec des ANTISLASHS : le zip s'extrait correctement avec
# l'explorateur Windows, mais les noms ne sont pas conformes au format et la
# verification ci-dessous ne retrouvait aucun fichier de sous-dossier.
$zipStream = $null
$archive   = $null
try {
    $zipStream = [System.IO.File]::Open($ZipPath, [System.IO.FileMode]::CreateNew)
    $archive   = New-Object System.IO.Compression.ZipArchive(
        $zipStream, [System.IO.Compression.ZipArchiveMode]::Create)
    $stageRoot = (Resolve-Path -LiteralPath $StageDir).Path.TrimEnd('\') + '\'
    foreach ($file in (Get-ChildItem -LiteralPath $StageDir -Recurse -File)) {
        $rel = $file.FullName.Substring($stageRoot.Length).Replace('\', '/')
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive, $file.FullName, $rel,
            [System.IO.Compression.CompressionLevel]::Optimal)
    }
} finally {
    if ($null -ne $archive)   { $archive.Dispose() }
    if ($null -ne $zipStream) { $zipStream.Dispose() }
}

if (-not (Test-Path -LiteralPath $ZipPath)) { Fail 'La creation du zip a echoue.' }
$sizeMb = [math]::Round((Get-Item -LiteralPath $ZipPath).Length / 1MB, 2)
Write-Ok "Zip genere : $ZipPath ($sizeMb Mo)"

Test-Package $ZipPath $Onion $password $channel

Remove-Item -LiteralPath $StageDir -Recurse -Force

Write-Host ''
Write-Host '--------------------------------------------------------------'
Write-Host " Package pret : $ZipPath"
Write-Host " $sizeMb Mo -- a distribuer a tes utilisateurs."
Write-Host ''
Write-Host ' Rappel : ce zip contient l adresse .onion ET le mot de passe du'
Write-Host ' serveur en clair. Transmets-le par un canal de confiance.'
Write-Host '--------------------------------------------------------------'
Write-Host ''
exit 0
