REM @ECHO OFF
REM
SET _instance=0
SET /A MA_PORT=52150 + %_instance%
SET /A PH_PORT=52940 + %_instance%
SET /A NG_PORT=52380 + %_instance% & REM You can set NG_PORT to the default value of 80 if that is free
SET /A ADMIN_PORT=52280 + %_instance%

REM
SETLOCAL
REM
SET MA_VER=10.3.9
SET WO_VER=4.9.8
SET NG_VER=1.14.0
SET PH_VER=7.2.10
REM
SET WORKDIR=%CD%
SET sed=tools\sed\bin\sed.exe
SET unzip=tools\7za\7za.exe x
SET curl=tools\curl\bin\curl.exe
SET ipinfo=%curl% -s https://ipinfo.io/loc
REM curl headers for an interactive browser lookalike
SET CURL_HDR=-H "User-Agent: Mozilla/5.0 (Windows 10.0) Version/1.0" -H "Upgrade-Insecure-Requests: 1"
SET CURL_HDR=%CURL_HDR% -H "Accept: */*" -H "Accept-Encoding: gzip, deflate"
REM
REM mariaDB setup
IF EXIST mariadb\bin\mysql.exe GOTO MA_UNZIP_OK
SET MA_ZIP=mariadb/mariadb-%MA_VER%/winx64-packages/mariadb-%MA_VER%-winx64.zip
REM mariaDB download
FOR /F "tokens=3 delims=,." %%G IN ('%ipinfo%') DO (SET longitude=%%G)
IF NOT DEFINED longitude (SET longitude=116)
SET MA_URL=http://nyc2.mirrors.digitalocean.com/%MA_ZIP%
IF %longitude% GEQ -30 SET MA_URL=http://ams2.mirrors.digitalocean.com/%MA_ZIP%
IF %longitude% GEQ 60 SET MA_URL=http://sgp1.mirrors.digitalocean.com/%MA_ZIP%
ECHO Downloading %MA_URL%
%curl% "%MA_URL%" %CURL_HDR% --output ma.zip
IF NOT EXIST ma.zip ECHO MariaDB download error & GOTO END 
%unzip% ma.zip
DEL /F /Q ma.zip
RENAME mariadb-%MA_VER%-winx64 mariadb
IF NOT EXIST mariadb\bin\mysql.exe ECHO MariaDB unzip error & GOTO END
:MA_UNZIP_OK
REM mariaDB data directory
IF NOT EXIST mariadb-data MOVE mariadb\data mariadb-data
IF NOT EXIST mariadb-data\mysql ECHO MariaDB data error & GOTO END
REM mariadb ini-file
IF NOT EXIST mariadb\my.ini COPY tools\conf\ma.conf mariadb\my.ini
REM mariaDB port
FINDSTR "port.*%MA_PORT%" mariadb\my.ini
IF %ERRORLEVEL% EQU 0 GOTO MA_PORT_OK
COPY mariadb\my.ini tmp.tmp
%sed% -e "s/port.*/port = %MA_PORT%/" -e "s/socket.*/socket = mydb%MA_PORT%/" tmp.tmp > mariadb\my.ini
DEL /F /Q tmp.tmp
FINDSTR "port.*%MA_PORT%" mariadb\my.inis
IF %ERRORLEVEL% NEQ 0 ECHO MariaDB port error & GOTO END
:MA_PORT_OK
REM mariadb start
START /B mariadb\bin\mysqld --defaults-file=%WORKDIR%\mariadb\my.ini
mariadb\bin\mysql --user=root --password= -e "SHOW DATABASES;" | findstr /C:"wordpress"
IF %ERRORLEVEL% NEQ 0 mariadb\bin\mysql --user=root --password= -e "CREATE DATABASE wordpress; GRANT ALL PRIVILEGES ON wordpress.* TO ""wordpress""@""localhost"" IDENTIFIED BY ""s3cr3t""; FLUSH PRIVILEGES;"
REM adjust port of wordpress URL
mariadb\bin\mysql --user=root --password= -e "GRANT ALL PRIVILEGES ON wordpress.* TO ""wordpress""@""localhost"" IDENTIFIED BY ""s3cr3t""; FLUSH PRIVILEGES;"
mariadb\bin\mysql --user=root --password= -e "UPDATE wordpress.wp_options SET option_value='http://localhost:%NG_PORT%' WHERE option_name='siteurl' OR option_name='home';"
REM update wordpress.wp_options SET db_version='%MA_PORT%', initial_db_version='%MA_PORT%'
REM
REM wordpress setup
IF EXIST wordpress\wp-login.php GOTO WO_UNZIP_OK
SET WO_URL=https://wordpress.org/wordpress-%WO_VER%.zip
ECHO Downloading %WO_URL%
%curl% "%WO_URL%" %CURL_HDR% --output wo.zip
IF NOT EXIST wo.zip ECHO Wordpress download error & goto END 
:WO_DOWNLOAD_OK
REM Wordpress unzip
%unzip% wo.zip
DEL /F /Q wo.zip
IF NOT EXIST wordpress\wp-login.php ECHO Wordpress unzip error & goto END
:WO_UNZIP_OK
REM Wordpress setup
IF EXIST wordpress\wp-config-sample.php DEL wordpress\wp-config-sample.php
IF NOT EXIST wordpress\wp-config.php COPY tools\conf\wo.conf wordpress\wp-config.php
FINDSTR "DB_HOST.*localhost:%MA_PORT%" wordpress\wp-config.php >NUL 2>&1
IF %ERRORLEVEL% EQU 0 GOTO WO_CONF_OK
COPY wordpress\wp-config.php tmp.tmp
%sed% -e "s/DB_HOST.*/DB_HOST', 'localhost:%MA_PORT%');/" tmp.tmp > wordpress\wp-config.php 
DEL /F /Q tmp.tmp
:WO_CONF_OK
REM
REM PHP setup
IF EXIST php\php.exe GOTO PH_UNZIP_OK
SET PH_URL=https://windows.php.net/downloads/releases/php-%PH_VER%-Win32-VC15-x64.zip
ECHO Downloading %PH_URL%
%curl% "%PH_URL%" %CURL_HDR% --output ph.zip
IF NOT EXIST ph.zip ECHO PHP download error & goto END 
%unzip% -ophp ph.zip & DEL /F /Q ph.zip
IF NOT EXIST php\php.exe ECHO PHP unzip error & goto END
:PH_UNZIP_OK
REM php.ini setup
IF NOT EXIST php\php.ini COPY tools\conf\ph.conf php\php.ini
REM nginx setup
IF EXIST nginx\nginx.exe GOTO NG_UNZIP_OK
SET NG_URL=http://nginx.org/download/nginx-%NG_VER%.zip
ECHO Downloading %NG_URL%
%curl% "%NG_URL%" %CURL_HDR% --output ng.zip
IF NOT EXIST ng.zip ECHO Nginx download error & goto END 
:NG_DOWNLOAD_OK
REM Nginx unzip
%unzip% ng.zip & DEL /F /Q ng.zip
MOVE nginx-* nginx
IF NOT EXIST nginx\nginx.exe ECHO Nginx unzip error & goto END
DEL nginx\conf\nginx.conf
MOVE nginx\html nginx\html-orig
COPY tools\conf\ng.conf nginx\conf\nginx.conf
:NG_UNZIP_OK
REM Set nginx HTTP port and PHP port in nginx.conf 
(FINDSTR "listen.*%NG_PORT%" nginx\conf\nginx.conf >NUL 2>&1) && (FINDSTR "fastcgi_pass.*%PH_PORT%" nginx\conf\nginx.conf >NUL 2>&1)
IF %ERRORLEVEL% EQU 0 GOTO NG_PORTS_OK
COPY nginx\conf\nginx.conf tmp.tmp
%sed% -e "s/listen.*/listen %NG_PORT%;/" -e "s/fastcgi_pass.*/fastcgi_pass localhost:%PH_PORT%/" tmp.tmp > nginx\conf\nginx.conf
DEL /F /Q tmp.tmp
:NG_PORTS_OK
REM Hard link wordpress folder as nginx documents folder
FINDSTR "WordPress" nginx\wordpress\index.php >NUL 2>&1
IF %ERRORLEVEL% EQU 0 GOTO NG_LINK_OK
RMDIR /Q nginx\wordpress
MKLINK /J nginx\wordpress wordpress
:NG_LINK_OK
REM
REM Hard link phpmyadmin into wordpress http://localhost:port/phpmyadmin
REM edit conf.inc a) rename template b) edit port and free password 
REM mklink /j wordpress\phpmyadmin tools\phpMyAdmin-4.8.3-english
REM
SET PATH=%WORKDIR%\php;%PATH%
CD %WORKDIR%\php
START /B php-cgi.exe -b localhost:%PH_PORT%
CD %WORKDIR%\nginx
START /B nginx.exe
CD %WORKDIR%
tasklist /fi "imagename eq php-cgi.exe"
tasklist /fi "imagename eq nginx.exe"
tasklist /fi "imagename eq mysqld.exe"
REM Taskkill /PID 26356 /F
ECHO Start HTTP at port %ng_PORT% ...
REM Route to 0.0.0.0 contains the physical interface for accessing local machine
REM If there are multiple interfaces this magic spell prints all of them
REM (This riducculus spell may look like it puts a curse on your machine, but it is actually quite friendly )
REM Note: for extended testing in firewall limited environments use ngrok.com tunneling service
ECHO Host 127.0.0.1 (localhost)
ROUTE print 0.0.0.0 | findstr /c:"0.0.0.0" | tools\sed\bin\sed.exe -e "s/\([ ]*[0-9.]*\)\{4\}.*/Host \1/g" -e "s/[ ][ ]*/ /g"
START /b CMD /c start http://localhost:%NG_PORT%
PAUSE _P
:END