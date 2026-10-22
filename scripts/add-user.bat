@echo off
rem ======================================================================
rem  Cree un compte sur l'interface web The Lounge.
rem
rem  Depuis que l'adresse .onion publie aussi l'interface web, la page de
rem  connexion est atteignable par quiconque connait l'adresse : le compte
rem  nominatif cree ici EST le controle d'acces. Un compte par personne,
rem  revocable individuellement (thelounge remove PSEUDO).
rem
rem  Le script pre-renseigne aussi le reseau IRC dans le compte : la
rem  personne n'a donc rien a saisir d'autre que son identifiant, elle
rem  arrive directement dans le salon.
rem
rem  Usage :
rem      scripts\add-user.bat                      pose les questions
rem      scripts\add-user.bat PSEUDO               mot de passe genere
rem      scripts\add-user.bat PSEUDO MOTDEPASSE    mot de passe impose
rem
rem  IRC_NO_PAUSE=1 supprime le "appuyez sur une touche" final : c'est ce
rem  que fait setup.bat quand il appelle ce script pour le premier compte.
rem ======================================================================
cd /d "%~dp0.." || (echo [ERREUR] Dossier du projet introuvable. & pause & exit /b 1)
setlocal enabledelayedexpansion
chcp 65001 >nul
title - Nouveau compte web -

docker info >nul 2>&1
if errorlevel 1 (
    echo [ERREUR] Docker n'est pas lance.
    pause
    exit /b 1
)

set "WCID="
for /f "usebackq delims=" %%I in (`docker compose ps -q webclient 2^>nul`) do set "WCID=%%I"
if "!WCID!"=="" (
    echo [ERREUR] Le conteneur webclient n'est pas demarre.
    echo          Lancez d'abord : docker compose up -d
    pause
    exit /b 1
)

