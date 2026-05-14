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

:: ---- Suppression config HexChat (AppData) ----
set HXAPPDATA=%APPDATA%\HexChat
if exist "%HXAPPDATA%" (
    rmdir /s /q "%HXAPPDATA%"
    echo [OK] Config HexChat supprimee.
) else (
    echo [INFO] Config HexChat deja absente.
)

:: ---- Desinstallation HexChat via winget ----
echo [INFO] Desinstallation de HexChat...
winget uninstall --id HexChat.HexChat --exact --silent --accept-source-agreements >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [OK] HexChat desinstalle via winget.
) else (
    :: Securite : Si winget echoue ou si installe manuellement avant
    set "HXUNINST=%ProgramW6432%\HexChat"
    if exist "!HXUNINST!\unins000.exe" (
        "!HXUNINST!\unins000.exe" /S
        rmdir /S /Q "!HXUNINST!" >nul 2>&1
        echo [OK] HexChat desinstalle manuellement.
    ) else (
        echo [INFO] HexChat non trouve ou deja desinstalle.
    )
)

echo.
echo [OK] Desinstallation terminee.
echo Vous pouvez supprimer le dossier IRC-Client manuellement.
pause