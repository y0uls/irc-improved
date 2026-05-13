@echo off
set /p name=Username : 
docker exec -it irc-webclient thelounge remove %name%
pause