rem ----------------------------------------------------------------------
rem  Pseudo. Il sert de nom de fichier (users\PSEUDO.json) et de pseudo
rem  IRC : on refuse tout ce qui n'est pas alphanumerique.
rem ----------------------------------------------------------------------
set "LUSER=%~1"
if "!LUSER!"=="" (
    echo === Nouveau compte pour l'interface web ===
    echo.
    set /p "LUSER=Pseudo : "
)
if "!LUSER!"=="" (
    echo [ERREUR] Pseudo vide.
    pause
    exit /b 1
)
rem " echo( " et non " echo  " : avec un pseudo valant exactement on, off
rem ou /?, " echo on " serait interprete comme la commande d'echo du shell,
rem findstr recevrait une entree vide et le script refuserait un pseudo
rem pourtant conforme a la regle qu'il affiche.
echo(!LUSER!| findstr /R /C:"^[A-Za-z][A-Za-z0-9_-]*$" >nul
if errorlevel 1 (
    echo [ERREUR] Pseudo invalide : lettres, chiffres, - et _ uniquement,
    echo          en commencant par une lettre.
    pause
    exit /b 1
)

docker compose exec -T webclient test -f "/var/opt/thelounge/users/!LUSER!.json" >nul 2>&1
if not errorlevel 1 (
    echo [ERREUR] Le compte '!LUSER!' existe deja.
    echo          Pour le supprimer : docker compose exec webclient thelounge remove !LUSER!
    pause
    exit /b 1
)

rem ----------------------------------------------------------------------
rem  Mot de passe. Genere par defaut : une valeur saisie ici traverserait
rem  la ligne de commande de docker compose, ou un & ou un ! se perdrait
rem  en silence. L'utilisateur pourra le changer dans The Lounge.
rem ----------------------------------------------------------------------
set "LPASS=%~2"
if "!LPASS!"=="" (
    for /f "usebackq delims=" %%P in (`powershell -NoProfile -ExecutionPolicy Bypass -File "tools\new-password.ps1" -Length 14`) do set "LPASS=%%P"
)
if "!LPASS!"=="" (
    echo [ERREUR] Generation du mot de passe impossible.
    pause
    exit /b 1
)

rem ----------------------------------------------------------------------
rem  Creation. --password rend la commande non interactive (sans elle,
rem  thelounge add attend une saisie masquee et bloque le script).
rem ----------------------------------------------------------------------
echo.
echo Creation du compte '!LUSER!'...
docker compose exec -T webclient thelounge add "!LUSER!" --password "!LPASS!" --save-logs

rem Le code retour de "thelounge add" vaut 0 meme quand il refuse de
rem creer le compte : on verifie le fichier, pas errorlevel.
docker compose exec -T webclient test -f "/var/opt/thelounge/users/!LUSER!.json" >nul 2>&1
if errorlevel 1 (
    echo [ERREUR] Le compte n'a pas ete cree.
    echo          Diagnostic : docker compose logs webclient
    pause
    exit /b 1
)
echo [OK] /var/opt/thelounge/users/!LUSER!.json

rem ----------------------------------------------------------------------
rem  Pre-remplissage du reseau IRC dans le compte.
rem ----------------------------------------------------------------------
for /f "usebackq delims=" %%V in (`powershell -NoProfile -ExecutionPolicy Bypass -File "tools\get-env.ps1" -Key IRC_NETWORK_NAME`) do set "NETNAME=%%V"
for /f "usebackq delims=" %%V in (`powershell -NoProfile -ExecutionPolicy Bypass -File "tools\get-env.ps1" -Key CONNECT_PASSWORD`) do set "CONNPW=%%V"
for /f "usebackq delims=" %%V in (`powershell -NoProfile -ExecutionPolicy Bypass -File "tools\get-env.ps1" -Key DEFAULT_CHANNEL`) do set "CHAN=%%V"
if "!NETNAME!"=="" set "NETNAME=IRC"
if "!CHAN!"=="" set "CHAN=#general"

rem Le script est donne a node par l'entree standard : l'image The Lounge
rem n'a pas de /tmp, et rien n'est ecrit dans le conteneur.
rem
rem Les -e sont ENTRE GUILLEMETS : un nom de reseau ou un topic contenant
rem une espace ("Mon Reseau") coupait sinon l'argument en deux, docker
rem prenait le second mot pour le nom du service, et le pre-remplissage
rem echouait avec "no such service".
docker compose exec -T -e "TL_USER=!LUSER!" -e "TL_NETWORK=!NETNAME!" -e "TL_PASSWORD=!CONNPW!" -e "TL_CHANNEL=!CHAN!" webclient node < "scripts\provision-network.js"
if errorlevel 1 (
    echo [ATTENTION] Le reseau n'a pas pu etre pre-renseigne.
    echo             Le compte fonctionne, mais l'utilisateur devra valider
    echo             le formulaire "Connect" une fois, deja pre-rempli.
)

rem The Lounge ne relit les reseaux d'un compte qu'au demarrage : sans ce
rem redemarrage, le pre-remplissage ne serait pris en compte qu'au prochain
rem "docker compose up". Le conteneur garde son IP, tor n'a rien a relire.
echo Redemarrage de l'interface web...
docker compose restart webclient >nul 2>&1

rem ----------------------------------------------------------------------
rem  Invitation personnelle.
rem ----------------------------------------------------------------------
echo.
set "INVITE_OK="
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\make-invite.ps1" -User "!LUSER!" -Password "!LPASS!" >nul 2>&1
if not errorlevel 1 set "INVITE_OK=1"

set "ONION="
for /f "usebackq delims=" %%A in (`docker compose exec -T tor cat /var/lib/tor/hidden_service/hostname 2^>nul`) do set "ONION=%%A"

echo.
echo ======================================================================
echo  Compte cree
echo ======================================================================
if "!ONION!"=="" (
    rem Le compte est bon, mais tor ne tourne pas : sans adresse, afficher
    rem "http:///" donnerait une invitation inutilisable sans le dire.
    echo  [ATTENTION] Adresse .onion indisponible : le conteneur tor n'est
    echo              pas demarre. Relancez setup.bat pour obtenir l'adresse
    echo              et l'invitation.
) else (
    echo  Adresse web  : http://!ONION!/        ^(dans Tor Browser^)
)
echo  Identifiant  : !LUSER!
echo  Mot de passe : !LPASS!
echo  Salon        : !CHAN!
echo.
if defined INVITE_OK (
    echo  A envoyer a la personne : invite-!LUSER!.txt
    echo  ^(contient aussi la consigne "niveau de securite Standard"^)
) else (
    echo  [ATTENTION] invite-!LUSER!.txt n'a pas pu etre genere.
    echo              Notez les identifiants ci-dessus, ils ne sont plus
    echo              affiches ensuite.
)
echo.
echo  Pour revoquer cet acces :
echo      docker compose exec webclient thelounge remove !LUSER!
echo ======================================================================
echo.
if not defined IRC_NO_PAUSE pause
