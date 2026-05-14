@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

echo === Generation du package client HexChat ===
echo.

:: Recuperer l'adresse .onion
for /f "tokens=*" %%A in ('docker compose exec tor cat /var/lib/tor/hidden_service/hostname 2^>nul') do set ONION=%%A
if "!ONION!"=="" (
    echo [ERREUR] Impossible de recuperer l'adresse .onion.
    echo          Verifiez que les containers sont demarres.
    pause
    exit /b 1
)
echo [OK] Adresse .onion : !ONION!

:: Le .env est a la racine du projet (un niveau au-dessus de client-package\)
set ENVFILE=%~dp0..\env

:: Recuperer le mot de passe de connexion
:: Lire CONNECT_PASSWORD sans delayed expansion pour preserver les ! dans le mot de passe
setlocal disabledelayedexpansion
set CONN_PASS=
for /f "tokens=2 delims==" %%P in ('findstr /i "^CONNECT_PASSWORD=" "%~dp0..\.env"') do set CONN_PASS=%%P
endlocal & set CONN_PASS=%CONN_PASS%

:: Recuperer le channel par defaut
set CHAN=#general
for /f "tokens=2 delims==" %%C in ('findstr /i "^DEFAULT_CHANNEL=" "%~dp0..\.env"') do set CHAN=%%C

:: Recuperer le channel par defaut
set NAMESERV=MonServeurIRC
for /f "tokens=2 delims==" %%D in ('findstr /i "^IRC_NETWORK_NAME=" "%~dp0..\.env"') do set NAMESERV=%%D

echo [OK] Channel : !CHAN!
if "!CONN_PASS!"=="" (
    echo [INFO] Pas de mot de passe de connexion.
) else (
    echo [OK] Mot de passe de connexion detecte.
)

:: Creer le dossier de config HexChat
set OUTDIR=%~dp0HexChat-config
if exist "!OUTDIR!" rmdir /s /q "!OUTDIR!"
mkdir "!OUTDIR!\HexChat"

:: servlist.conf - copie depuis template + substitution des placeholders
copy /Y "%~dp0\config\servlist.conf" "!OUTDIR!\HexChat\servlist.conf" >nul
powershell -Command "$f='!OUTDIR!\HexChat\servlist.conf'; (Get-Content $f).Replace('__ONION__','!ONION!').Replace('__NAMESERV__','!NAMESERV!').Replace('__CONN_PASS__','!CONN_PASS!').Replace('__CHAN__','!CHAN!') | Set-Content $f"

:: hexchat.conf - copie depuis config statique
copy /Y "%~dp0\config\hexchat.conf" "!OUTDIR!\HexChat\hexchat.conf" >nul

:: README utilisateur
(
echo # Connexion au serveur IRC
echo.
echo ## Installation
echo.
echo 1. Executer "start.bat"
echo 2. Une fois l'installation de HexChat finie, ne pas l'executer tout de suite, laisser le script le faire.
echo 3. Connecte-toi !
echo.
echo ## Adresse du serveur
echo.
echo !ONION!:6667
) > "!OUTDIR!\README.txt"

:: Copier start.bat statique dans le package
copy /Y "%~dp0\config\start.bat" "!OUTDIR!\start.bat" >nul
if not exist "!OUTDIR!\start.bat" (
    echo [ERREUR] start.bat introuvable a cote de build-client.bat
    pause
    exit /b 1
)
echo [OK] start.bat inclus.


:: Copier uninstall.bat statique dans le package
copy /Y "%~dp0\config\uninstall.bat" "!OUTDIR!\uninstall.bat" >nul
if not exist "!OUTDIR!\uninstall.bat" (
    echo [ERREUR] uninstall.bat introuvable a cote de build-client.bat
    pause
    exit /b 1
)
echo [OK] uninstall.bat inclus.


:: Zipper le tout
set ZIPNAME=%~dp0IRC-Client.zip
if exist "!ZIPNAME!" del /f /q "!ZIPNAME!"
powershell -Command "Compress-Archive -Path '!OUTDIR!\*' -DestinationPath '!ZIPNAME!'"

if exist "!ZIPNAME!" (
    echo.
    echo [OK] Package genere : client-package\IRC-Client.zip
    echo      Distribue ce zip a tes utilisateurs.
    echo      Ils extraient le dossier HexChat dans %%APPDATA%% et lancent HexChat.
) else (
    echo [ERREUR] La creation du zip a echoue.
)
rmdir /S /Q "%~dp0\HexChat-config"
echo.
pause