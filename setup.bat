@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

echo === Setup du serveur IRC ===
echo.

docker info >nul 2>&1
if errorlevel 1 (
    echo [ERREUR] Docker n'est pas lance ou n'est pas installe.
    echo          Lancez Docker Desktop puis reessayez.
    pause
    exit /b 1
)

if not exist ".env" (
    copy ".env.example" ".env" >nul
    echo [OK] Fichier .env cree.
    echo.
    echo  Editez le fichier .env avec vos valeurs avant de continuer.
    echo  Exemple : notepad .env
    echo.
    pause
    exit /b 0
)

:: IRC_NETWORK_NAME
findstr /C:"MonReseau" .env >nul
if not errorlevel 1 (
    echo [ATTENTION] IRC_NETWORK_NAME est toujours "MonReseau".
    echo.
    set /p IRC_NETWORK="Nom de mon network IRC : "
    echo.
    powershell -Command "(Get-Content '.env') -replace 'IRC_NETWORK_NAME=.*', 'IRC_NETWORK_NAME=!IRC_NETWORK!' | Set-Content '.env'"
    echo [OK] Network name enregistre.
    echo.
)

:: Hash mot de passe oper
findstr /C:"CHANGEME" .env >nul
if not errorlevel 1 (
    echo [ATTENTION] OPER_PASSWORD_HASH est toujours "CHANGEME".
    echo.
    set /p OPER_PASS="Mot de passe oper (pour /OPER admin) : "
    echo.
    echo Generation du hash...
    for /f "tokens=*" %%H in ('docker run --rm inspircd/inspircd-docker:latest /inspircd/bin/inspircd --mkpasswd hmac-sha256 "!OPER_PASS!" 2^>nul ^| findstr /C:"Password:"') do set HASH_LINE=%%H
    set HASH=!HASH_LINE:*Password: =!
    if "!HASH!"=="" (
        echo [ERREUR] Impossible de generer le hash.
        pause
        exit /b 1
    )
    powershell -Command "(Get-Content '.env') -replace 'OPER_PASSWORD_HASH=.*', 'OPER_PASSWORD_HASH=!HASH!' | Set-Content '.env'"
    echo [OK] Hash oper enregistre.
    echo.
)

:: Mot de passe de connexion
findstr /C:"CONNECT_PASSWORD=" .env | findstr /V /C:"CONNECT_PASSWORD=." >nul 2>&1
if not errorlevel 1 (
    echo.
    set /p CONN_PASS="Mot de passe pour rejoindre le serveur IRC (Entree = aucun) : "
    powershell -Command "(Get-Content '.env') -replace '^CONNECT_PASSWORD=.*', 'CONNECT_PASSWORD=!CONN_PASS!' | Set-Content '.env'"
    if "!CONN_PASS!"=="" (
        echo [INFO] Aucun mot de passe de connexion.
    ) else (
        echo [OK] Mot de passe de connexion enregistre.
    )
    echo.
)

:: Channel par défaut
findstr /C:"DEFAULT_CHANNEL=#general" .env >nul
if not errorlevel 1 (
    echo.
    set /p CHAN="Channel par defaut [#general] : "
    if "!CHAN!"=="" set CHAN=#general
    if "!CHAN:~0,1!" neq "#" set CHAN=#!CHAN!
    powershell -Command "(Get-Content '.env') -replace 'DEFAULT_CHANNEL=.*', 'DEFAULT_CHANNEL=!CHAN!' | Set-Content '.env'"

    set /p TOPIC="Topic du channel !CHAN! : "
    if "!TOPIC!"=="" set TOPIC=Bienvenue sur le serveur IRC !
    powershell -Command "(Get-Content '.env') -replace 'DEFAULT_TOPIC=.*', 'DEFAULT_TOPIC=!TOPIC!' | Set-Content '.env'"
    echo [OK] Channel !CHAN! configure.
    echo.
)

echo === Build des images Docker ===
docker compose build
if errorlevel 1 (
    echo [ERREUR] Le build a echoue.
    pause
    exit /b 1
)

echo.
echo === Demarrage des services ===
docker compose up -d
if errorlevel 1 (
    echo [ERREUR] Le demarrage a echoue.
    pause
    exit /b 1
)

echo.
echo === Attente du demarrage de Tor (30s) ===
timeout /t 30 /nobreak >nul

echo.
echo === Adresse .onion ===
docker compose exec tor cat /var/lib/tor/hidden_service/hostname 2>nul
if errorlevel 1 (
    echo [INFO] Tor demarre encore :
    echo        docker compose exec tor cat /var/lib/tor/hidden_service/hostname
)

echo.
echo === Compte The Lounge (interface web) ===
echo Il faut creer au moins un compte pour acceder a l'interface web.
echo.
set /p LOUNGE_USER="Pseudo pour The Lounge : "
if "!LOUNGE_USER!"=="" (
    echo [ATTENTION] Creez un compte plus tard :
    echo             docker compose exec webclient thelounge add PSEUDO
) else (
    docker compose exec -it webclient thelounge add !LOUNGE_USER!
    echo [OK] Compte '!LOUNGE_USER!' cree.
)

for /f "tokens=2 delims==" %%P in ('findstr "WEBCLIENT_PORT" .env') do set WCPORT=%%P
if "!WCPORT!"=="" set WCPORT=8080

echo.
echo [OK] Serveur IRC demarre !
echo      Interface web : http://localhost:!WCPORT!
echo      Logs IRC      : docker compose logs -f irc
echo      Logs Tor      : docker compose logs -f tor
echo.
pause
