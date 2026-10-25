@echo off
rem ======================================================================
rem  Setup et demarrage du serveur IRC.
rem
rem  Le "cd /d" est la premiere instruction : sans lui, un lancement par
rem  "Executer en tant qu'administrateur" place le repertoire courant dans
rem  C:\Windows\System32. Le .env etait alors introuvable, AUCUNE question
rem  n'etait posee, et le script affichait quand meme [OK].
rem ======================================================================
cd /d "%~dp0" || (echo [ERREUR] Impossible d'acceder au dossier du script. & pause & exit /b 1)
setlocal enabledelayedexpansion
chcp 65001 >nul
title - Setup IRC Server -

echo === Setup du serveur IRC ===
echo.

docker info >nul 2>&1
if errorlevel 1 (
    echo [ERREUR] Docker n'est pas lance ou n'est pas installe.
    echo          Lancez Docker Desktop puis reessayez.
    pause
    exit /b 1
)

rem ----------------------------------------------------------------------
rem  Configuration (toute la saisie est faite par tools\configure.ps1 :
rem  un mot de passe contenant ' $ & ! = ou un accent y est gere sans
rem  risque, ce qui n'etait pas le cas en batch).
rem ----------------------------------------------------------------------
set "RECONF="
if exist ".env" (
    findstr /R /C:"^OPER_PASSWORD=." .env >nul 2>&1
    if not errorlevel 1 (
        echo Ce serveur est deja configure.
        set /p "ANS=Revoir la configuration (mots de passe, channel) ? (O/N) [N] : "
        if /I "!ANS!"=="O" set "RECONF=-Force"
        echo.
    )
)

powershell -NoProfile -ExecutionPolicy Bypass -File "tools\configure.ps1" !RECONF!
if errorlevel 1 (
    echo [ERREUR] La configuration a echoue. Rien n'a ete demarre.
    pause
    exit /b 1
)

rem ----------------------------------------------------------------------
rem  Build + demarrage.
rem  Le serveur IRC, le service cache Tor et l'interface web demarrent
rem  ensemble : la meme adresse .onion publie les deux (IRC sur 6667,
rem  interface web sur 80). Les services restes optionnels sont des
rem  profils docker compose, pilotes par COMPOSE_PROFILES dans le .env.
rem ----------------------------------------------------------------------
echo.
echo === Build des images ===
docker compose build
if errorlevel 1 (
    echo [ERREUR] Le build a echoue.
    pause
    exit /b 1
)

set "IRCID_BEFORE="
for /f "usebackq delims=" %%I in (`docker compose ps -q irc 2^>nul`) do set "IRCID_BEFORE=%%I"
set "WEBID_BEFORE="
for /f "usebackq delims=" %%I in (`docker compose ps -q webclient 2^>nul`) do set "WEBID_BEFORE=%%I"

echo.
echo === Demarrage des services ===
docker compose up -d --remove-orphans
if errorlevel 1 (
    echo [ERREUR] Le demarrage a echoue. Diagnostic : docker compose logs
    pause
    exit /b 1
)

set "IRCID_AFTER="
for /f "usebackq delims=" %%I in (`docker compose ps -q irc 2^>nul`) do set "IRCID_AFTER=%%I"
set "WEBID_AFTER="
for /f "usebackq delims=" %%I in (`docker compose ps -q webclient 2^>nul`) do set "WEBID_AFTER=%%I"

rem Tor ne resout les cibles de son service cache qu'a son demarrage : si
rem un conteneur cible a ete recree, il a une nouvelle IP et tor repond
rem dans le vide jusqu'a son redemarrage. Vrai pour irc (port 6667) comme
rem pour webclient (port 80).
set "NEEDTOR="
if not "!IRCID_BEFORE!"=="!IRCID_AFTER!" if not "!IRCID_BEFORE!"=="" set "NEEDTOR=1"
if not "!WEBID_BEFORE!"=="!WEBID_AFTER!" if not "!WEBID_BEFORE!"=="" set "NEEDTOR=1"
if defined NEEDTOR echo [INFO] Un conteneur cible a ete recree : redemarrage de Tor...

rem Et le cas que la comparaison d'ID ne voit pas : tor tourne en mode
rem repli (sans la ligne du service web) alors que webclient est la.
rem Cela arrive quand Docker Desktop a relance les conteneurs lui-meme,
rem dans le desordre - le demon ignore depends_on. Les ID n'ont alors pas
rem change, mais http://<onion>/ ne repond pas. On repare ici, sinon il
rem faudrait que l'administrateur pense a "docker compose restart tor".
if not defined NEEDTOR (
    if not "!WEBID_AFTER!"=="" (
        set "WEBLINE="
        for /f "usebackq delims=" %%L in (`docker compose exec -T tor grep -c "HiddenServicePort 80" /tmp/torrc 2^>nul`) do set "WEBLINE=%%L"
        if "!WEBLINE!"=="0" (
            echo [INFO] Le service cache web etait desactive : redemarrage de Tor...
            set "NEEDTOR=1"
        )
    )
)

if defined NEEDTOR docker compose restart tor >nul

rem ----------------------------------------------------------------------
rem  Attente reelle de l'adresse .onion (l'ancienne version attendait
rem  30 secondes a l'aveugle, puis annoncait "[OK] Service Tor pret").
rem ----------------------------------------------------------------------
echo.
echo === Publication du service cache Tor ===
set "ONION="
set /a TRIES=0
:waitonion
for /f "usebackq delims=" %%A in (`docker compose exec -T tor cat /var/lib/tor/hidden_service/hostname 2^>nul`) do set "ONION=%%A"
if "!ONION!"=="" (
    set /a TRIES+=1
    if !TRIES! LSS 45 (
        <nul set /p "=."
        timeout /t 2 /nobreak >nul
        goto :waitonion
    )
    echo.
    echo [ERREUR] Tor n'a pas publie d'adresse .onion.
    echo          Diagnostic : docker compose logs tor
    pause
    exit /b 1
)
echo.
echo [OK] Adresse .onion publiee.

rem ----------------------------------------------------------------------
rem  Comptes de l'interface web.
rem  L'adresse .onion publie aussi The Lounge : la page de connexion est
rem  atteignable par quiconque connait l'adresse. Le compte nominatif est
rem  donc le vrai controle d'acces - un compte par personne.
rem ----------------------------------------------------------------------
set "NBUSERS="
for /f "usebackq delims=" %%N in (`docker compose exec -T webclient sh -c "ls /var/opt/thelounge/users/*.json 2>/dev/null | wc -l" 2^>nul`) do set "NBUSERS=%%N"

set "FIRSTUSER="
if "!NBUSERS!"=="" (
    rem Valeur vide = la commande n'a pas pu s'executer, pas "zero compte".
    rem Sans ce test, un webclient en panne passait pour un serveur deja
    rem pourvu en comptes et le recapitulatif annoncait quand meme l'URL.
    echo.
    echo [ATTENTION] Impossible de lire les comptes de l'interface web.
    echo             Le conteneur webclient a-t-il demarre ?
    echo             Diagnostic : docker compose logs webclient
) else if "!NBUSERS!"=="0" (
    echo.
    echo === Premier compte pour l'interface web ===
    echo Un compte par personne : c'est ce qui protege l'acces web.
    set /p "LOUNGE_USER=Pseudo (Entree = plus tard) : "
    if not "!LOUNGE_USER!"=="" (
        set "IRC_NO_PAUSE=1"
        call "scripts\add-user.bat" "!LOUNGE_USER!"
        set "IRC_NO_PAUSE="
        set "FIRSTUSER=!LOUNGE_USER!"
    )
)

rem ----------------------------------------------------------------------
rem  Invitation a distribuer : adresse web, adresse IRC, salon, et la
rem  consigne "niveau de securite Standard" dans Tor Browser. Plus un QR
rem  code de l'URL web.
rem ----------------------------------------------------------------------
echo.
echo === Invitation ===
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\make-invite.ps1" >nul

rem ----------------------------------------------------------------------
rem  Recapitulatif : tout ce qu'il faut pour faire entrer quelqu'un.
rem
rem  Ecrit par tools\show-summary.ps1, qui lit lui-meme le .env. Les mots
rem  de passe etaient lus ici par un for /f, sous enabledelayedexpansion :
rem  leur ! etait mange au moment du set, et le ^ avec lui. Pass!word42
rem  s'affichait Password42, et le /OPER recopie depuis cet ecran
rem  echouait. Aucune valeur du .env ne doit transiter par ce script.
rem ----------------------------------------------------------------------
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\show-summary.ps1" -Onion "!ONION!" -FirstUser "!FIRSTUSER!"
echo.
pause
