@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul
echo === Lancement IRC sur Tor ===
echo.

set SCRIPTDIR=%~dp0

:: ---- HexChat ----
set HEXCHAT_EXE=%ProgramFiles%\HexChat\hexchat.exe
if not exist "%HEXCHAT_EXE%" set HEXCHAT_EXE=%LOCALAPPDATA%\HexChat\hexchat.exe

if not exist "%HEXCHAT_EXE%" (
    echo [INFO] HexChat absent. Installation via winget en cours...
    
    :: Installation silencieuse via winget avec acceptation auto des licences
    winget install --id HexChat.HexChat --exact --silent --accept-package-agreements --accept-source-agreements
    
    :: Re-verification du chemin apres installation
    set HEXCHAT_EXE=%ProgramFiles%\HexChat\hexchat.exe
    if not exist "!HEXCHAT_EXE!" set HEXCHAT_EXE=%LOCALAPPDATA%\HexChat\hexchat.exe
    
    if not exist "!HEXCHAT_EXE!" ( 
        echo [ERREUR] HexChat introuvable apres installation. 
        pause 
        exit /b 1 
    )
    echo [OK] HexChat installe avec succes.
)
echo [OK] HexChat : %HEXCHAT_EXE%

:: ---- Config HexChat ----
set HXDEST=%APPDATA%\HexChat
if not exist "%HXDEST%" mkdir "%HXDEST%"
xcopy /E /Y /I "%SCRIPTDIR%HexChat\*" "%HXDEST%\" >nul
echo [OK] Config HexChat copiee.

:: ---- Config Tor ----
set TOREXE=%~dp0tor\tor\tor.exe
echo [OK] Tor : %~dp0tor\tor\tor.exe

:: ---- Lancement Tor ----
echo [INFO] Demarrage de Tor...
start "" /B "%~dp0tor\tor\tor.exe"

:: ---- Attente SOCKS5 9050 ----
echo [INFO] Attente proxy SOCKS5 sur 127.0.0.1:9050...
:waittor
powershell -Command "try{$t=New-Object Net.Sockets.TcpClient;$t.Connect('127.0.0.1',9050);$t.Close();exit 0}catch{exit 1}" >nul
if errorlevel 1 ( timeout /t 1 /nobreak >nul & goto :waittor )
echo [OK] Proxy Tor pret.

:: ---- Lancement HexChat ----
echo [OK] Lancement de HexChat...
echo.
start "" /WAIT "%HEXCHAT_EXE%"

:: ---- Arret Tor ----
echo.
echo [INFO] HexChat ferme. Arret de Tor...
taskkill /F /IM tor.exe >nul
echo [OK] Tor arrete.
exit /b 0
