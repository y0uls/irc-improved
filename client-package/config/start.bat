@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul
echo === Lancement IRC sur Tor ===
echo.

set SCRIPTDIR=%~dp0
:: SCRIPTDIR se termine toujours par \, TOREXE est le chemin absolu direct
set TOREXE=%~dp0tor\tor\tor.exe

:: ---- HexChat ----
set HEXCHAT_EXE=%ProgramFiles%\HexChat\hexchat.exe
if not exist "%HEXCHAT_EXE%" set HEXCHAT_EXE=%LOCALAPPDATA%\HexChat\hexchat.exe
if not exist "%HEXCHAT_EXE%" (
    echo [INFO] HexChat absent. Telechargement...
    set HCINST=!TEMP!\HexChat-installer.exe
    powershell -Command "[Net.ServicePointManager]::SecurityProtocol='Tls12'; Import-Module BitsTransfer; Start-BitsTransfer -Source 'https://github.com/hexchat/hexchat/releases/download/v2.16.2/HexChat.2.16.2.x64.exe' -Destination '!HCINST!'"
    if not exist "!HCINST!" ( echo [ERREUR] Echec telechargement HexChat. & pause & exit /b 1 )
    powershell -Command "Start-Process '!HCINST!' -ArgumentList '/S' -Wait"
    set HEXCHAT_EXE=%ProgramFiles%\HexChat\hexchat.exe
    if not exist "!HEXCHAT_EXE!" set HEXCHAT_EXE=%LOCALAPPDATA%\HexChat\hexchat.exe
    if not exist "!HEXCHAT_EXE!" ( echo [ERREUR] HexChat introuvable apres installation. & pause & exit /b 1 )
    echo [OK] HexChat installe.
)
echo [OK] HexChat : %HEXCHAT_EXE%

:: ---- Config HexChat ----
set HXDEST=%APPDATA%\HexChat
if not exist "%HXDEST%" mkdir "%HXDEST%"
xcopy /E /Y /I "%SCRIPTDIR%HexChat\*" "%HXDEST%\" >nul
echo [OK] Config HexChat copiee.

:: ---- Tor ----
if not exist "!TOREXE!" (
    echo [INFO] Tor absent. Telechargement...
    set TORZIP=!TEMP!\tor-expert.tar.gz
    powershell -Command "[Net.ServicePointManager]::SecurityProtocol='Tls12'; Import-Module BitsTransfer; Start-BitsTransfer -Source 'https://archive.torproject.org/tor-package-archive/torbrowser/14.0.4/tor-expert-bundle-windows-x86_64-14.0.4.tar.gz' -Destination '!TORZIP!'"
    if not exist "!TORZIP!" ( echo [ERREUR] Echec telechargement Tor. & pause & exit /b 1 )
    set TORROOT=%~dp0tor
    if not exist "!TORROOT!" mkdir "!TORROOT!"
    echo [INFO] Extraction Tor...
    tar -xzf "!TORZIP!" -C "!TORROOT!"
    :: Chercher tor.exe dans les sous-dossiers du bundle
    set TOREXE=
    for /r "!TORROOT!" %%F in (tor.exe) do set TOREXE=%%F
    if "!TOREXE!"=="" ( echo [ERREUR] tor.exe introuvable apres extraction. & pause & exit /b 1 )
    echo [OK] Tor installe : !TOREXE!
)
:: Toujours forcer le chemin canonique apres installation
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
