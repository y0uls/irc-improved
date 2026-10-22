@echo off
rem ---------------------------------------------------------------------------
rem  Client IRC prive -- point d'entree (double-clic).
rem
rem  Ce fichier ne fait que lancer start.ps1, qui contient toute la logique.
rem  Volontairement : la version precedente melangeait cmd et powershell, et
rem  c'est la que se trouvaient les bugs (interpolation de valeurs dans une
rem  ligne de commande, un process powershell.exe complet lance par seconde
rem  dans la boucle d'attente, attente infinie).
rem ---------------------------------------------------------------------------

cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start.ps1"
set RC=%ERRORLEVEL%

if not "%RC%"=="0" (
    echo.
    echo [XX] Le lancement a echoue -- le message au-dessus dit pourquoi.
    echo.
    echo      Si rien ne s'est affiche du tout, PowerShell est bloque sur cette
    echo      machine. Ouvre un PowerShell et lance :
    echo         powershell -ExecutionPolicy Bypass -File "%~dp0start.ps1"
    echo.
    pause
)

exit /b %RC%
