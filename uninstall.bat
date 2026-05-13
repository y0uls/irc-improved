@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

echo === Desinstallation du serveur IRC ===
echo.
echo [ATTENTION] Cette operation va supprimer :
echo    - Tous les containers (irc, tor, webclient, proxytor)
echo    - Tous les volumes Docker (cles Tor, config, logs)
echo    - Les images Docker buildees
echo    - Le fichier .env
echo.
set /p CONFIRM="Confirmer la suppression complete ? [o/N] : "
if /i "!CONFIRM!" neq "o" (
    echo Annule.
    pause
    exit /b 0
)

echo.
echo --- Arret et suppression des containers + volumes ---
docker compose down -v --remove-orphans 2>nul

echo --- Suppression des images buildees ---
docker rmi irc-server tor-hidden-service 2>nul

echo --- Suppression du .env ---
if exist ".env" del /f /q ".env"

echo.
echo [OK] Desinstallation terminee. Aucune trace laissee.
echo.
pause
