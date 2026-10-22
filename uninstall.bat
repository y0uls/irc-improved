@echo off
rem ======================================================================
rem  Desinstallation du serveur IRC.
rem
rem  Le "cd /d" est obligatoire : sans lui, un lancement en tant
rem  qu'administrateur travaillerait depuis C:\Windows\System32 et les
rem  commandes docker compose ne trouveraient pas le projet.
rem ======================================================================
cd /d "%~dp0" || (echo [ERREUR] Impossible d'acceder au dossier du script. & pause & exit /b 1)
setlocal enabledelayedexpansion
chcp 65001 >nul

echo === Desinstallation du serveur IRC ===
echo.
echo [ATTENTION] Cette operation va supprimer :
echo    - Tous les containers (irc, tor, webclient, proxytor)
echo    - Les volumes Docker (config, logs, comptes de l'interface web)
echo    - Les images Docker buildees
echo    - Le fichier .env (mots de passe)
echo.
set /p CONFIRM="Confirmer la suppression ? (O/N) [N] : "
if /i not "!CONFIRM!"=="O" (
    echo Annule.
    pause
    exit /b 0
)

rem ----------------------------------------------------------------------
rem  L'adresse .onion fait l'objet d'une question SEPAREE : c'est la seule
rem  donnee irrecuperable du projet. La supprimer rend inutilisables tous
rem  les packages clients deja distribues.
rem ----------------------------------------------------------------------
echo.
set "ONION="
for /f "usebackq delims=" %%A in (`docker compose exec -T tor cat /var/lib/tor/hidden_service/hostname 2^>nul`) do set "ONION=%%A"
if not "!ONION!"=="" echo Adresse actuelle : !ONION!
echo.
echo L'adresse .onion est definie par des cles qui n'existent qu'ici.
echo Si vous les supprimez, elle est perdue DEFINITIVEMENT et tous les
echo clients deja distribues cessent de fonctionner.
echo.
set /p KEEPKEYS="Conserver l'adresse .onion (cles Tor) ? (O/N) [O] : "
if /i "!KEEPKEYS!"=="N" (
    set "DROPKEYS=1"
) else (
    set "DROPKEYS="
    echo [INFO] Les cles Tor seront conservees dans le volume irc-improved_tor_keys.
)

if defined DROPKEYS (
    echo.
    echo Une sauvegarde des cles peut etre ecrite dans .\backup avant suppression.
    set /p DOBACKUP="Sauvegarder les cles avant de les supprimer ? (O/N) [O] : "
    if /i not "!DOBACKUP!"=="N" (
        if not exist "%CD%\backup" mkdir "%CD%\backup"
        for /f "usebackq delims=" %%D in (`powershell -NoProfile -Command "(Get-Date).ToString('yyyyMMdd-HHmmss')"`) do set "STAMP=%%D"
        docker run --rm -v irc-improved_tor_keys:/k:ro -v "%CD%\backup:/b" alpine tar czf "/b/tor-keys-!STAMP!.tgz" -C /k . 2>nul
        if errorlevel 1 (
            echo [ATTENTION] La sauvegarde a echoue - suppression annulee par securite.
            set "DROPKEYS="
        ) else (
            if not "!ONION!"=="" echo !ONION! > "%CD%\backup\tor-keys-!STAMP!.onion.txt"
            echo [OK] Sauvegarde : backup\tor-keys-!STAMP!.tgz
        )
    )
)

echo.
echo --- Arret et suppression des containers ---
docker compose down --remove-orphans 2>nul

echo --- Suppression des volumes ---
docker volume rm irc-improved_irc_conf irc-improved_irc_logs irc-improved_thelounge_data 2>nul
if defined DROPKEYS (
    docker volume rm irc-improved_tor_keys 2>nul
    echo [OK] Cles Tor supprimees.
)

echo --- Suppression des images buildees ---
docker rmi irc-server tor-hidden-service 2>nul

echo --- Suppression du .env ---
if exist ".env" del /f /q ".env"

echo.
echo [OK] Desinstallation terminee.
if not defined DROPKEYS (
    echo.
    echo L'adresse .onion a ete conservee : relancez setup.bat pour
    echo remonter le serveur avec la meme adresse.
)
echo.
echo A supprimer eventuellement a la main (ils contiennent l'adresse et
echo des mots de passe en clair) :
echo    invite.txt  /  invite-*.txt  /  invite-qr.png
echo    client-package\IRC-Client.zip
echo    backup\*.tgz
echo.
pause
