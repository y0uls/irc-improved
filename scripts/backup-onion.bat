@echo off
rem ======================================================================
rem  Sauvegarde l'identite du serveur : les cles du service cache Tor.
rem
rem  Ces cles SONT l'adresse .onion. Si le volume tor_keys est perdu
rem  (uninstall, "docker compose down -v", suppression des volumes,
rem  renommage du dossier du projet), l'adresse est definitivement
rem  irrecuperable : tous les packages clients deja distribues deviennent
rem  inutilisables et il faut redistribuer a tout le monde.
rem ======================================================================
cd /d "%~dp0.." || (echo [ERREUR] Dossier du projet introuvable. & pause & exit /b 1)
setlocal enabledelayedexpansion
chcp 65001 >nul

docker info >nul 2>&1
if errorlevel 1 (
    echo [ERREUR] Docker n'est pas lance.
    pause
    exit /b 1
)

set "BACKUPDIR=%CD%\backup"
if not exist "!BACKUPDIR!" mkdir "!BACKUPDIR!"

for /f "usebackq delims=" %%A in (`docker compose exec -T tor cat /var/lib/tor/hidden_service/hostname 2^>nul`) do set "ONION=%%A"

for /f "usebackq delims=" %%D in (`powershell -NoProfile -Command "(Get-Date).ToString('yyyyMMdd-HHmmss')"`) do set "STAMP=%%D"
set "OUT=!BACKUPDIR!\tor-keys-!STAMP!.tgz"

echo === Sauvegarde des cles du service cache ===
if not "!ONION!"=="" echo Adresse : !ONION!
echo.

docker run --rm -v irc-improved_tor_keys:/k:ro -v "!BACKUPDIR!:/b" alpine tar czf "/b/tor-keys-!STAMP!.tgz" -C /k .
if errorlevel 1 (
    echo [ERREUR] La sauvegarde a echoue.
    echo          Le volume irc-improved_tor_keys existe-t-il ? docker volume ls
    pause
    exit /b 1
)

if not "!ONION!"=="" echo !ONION! > "!BACKUPDIR!\tor-keys-!STAMP!.onion.txt"

echo [OK] Sauvegarde : !OUT!
echo.
echo [IMPORTANT] Ce fichier contient la cle privee du service cache :
echo             conservez-le comme un mot de passe (quiconque l'a peut
echo             usurper votre adresse .onion).
echo.
echo Restauration : scripts\restore-onion.bat "!OUT!"
echo.
pause
