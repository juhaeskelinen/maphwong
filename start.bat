@ECHO OFF
SET PsScript=%~dp0%tools\start.ps1
%SYSTEMROOT%\System32\WindowsPowerShell\v1.0\PowerShell -NoProfile -ExecutionPolicy Bypass -Command "& '%PsScript%'";