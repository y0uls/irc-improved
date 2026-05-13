@echo off
set /p name=Username : 
docker exec -it irc-webclient thelounge add %name%
pause