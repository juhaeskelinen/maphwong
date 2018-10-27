@ECHO OFF
SETLOCAL

SET MA_PORT=52150
SET PH_PORT=52940
SET NG_PORT=52380
SET PH_ADMIN_PORT=52280
REM You can set NG_PORT to 80 if that port is free

SET MA_VERSION=10.3.9
SET WO_VERSION=4.9.8
SET NG_VERSION=1.14.0
SET PH_VERSION=7.2.9


SET PsScript=%~dp0%tools\start.ps1
REM echo %PsScript%
%SYSTEMROOT%\System32\WindowsPowerShell\v1.0\PowerShell -NoProfile -ExecutionPolicy Bypass -Command "& '%PsScript%'";
REM PAUSE P >nul 