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
set CONN_PASS=
for /f "tokens=2 delims==" %%P in ('findstr /i "^CONNECT_PASSWORD=" "%~dp0..\.env"') do set CONN_PASS=%%P

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

:: servlist.conf â€” reseau pre-configure
(
echo [Networks]
echo n0=!ONION!\p0
echo [Network !ONION!]
echo N=!NAMESERV!
echo E=UTF-8 ^(Unicode^)
echo F=19
echo S=!ONION!/6667
echo P=!CONN_PASS!
echo J=!CHAN!
echo B=
) > "!OUTDIR!\HexChat\servlist.conf"

:: hexchat.conf â€” proxy SOCKS5 vers proxytor
(
echo net_proxy_host = 127.0.0.1
echo net_proxy_port = 9050
echo net_proxy_type = 3
echo net_proxy_auth = 0
) > "!OUTDIR!\HexChat\hexchat.conf"

:: README utilisateur
(
echo # Connexion au serveur IRC
echo.
echo ## Pre-requis
echo.
echo Le serveur doit etre demarre sur la machine hote ^(docker compose up -d^).
echo Le proxy Tor est accessible sur 127.0.0.1:9050.
echo.
echo ## Installation
echo.
echo 1. Telecharge et installe HexChat : https://hexchat.github.io
echo 2. Copie le dossier HexChat\ dans %%APPDATA%%\
echo    ^(Chemin complet : C:\Users\TON_NOM\AppData\Roaming\HexChat\^)
echo 3. Lance HexChat
echo 4. Le reseau "MonServeurIRC" apparait deja configure
echo 5. Connecte-toi !
echo.
echo ## Adresse du serveur
echo.
echo !ONION!:6667
) > "!OUTDIR!\README.txt"

:: Zipper le tout
set ZIPNAME=%~dp0HexChat-IRC-Client.zip
if exist "!ZIPNAME!" del /f /q "!ZIPNAME!"
powershell -Command "Compress-Archive -Path '!OUTDIR!\*' -DestinationPath '!ZIPNAME!'"

if exist "!ZIPNAME!" (
    echo.
    echo [OK] Package genere : client-package\HexChat-IRC-Client.zip
    echo      Distribue ce zip a tes utilisateurs.
    echo      Ils extraient le dossier HexChat dans %%APPDATA%% et lancent HexChat.
) else (
    echo [ERREUR] La creation du zip a echoue.
)
echo.
pause