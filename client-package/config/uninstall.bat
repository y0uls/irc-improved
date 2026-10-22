@echo off
setlocal enabledelayedexpansion
rem ---------------------------------------------------------------------------
rem  Desinstallation du client IRC.
rem
rem  Ce script ne touche QUE ce que le package a installe :
rem   - il n'efface pas %APPDATA%\HexChat (config, logs et historique IRC
rem     personnels de l'utilisateur) : le package n'y a jamais ecrit ;
rem   - il n'arrete que le tor.exe du package, par PID, pas tous les tor.exe
rem     de la machine (le Tor Browser de l'utilisateur en est un) ;
rem   - il ne desinstalle HexChat que si c'est le package qui l'a installe,
rem     ce dont temoigne hexchat-installed-by-package.flag.
rem ---------------------------------------------------------------------------

set SCRIPTDIR=%~dp0
echo === Desinstallation du client IRC ===
echo.
echo Ce script va retirer de cette machine :
echo   - le proxy Tor du package et son cache (dossier tor\data)
echo   - le profil HexChat du package (dossier HexChatProfile)
if exist "%SCRIPTDIR%hexchat-installed-by-package.flag" (
    echo   - HexChat, qui avait ete installe par ce package
) else (
    echo   - HexChat sera CONSERVE : il etait deja installe avant le package
)
echo.
echo Ta configuration HexChat personnelle ^(%%APPDATA%%\HexChat^) n'est pas touchee.
echo.
set /p CONFIRM="Continuer ? [O/N] : "
if /i not "%CONFIRM%"=="O" ( echo Annule. & pause & exit /b 0 )
echo.

rem ---- HexChat doit etre ferme, mais on ne tue pas la session de l'utilisateur
tasklist /FI "IMAGENAME eq hexchat.exe" 2>nul | find /I "hexchat.exe" >nul
if not errorlevel 1 (
    echo [!!] HexChat est ouvert. Ferme-le puis relance uninstall.bat.
    echo      ^(On ne le ferme pas de force : tu as peut-etre une autre session
    echo      HexChat ouverte sur un autre serveur.^)
    pause
    exit /b 1
)

rem ---- Arret du tor du package, par PID uniquement
if exist "%SCRIPTDIR%tor\tor.pid" (
    set /p TORPID=<"%SCRIPTDIR%tor\tor.pid"
    if not "!TORPID!"=="" (
        taskkill /PID !TORPID! /F >nul 2>&1
        if not errorlevel 1 ( echo [OK] Tor du package arrete ^(PID !TORPID!^). )
    )
    del /f /q "%SCRIPTDIR%tor\tor.pid" >nul 2>&1
)

rem ---- Fichiers produits a l'execution
if exist "%SCRIPTDIR%tor\data"  rmdir /s /q "%SCRIPTDIR%tor\data"
if exist "%SCRIPTDIR%tor\torrc" del /f /q "%SCRIPTDIR%tor\torrc" >nul 2>&1
if exist "%SCRIPTDIR%tor\tor.log" del /f /q "%SCRIPTDIR%tor\tor.log" >nul 2>&1
echo [OK] Cache et configuration Tor supprimes.

if exist "%SCRIPTDIR%HexChatProfile" (
    rmdir /s /q "%SCRIPTDIR%HexChatProfile"
    echo [OK] Profil HexChat du package supprime ^(y compris ses logs^).
)
if exist "%SCRIPTDIR%nick.txt" del /f /q "%SCRIPTDIR%nick.txt" >nul 2>&1

rem ---- HexChat : seulement si c'est nous qui l'avons installe
if exist "%SCRIPTDIR%hexchat-installed-by-package.flag" (
    echo [..] Desinstallation de HexChat ^(installe par le package^)...
    winget uninstall --id HexChat.HexChat --exact --silent --accept-source-agreements >nul 2>&1
    if not errorlevel 1 (
        echo [OK] HexChat desinstalle.
    ) else (
        echo [!!] winget n'a pas pu desinstaller HexChat.
        echo      Fais-le depuis Parametres ^> Applications si tu y tiens.
    )
    del /f /q "%SCRIPTDIR%hexchat-installed-by-package.flag" >nul 2>&1
) else (
    echo [OK] HexChat conserve : ce n'est pas le package qui l'a installe.
)

echo.
echo [OK] Termine. Tu peux maintenant supprimer ce dossier.
pause
exit /b 0
