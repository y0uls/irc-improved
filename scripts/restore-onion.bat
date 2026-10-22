@echo off
rem ======================================================================
rem  Restaure l'adresse .onion depuis une sauvegarde faite par
rem  scripts\backup-onion.bat
rem
rem  Usage : scripts\restore-onion.bat chemin\vers\tor-keys-....tgz
rem ======================================================================
cd /d "%~dp0.." || (echo [ERREUR] Dossier du projet introuvable. & pause & exit /b 1)
setlocal enabledelayedexpansion
chcp 65001 >nul

set "ARCHIVE=%~1"
if "!ARCHIVE!"=="" (
    echo Usage : scripts\restore-onion.bat chemin\vers\tor-keys-AAAAMMJJ-HHMMSS.tgz
    echo.
    echo Sauvegardes disponibles :
    if exist "%CD%\backup" dir /b "%CD%\backup\*.tgz" 2>nul
    pause
    exit /b 1
)
if not exist "!ARCHIVE!" (
    echo [ERREUR] Fichier introuvable : !ARCHIVE!
    pause
    exit /b 1
)

docker info >nul 2>&1
if errorlevel 1 (
    echo [ERREUR] Docker n'est pas lance.
    pause
    exit /b 1
)

echo [ATTENTION] Cette operation remplace l'identite actuelle du serveur
echo             (l'adresse .onion en cours) par celle de la sauvegarde.
set /p "CONFIRM=Confirmer ? (O/N) [N] : "
if /I not "!CONFIRM!"=="O" (
    echo Annule.
    pause
    exit /b 0
)

docker compose stop tor >nul 2>&1

for %%F in ("!ARCHIVE!") do set "ARCHDIR=%%~dpF"
for %%F in ("!ARCHIVE!") do set "ARCHNAME=%%~nxF"

rem Les cles doivent appartenir a l'utilisateur tor (uid 100) et le
rem repertoire etre en 700, sinon tor refuse de demarrer
rem ("... is not owned by this user (tor, 100)").
docker run --rm -v irc-improved_tor_keys:/k -v "!ARCHDIR!:/in:ro" alpine sh -c "rm -rf /k/* && tar xzf '/in/!ARCHNAME!' -C /k && chown -R 100:100 /k && chmod 700 /k && chmod 600 /k/hs_ed25519_*"
if errorlevel 1 (
    echo [ERREUR] La restauration a echoue.
    pause
    exit /b 1
)

docker compose up -d tor >nul
if errorlevel 1 (
    echo [ERREUR] Les cles sont restaurees, mais tor n'a pas redemarre.
    echo          Diagnostic : docker compose up -d
    pause
    exit /b 1
)

rem On affiche l'adresse effectivement publiee, et on verifie qu'il y en a
rem une : sans ce controle, le script annoncait "[OK] Cles restaurees" meme
rem quand tor n'avait rien republie.
set "NEWONION="
for /f "usebackq delims=" %%A in (`docker compose exec -T tor cat /var/lib/tor/hidden_service/hostname 2^>nul`) do set "NEWONION=%%A"
echo.
if "!NEWONION!"=="" (
    echo [ERREUR] Aucune adresse .onion publiee apres la restauration.
    echo          Diagnostic : docker compose logs tor
    pause
    exit /b 1
)
echo [OK] Cles restaurees. Adresse publiee :
echo     !NEWONION!
echo.
pause
