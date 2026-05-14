@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul
echo === Desinstallation IRC Client ===
echo.
set /p CONFIRM="Confirmer la desinstallation complete ? [O/N] : "
if /i not "%CONFIRM%"=="O" ( echo Annule. & pause & exit /b 0 )
echo.

:: ---- Arret Tor si actif ----
tasklist /FI "IMAGENAME eq tor.exe" 2>nul | find /I "tor.exe" >nul
if not errorlevel 1 (
    echo [INFO] Tor en cours d'execution, arret...
    taskkill /F /IM tor.exe >nul
    echo [OK] Tor arrete.
)

:: ---- Arret HexChat si actif ----
tasklist /FI "IMAGENAME eq hexchat.exe" 2>nul | find /I "hexchat.exe" >nul
if not errorlevel 1 (
    echo [INFO] HexChat en cours d'execution, arret...
    taskkill /F /IM hexchat.exe >nul
    echo [OK] HexChat arrete.
)

:: ---- Suppression Tor ----
set TORDIR=%~dp0tor
if exist "%TORDIR%" (
    rmdir /s /q "%TORDIR%"
    echo [OK] Dossier Tor supprime.
) else (
    echo [INFO] Dossier Tor deja absent.
)

:: ---- Suppression config HexChat (AppData) ----
set HXAPPDATA=%APPDATA%\HexChat
if exist "%HXAPPDATA%" (
    rmdir /s /q "%HXAPPDATA%"
    echo [OK] Config HexChat supprimee.
) else (
    echo [INFO] Config HexChat deja absente.
)

:: ---- Desinstallation HexChat ----
set "HXUNINST=%ProgramW6432%\HexChat"
if exist "%HXUNINST%\unins000.exe" (
    echo [INFO] Desinstallation HexChat...
    "%HXUNINST%\unins000.exe" /S
    rmdir /S /Q "%HXUNINST%"
    echo [OK] HexChat desinstalle.
) else (
    echo [INFO] Uninstaller HexChat non trouve (deja absent).
)

:: ---- Nettoyage cache ----
if exist "%TEMP%\tor-expert.zip" del /f /q "%TEMP%\tor-expert.zip" & echo [OK] Cache Tor supprime.
if exist "%TEMP%\HexChat-installer.exe" del /f /q "%TEMP%\HexChat-installer.exe" & echo [OK] Cache HexChat supprime.

echo.
echo [OK] Desinstallation terminee.
echo Vous pouvez supprimer le dossier IRC-Client manuellement.
pause
