@echo off
rem ---------------------------------------------------------------------------
rem  Genere IRC-Client.zip, le package a distribuer aux utilisateurs.
rem
rem  Ce fichier ne fait que lancer build-client.ps1 : tout est en PowerShell
rem  parce que cmd corrompait le zip en silence. "for /f delims==" tronquait un
rem  mot de passe contenant "=", les "!" disparaissaient, un "&" pouvait
rem  executer une commande, et une apostrophe faisait echouer la substitution
rem  - le zip partait alors avec le placeholder __CONN_PASS__ tel quel.
rem
rem  Le "cd /d" est indispensable : sans lui, un lancement par "Executer en
rem  tant qu'administrateur" place le repertoire courant dans System32, et le
rem  script travaillait differemment selon le dossier d'ou on l'appelait.
rem ---------------------------------------------------------------------------
cd /d "%~dp0" || (echo [ERREUR] Impossible d'acceder au dossier du script. & pause & exit /b 1)
chcp 65001 >nul
title - Package client IRC -

docker info >nul 2>&1
if errorlevel 1 (
    echo [XX] Docker n'est pas lance : l'adresse .onion ne peut pas etre lue.
    echo      Lancez Docker Desktop, puis setup.bat, puis reessayez.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-client.ps1" %*
set RC=%ERRORLEVEL%

if not "%RC%"=="0" (
    echo.
    echo [XX] La generation a echoue -- rien n'a ete distribue.
)

echo.
pause
exit /b %RC%
