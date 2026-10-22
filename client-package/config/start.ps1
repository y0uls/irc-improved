#Requires -Version 3
<#
  Lanceur du client IRC prive (Tor + HexChat).
  Appele par start.bat -- ne pas double-cliquer ce fichier directement.

  Toute la logique delicate est ici, en un seul langage : choix du pseudo,
  generation des fichiers de config depuis les modeles, attente du bootstrap
  Tor, arret cible de Tor. La version precedente repartissait ces etapes
  entre cmd et des appels powershell successifs, ce qui est precisement la ou
  se nichaient les bugs (valeurs interpolees dans une ligne de commande, test
  sur un tableau, boucle d'attente infinie).

  Principes a ne pas casser :
   - Aucune valeur variable (pseudo, mot de passe) n'est interpolee dans une
     ligne de commande ni utilisee comme chaine de remplacement d'un -replace.
     On passe par [string]::Replace, litteral des deux cotes.
   - %APPDATA%\HexChat n'est JAMAIS touche : HexChat tourne sur un profil
     dedie, dans le dossier du package (--cfgdir).
   - On n'arrete que le tor.exe lance par ce script, par PID + verification du
     chemin de l'executable. Un "taskkill /IM tor.exe" tuerait aussi le Tor
     Browser de l'utilisateur.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------------
#  Parametres
# --------------------------------------------------------------------------
# Port SOCKS volontairement different de 9050, deja pris par Tor Browser,
# Orbot ou le service proxytor du serveur. On essaie les suivants si besoin.
$SocksPortFirst      = 9251
$SocksPortLast       = 9260
$BootstrapTimeoutSec = 300
# Pseudo IRC : 2 a 16 caracteres, commence par une lettre. Le jeu de
# caracteres exclut volontairement l'apostrophe, le dollar, l'esperluette et
# l'espace, qui cassent soit IRC soit les lignes de commande.
$NickPattern         = '^[A-Za-z][A-Za-z0-9_-]{1,15}$'

$Pkg        = $PSScriptRoot
$TorDir     = Join-Path $Pkg 'tor'
$TorExe     = Join-Path $TorDir 'tor\tor.exe'
$TorRcTmpl  = Join-Path $TorDir 'torrc.tmpl'
$TorRc      = Join-Path $TorDir 'torrc'
$TorLog     = Join-Path $TorDir 'tor.log'
$TorPidFile = Join-Path $TorDir 'tor.pid'
$ProfDir    = Join-Path $Pkg 'HexChatProfile'
$TmplDir    = Join-Path $Pkg 'profile'
$NickFile   = Join-Path $Pkg 'nick.txt'
$MarkerFile = Join-Path $Pkg 'hexchat-installed-by-package.flag'

$script:TorProcess = $null

# --------------------------------------------------------------------------
#  Utilitaires
# --------------------------------------------------------------------------
function Write-Step([string]$Message) { Write-Host "[..] $Message" }
function Write-Ok  ([string]$Message) { Write-Host "[OK] $Message" }
function Write-Warn([string]$Message) { Write-Host "[!!] $Message" }
function Write-Err ([string]$Message) { Write-Host "[XX] $Message" }

# Lit un fichier qu'un autre process tient ouvert (le journal de tor).
function Read-SharedText([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    $fs = $null
    $sr = $null
    try {
        $fs = New-Object System.IO.FileStream(
            $Path, [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $sr = New-Object System.IO.StreamReader($fs)
        return $sr.ReadToEnd()
    } catch {
        return ''
    } finally {
        if ($null -ne $sr) { $sr.Dispose() }
        if ($null -ne $fs) { $fs.Dispose() }
    }
}

# Substitution litterale : ni le motif ni la valeur ne sont interpretes.
# C'est le point important -- un mot de passe contenant $, ' ou & passe tel
# quel, alors qu'un -replace interpreterait le $ comme reference de groupe.
function Expand-Template([string]$Source, [string]$Destination, [hashtable]$Values) {
    $text = [System.IO.File]::ReadAllText($Source)
    foreach ($key in $Values.Keys) {
        $text = $text.Replace($key, [string]$Values[$key])
    }
    [System.IO.File]::WriteAllText($Destination, $text)
}

# Remplace la valeur d'une cle "cle = valeur" dans un fichier HexChat.
# La boucle est indexee et le drapeau explicite : un test du genre
# "if ($lignes -notmatch '^cle')" sur un TABLEAU est toujours vrai et
# ajouterait une ligne de plus a chaque lancement.
function Set-ConfValue([string]$Path, [string]$Key, [string]$Value) {
    $lines   = [System.IO.File]::ReadAllLines($Path)
    $pattern = '^\s*' + [regex]::Escape($Key) + '\s*='
    $found   = $false
    for ($i = 0; $i -lt $lines.Length; $i++) {
        if ($lines[$i] -match $pattern) {
            $lines[$i] = "$Key = $Value"
            $found = $true
        }
    }
    if (-not $found) { $lines = $lines + "$Key = $Value" }
    [System.IO.File]::WriteAllLines($Path, $lines)
}

function Test-PortFree([int]$Port) {
    $client = $null
    try {
        $client = New-Object Net.Sockets.TcpClient
        $client.Connect('127.0.0.1', $Port)
        return $false          # quelque chose repond deja : port occupe
    } catch {
        return $true
    } finally {
        if ($null -ne $client) { $client.Close() }
    }
}

# --------------------------------------------------------------------------
#  Etape 0 : dossier inscriptible, Mark-of-the-Web
# --------------------------------------------------------------------------
function Test-Writable {
    $probe = Join-Path $Pkg '.write-test'
    try {
        [System.IO.File]::WriteAllText($probe, 'x')
        Remove-Item -LiteralPath $probe -Force
    } catch {
        Write-Err "Ce dossier n'est pas inscriptible :"
        Write-Err "  $Pkg"
        Write-Host ''
        Write-Host '     HexChat et Tor doivent y ecrire leur configuration.'
        Write-Host '     Deplace le dossier IRC-Client dans tes Documents ou sur le'
        Write-Host '     Bureau (pas dans C:\Program Files) puis relance start.bat.'
        throw 'Dossier non inscriptible.'
    }
}

# Les fichiers sortis d'un zip recu par mail ou Discord portent une marque
# "venu d'Internet" : SmartScreen bloque start.bat et l'antivirus se mefie de
# tor.exe, qui n'est pas signe.
function Clear-MarkOfTheWeb {
    try {
        Get-ChildItem -LiteralPath $Pkg -Recurse -File -ErrorAction SilentlyContinue |
            Unblock-File -ErrorAction SilentlyContinue
    } catch { }
}

# --------------------------------------------------------------------------
#  Etape 1 : HexChat
# --------------------------------------------------------------------------
function Get-HexChatExe {
    $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)
    foreach ($root in $roots) {
        if ([string]::IsNullOrEmpty($root)) { continue }
        $exe = Join-Path $root 'HexChat\hexchat.exe'
        if (Test-Path -LiteralPath $exe) { return $exe }
    }
    return $null
}

function Install-HexChat {
    Write-Step 'HexChat absent : installation via winget...'
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Err "winget n'est pas disponible sur cette machine."
        Write-Host ''
        Write-Host '     Installe HexChat a la main depuis https://hexchat.github.io/'
        Write-Host '     puis relance start.bat.'
        throw 'winget introuvable.'
    }
    winget install --id HexChat.HexChat --exact --silent `
           --accept-package-agreements --accept-source-agreements
    $exe = Get-HexChatExe
    if (-not $exe) {
        Write-Err 'HexChat reste introuvable apres installation.'
        Write-Host '     Installe-le a la main depuis https://hexchat.github.io/'
        throw 'HexChat introuvable.'
    }
    # Temoin : uninstall.bat ne desinstallera HexChat que si c'est NOUS qui
    # l'avons installe. Sans ce fichier, on desinstallerait un HexChat que
    # l'utilisateur avait peut-etre depuis des annees.
    [System.IO.File]::WriteAllText($MarkerFile,
        "HexChat a ete installe par ce package le " +
        (Get-Date -Format 'yyyy-MM-dd HH:mm') + ".`r`n" +
        "Supprime ce fichier pour garder HexChat apres la desinstallation.`r`n")
    Write-Ok 'HexChat installe.'
    return $exe
}

# --------------------------------------------------------------------------
#  Etape 2 : pseudo, demande une seule fois
# --------------------------------------------------------------------------
function Request-Nick {
    Write-Host ''
    Write-Host '  ------------------------------------------------------------'
    Write-Host '   Premiere utilisation : choisis ton pseudo IRC.'
    Write-Host '   Lettres, chiffres, - et _ ; de 2 a 16 caracteres ;'
    Write-Host '   il commence par une lettre. Il sera retenu pour la suite.'
    Write-Host '  ------------------------------------------------------------'
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        $answer = Read-Host '   Ton pseudo'
        if ($null -eq $answer) { $answer = '' }
        $answer = $answer.Trim()
        if ($answer -match $NickPattern) { return $answer }
        Write-Warn 'Pseudo refuse : lettres, chiffres, - et _ seulement, 2 a 16 caracteres.'
    }
    throw 'Aucun pseudo valide fourni.'
}

function Get-Nick {
    if (Test-Path -LiteralPath $NickFile) {
        $saved = ''
        try {
            $lines = [System.IO.File]::ReadAllLines($NickFile)
            if ($lines.Length -gt 0) { $saved = $lines[0].Trim() }
        } catch {
            $saved = ''
        }
        if ($saved -match $NickPattern) { return $saved }
        Write-Warn 'Le pseudo enregistre dans nick.txt est invalide, on le redemande.'
    }
    $nick = Request-Nick
    [System.IO.File]::WriteAllText($NickFile, $nick + "`r`n")
    Write-Ok "Pseudo enregistre : $nick (modifiable dans nick.txt)"
    return $nick
}

# --------------------------------------------------------------------------
#  Etape 3 : profil HexChat dedie
# --------------------------------------------------------------------------
function Update-HexChatProfile([string]$Nick, [int]$SocksPort) {
    if (-not (Test-Path -LiteralPath $ProfDir)) {
        New-Item -ItemType Directory -Path $ProfDir -Force | Out-Null
    }
    $conf = Join-Path $ProfDir 'hexchat.conf'

    # hexchat.conf : cree au premier lancement seulement. HexChat le reecrit
    # en quittant (taille de fenetre, etc.) et on ne veut pas ecraser ces
    # reglages a chaque lancement -- c'est ce que faisait le xcopy /E /Y.
    if (-not (Test-Path -LiteralPath $conf)) {
        Expand-Template (Join-Path $TmplDir 'hexchat.conf') $conf @{
            '__NICK__'      = $Nick
            '__NICK2__'     = $Nick + '_'
            '__NICK3__'     = $Nick + '__'
            '__SOCKSPORT__' = [string]$SocksPort
        }
        Write-Ok "Profil HexChat cree : $ProfDir"
    }

    # A chaque lancement : le port SOCKS peut avoir change (port occupe) et le
    # pseudo peut avoir ete modifie dans nick.txt.
    Set-ConfValue $conf 'net_proxy_port' ([string]$SocksPort)
    Set-ConfValue $conf 'irc_nick1'      $Nick
    Set-ConfValue $conf 'irc_nick2'      ($Nick + '_')
    Set-ConfValue $conf 'irc_nick3'      ($Nick + '__')
    Set-ConfValue $conf 'irc_user_name'  $Nick
    Set-ConfValue $conf 'irc_real_name'  $Nick
    Set-ConfValue $conf 'gui_slist_skip' '1'

    # servlist.conf : regenere depuis le modele a chaque lancement. C'est le
    # fichier qui porte l'adresse .onion, le mot de passe, le channel et
    # l'auto-connexion (F=27). Le regenerer garantit qu'un reglage change par
    # megarde dans l'interface ne casse pas la connexion au lancement suivant.
    Expand-Template (Join-Path $TmplDir 'servlist.tmpl') `
                    (Join-Path $ProfDir 'servlist.conf') `
                    @{ '__NICK__' = $Nick }
}

# --------------------------------------------------------------------------
#  Etape 4 : Tor
# --------------------------------------------------------------------------
# Verifie que ce PID est bien NOTRE tor.exe, et pas celui du Tor Browser de
# l'utilisateur (Windows recycle aussi les PID).
function Test-OurTor($Process) {
    if ($null -eq $Process) { return $false }
    try {
        if ([string]::IsNullOrEmpty($Process.Path)) { return $false }
        return ([System.IO.Path]::GetFullPath($Process.Path) -eq
                [System.IO.Path]::GetFullPath($TorExe))
    } catch {
        return $false
    }
}

# Un tor du package laisse par un lancement precedent (fenetre fermee en
# croix, plantage) garderait le port et le dossier de donnees.
function Stop-StaleTor {
    if (-not (Test-Path -LiteralPath $TorPidFile)) { return }
    $raw = ''
    try { $raw = ([System.IO.File]::ReadAllText($TorPidFile)).Trim() } catch { return }
    $stalePid = 0
    if ([int]::TryParse($raw, [ref]$stalePid) -and $stalePid -gt 0) {
        $proc = Get-Process -Id $stalePid -ErrorAction SilentlyContinue
        if (Test-OurTor $proc) {
            Write-Step "Arret d'un Tor du package reste actif (PID $stalePid)..."
            try { Stop-Process -Id $stalePid -Force -ErrorAction Stop } catch { }
            Start-Sleep -Milliseconds 800
        }
    }
    Remove-Item -LiteralPath $TorPidFile -Force -ErrorAction SilentlyContinue
}

function Get-SocksPort {
    for ($port = $SocksPortFirst; $port -le $SocksPortLast; $port++) {
        if (Test-PortFree $port) { return $port }
        Write-Warn "Port $port deja utilise, on essaie le suivant."
    }
    throw "Aucun port libre entre $SocksPortFirst et $SocksPortLast."
}

function Start-Tor([int]$SocksPort) {
    if (-not (Test-Path -LiteralPath $TorExe)) {
        Write-Err "tor.exe est introuvable : $TorExe"
        Write-Host '     Le zip a probablement ete extrait partiellement, ou bien'
        Write-Host '     l antivirus a mis tor.exe en quarantaine (il n est pas signe).'
        throw 'tor.exe introuvable.'
    }

    # torrc regenere a chaque lancement : le dossier peut avoir ete deplace, et
    # tor exige des chemins absolus (il resout le relatif par rapport au
    # repertoire courant du process, pas par rapport au torrc).
    Expand-Template $TorRcTmpl $TorRc @{
        '__TORDIR__'    = $TorDir.TrimEnd('\')
        '__SOCKSPORT__' = [string]$SocksPort
    }

    # Journal remis a zero : sinon on relirait le "Bootstrapped 100%" du
    # lancement precedent et HexChat partirait avant que Tor soit pret.
    Remove-Item -LiteralPath $TorLog -Force -ErrorAction SilentlyContinue

    Write-Step "Demarrage de Tor (proxy SOCKS 127.0.0.1:$SocksPort)..."
    # -WorkingDirectory : tor cherche geoip/geoip6 en chemin relatif. Sans
    # cela il les cherche dans le repertoire courant (C:\Windows) et le dit.
    $script:TorProcess = Start-Process -FilePath $TorExe `
        -ArgumentList @('-f', $TorRc) `
        -WorkingDirectory $TorDir `
        -WindowStyle Hidden -PassThru
    [System.IO.File]::WriteAllText($TorPidFile, [string]$script:TorProcess.Id)
}

function Show-TorLogTail {
    $log = Read-SharedText $TorLog
    if (-not $log) {
        Write-Host '     (journal tor.log vide ou absent)'
        return
    }
    Write-Host ''
    Write-Host "     Dernieres lignes de $TorLog :"
    $lines = $log -split "`r?`n" | Where-Object { $_ -ne '' }
    foreach ($l in ($lines | Select-Object -Last 12)) { Write-Host "       $l" }
}

# Attend le vrai signal de disponibilite : "Bootstrapped 100%".
# L'ancienne version attendait que 127.0.0.1:9050 accepte le TCP, ce qui
# arrive environ 1 seconde apres le lancement de tor.exe -- bien avant que le
# reseau Tor soit utilisable (mesure : port ouvert a 1 s, bootstrap complet
# entre 12 s et pres de 3 minutes selon la qualite du reseau).
function Wait-TorBootstrap {
    $started = Get-Date
    $lastPct = -1
    $lastTag = ''
    $rx      = [regex]'Bootstrapped (\d+)%\s*(?:\(([^)]*)\))?'
    Write-Host ''
    while ($true) {
        $elapsed = [int]((Get-Date) - $started).TotalSeconds
        $log     = Read-SharedText $TorLog

        if ($log) {
            $hits = $rx.Matches($log)
            if ($hits.Count -gt 0) {
                $last = $hits[$hits.Count - 1]
                $pct  = [int]$last.Groups[1].Value
                $tag  = $last.Groups[2].Value
                if ($pct -ne $lastPct -or $tag -ne $lastTag) {
                    $lastPct = $pct
                    $lastTag = $tag
                    Write-Host ("`r   Tor : {0,3} %  {1,-34} ({2} s)  " -f $pct, $tag, $elapsed) -NoNewline
                }
                if ($pct -ge 100) {
                    Write-Host ''
                    Write-Ok "Reseau Tor pret en $elapsed s."
                    return
                }
            } else {
                Write-Host ("`r   Tor : demarrage...  ({0} s)  " -f $elapsed) -NoNewline
            }
        }

        # Tor s'est arrete tout seul : inutile d'attendre, on montre pourquoi.
        if ($script:TorProcess.HasExited) {
            Write-Host ''
            Write-Err "Tor s'est arrete tout seul (code $($script:TorProcess.ExitCode))."
            Show-TorLogTail
            Write-Host ''
            Write-Host '     Causes habituelles : port SOCKS deja pris, tor.exe mis en'
            Write-Host '     quarantaine par l antivirus, dossier non inscriptible.'
            throw 'Tor ne demarre pas.'
        }

        if ($elapsed -ge $BootstrapTimeoutSec) {
            Write-Host ''
            Write-Err "Tor n a pas fini de demarrer en $BootstrapTimeoutSec s (arrive a $lastPct %)."
            Show-TorLogTail
            Write-Host ''
            Write-Host '     A essayer, dans cet ordre :'
            Write-Host '      1. relancer start.bat : le cache Tor est conserve, ca va plus vite ;'
            Write-Host '      2. verifier la connexion Internet ;'
            Write-Host '      3. si le reseau bloque Tor (wifi d entreprise, hotel, certains'
            Write-Host '         operateurs mobiles), essayer depuis un autre reseau ou un'
            Write-Host '         partage de connexion telephone.'
            throw 'Bootstrap Tor incomplet.'
        }

        Start-Sleep -Milliseconds 700
    }
}

function Stop-PackageTor {
    if ($null -eq $script:TorProcess) { return }
    try {
        if (-not $script:TorProcess.HasExited) {
            $proc = Get-Process -Id $script:TorProcess.Id -ErrorAction SilentlyContinue
            if (Test-OurTor $proc) {
                Write-Step 'Arret de Tor...'
                Stop-Process -Id $script:TorProcess.Id -Force -ErrorAction SilentlyContinue
                Write-Ok 'Tor arrete.'
            }
        }
    } catch { }
    Remove-Item -LiteralPath $TorPidFile -Force -ErrorAction SilentlyContinue
}

# --------------------------------------------------------------------------
#  Deroulement
# --------------------------------------------------------------------------
try {
    Write-Host ''
    Write-Host '  ============================================================'
    Write-Host '   Client IRC prive  --  connexion via Tor'
    Write-Host '  ============================================================'
    Write-Host ''
    Write-Host '  Laisse cette fenetre OUVERTE pendant toute la session :'
    Write-Host '  c est elle qui fait tourner Tor. La fermer coupe la connexion.'
    Write-Host ''

    Test-Writable
    Clear-MarkOfTheWeb

    $hexchat = Get-HexChatExe
    if (-not $hexchat) { $hexchat = Install-HexChat }
    Write-Ok "HexChat : $hexchat"

    $nick = Get-Nick
    Write-Ok "Pseudo : $nick"

    Stop-StaleTor
    $socksPort = Get-SocksPort
    Update-HexChatProfile $nick $socksPort
    Write-Ok 'Configuration prete (profil dedie, %APPDATA%\HexChat intact).'

    Start-Tor $socksPort
    Wait-TorBootstrap

    if (Test-PortFree $socksPort) {
        Write-Warn "Le proxy SOCKS ne repond pas sur 127.0.0.1:$socksPort alors que"
        Write-Warn 'Tor se dit pret. On lance HexChat quand meme.'
    }

    Write-Host ''
    Write-Ok 'Lancement de HexChat (connexion automatique au serveur).'
    Write-Host '     La premiere tentative peut echouer le temps que Tor trouve le'
    Write-Host '     service .onion : HexChat reessaie tout seul, laisse-le faire.'
    Write-Host ''
    $hc = Start-Process -FilePath $hexchat -ArgumentList @("--cfgdir=$ProfDir") -PassThru
    $hc.WaitForExit()
    Write-Host ''
    Write-Ok 'HexChat ferme.'
    exit 0
}
catch {
    Write-Host ''
    Write-Err $_.Exception.Message
    exit 1
}
finally {
    Stop-PackageTor
}
