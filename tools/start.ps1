<#
.SYNOPSIS
MaphWong setups WordPress localhost development environment in Windows 10 PC.
It downloads, configures, and starts MariaDB, PHP, and Nginx with fastcgi and WordPress in document root directory

.DESCRIPTION
This script downloads, configures, and starts MariaDB, PHP, and Nginx with WordPress in document root directory.
This PowerShell script is invoked by the associated "start.bat" Windows command -script which contains the
  configurable port numbers and component versions. Those are visible here in the "$env" -variable
  (MA_PORT, PH_PORT, NG_PORT, MA_VERSION, PH_VERSION, WO_VERSION, NG_VERSION )
$MyInvocation.MyCommand.Name contains the name of this script-file for verification of the setup.
Main -function contains the logic-flow. It will be invoked after all other functions have been parsed
  (at the end of this file).

.EXAMPLE
start.bat

.NOTES
Written by: Juha Eskelinen, https://juhaeskelinen.com
#>

<#
Start-Process 
Stop-Process -Name Idle
Invoke-Command
https://www.microsoftpressstore.com/articles/article.aspx?p=2449030
#>

#
# Main -function : logic-flow
# This will be invoked after all other functions have been parsed (at the end of this file)
#
function Main
{
    param( [string]$ScriptName )

    # Set current working directory to MaphWong folder
    Split-Path -Path $PsScriptRoot -Parent | Set-Location
    # Verify script location
    if (!(Test-Path -Path "tools\$ScriptName")) { throw "Running in wrong directory" }
    # Verify $env. All is well if NG_PORT is defined
    # if !NG_PORT Write-Host "Use the start.bat -file to launch this PowerShell -script"
    # Download components
    Get-MariaDb -MaVersion $env:MA_VERSION
    Get-Php -PhVersion $env:PH_VERSION
    Get-WordPress -WoVersion $env:WO_VERSION
    Get-Nginx -NgVersion $env:NG_VERSION
    # Configure components
    Set-MariaDb -MaPort $env:MA_PORT
    Set-Php
    Set-WordPress -MaPort $env:MA_PORT
    Set-Nginx -NgPort $env:NG_PORT -PhPort $env:PH_PORT
    # Start components
    Start-MariaDb -MaPort $env:MA_PORT 
    Start-Php -PhPort $env:PH_PORT
    Start-Nginx -NgPort $env:NG_PORT
    Start-Wordpress -MaPort $env:MA_PORT -PhPort $env:PH_PORT -NgPort $env:NG_PORT
}

function Assert-Path
{
    param( [string]$Path, [string]$Pattern, [string]$Error )
    if (!(Test-Path -Path $Path))
    {
        throw $Error
    }
    if ($Pattern)
    {
        if (!(Select-String -Path $Path -Pattern $Pattern))
        {
            throw $Error
        }
    }
}

function Get-GeoLocation
{
    return Invoke-RestMethod -URI "https://ipinfo.io/loc"
}

function Get-WebFile
{
    param( [string]$Displayname, [string]$Url, [string]$OutFile )
    # Write-Host "Get-WebFile $Url $OutFile"

    Import-Module BitsTransfer
    $null = Start-BitsTransfer -Source $url -Destination $OutFile `
     -Displayname "Downloading $Displayname    (in case of emergency break process with Ctrl-C)" `
     -Description "from $Url "
}

#
# MariaDB
#
function Get-MariaDb
{
    param( [string]$MaVersion )
    Write-Host "Verifying MariaDB"

    if (Test-Path -Path "mariadb\bin\mysql.exe")
    {
        return "  MariaDB already downloaded"
    }
    
    Write-Host "  Downloading MariaDB from closest DigitalOcean mirror"
    $MariaDbZip = "mariadb/mariadb-" + $MaVersion + "/winx64-packages/mariadb-" + $MaVersion + "-winx64.zip"
    $GeoLocation = Get-GeoLocation # return format 61.4354,23.8622
    $longitude = [int]$GeoLocation.Split(",.")[2]
    if (!$longitude) { $longitude = 116 }
    if ($longitude -ge 60) { $MariaDbMirror = "http://sgp1.mirrors.digitalocean.com/" } # Asia, Australia
    elseif ($longitude -ge -30) { $MariaDbMirror = "http://ams2.mirrors.digitalocean.com/" } # Europe, Africa
    else { $MariaDbMirror = "http://nyc2.mirrors.digitalocean.com/" } # Americas
    $MariaDbUrl = $MariaDbMirror + $MariaDbZip
    Get-WebFile -Displayname "MariaDB" -Url $MariaDbUrl -OutFile "ma.zip"
    Assert-Path -Path "ma.zip" -Error "MariaDB download failed"

    Write-Host "  Expanding downloaded MariaDB zip-archive"
    Expand-Archive -Path "ma.zip" -DestinationPath "ma-dir"
    Move-Item -Path "ma-dir\mariadb*" -Destination "mariadb"
    Assert-Path -Path "mariadb\bin\mysql.exe" -Error "MariaDB unzip failed"
    Remove-Item -Path "ma-dir"
    Remove-Item -Path "ma.zip"

    return "MariaDB downloaded"
}

function Set-MariaDb
{
    param( [int]$MaPort )
    Write-Host "Verifying MariaDB configuration"
    # tests: $Port++; # Remove-Item -Path "mariadb\my.ini" -Verbose

    $thisDir = Get-Location

    if ((Test-Path -Path "mariadb\my.ini") -and `
        (Select-String -Path "mariadb\my.ini" -Pattern "port.*$MaPort") -and `
        (Select-String -Path "mariadb\my.ini" -SimpleMatch -Pattern "$thisDir\mariadb-data") -and `
        (Test-Path -Path "mariadb-data\mysql"))
    {
        return "  MariaDB already configured"
    }

    if (!(Test-Path -Path "mariadb\my.ini"))
    {
        Copy-Item -Path "tools\_ma.conf" -Destination "mariadb\my.ini"
    }

    if (!((Select-String -Path "mariadb\my.ini" -Pattern "port.*$MaPort") -and `
          (Select-String -Path "mariadb\my.ini" -SimpleMatch -Pattern "$thisDir\mariadb-data")))
    {
        (Get-Content -Path "mariadb\my.ini") | ForEach-Object {
            $_ -Replace "port.*", "port = $MaPort" -Replace "socket.*", "socket = mydb$MaPort" `
            -Replace "datadir.*", "datadir = $thisDir\mariadb-data"
        } | Set-Content -Path "mariadb\my.ini"
    }

    if (!(Test-Path -Path "mariadb-data"))
    {
        Write-Host "  Moving MariaDB data to mariadb-data -folder so that it will not get over-written"
        Move-Item -Path "mariadb\data" -Destination "mariadb-data"
    }
    Assert-Path -Path "mariadb-data\mysql" -Error "MariaDB mariadb-data folder incomplete"

    return "  MariaDB configured"
}

function Start-MariaDb
{
    param( [int]$MaPort, [int]$NgPort )
    Write-Host "Starting MariaDB"

    $proc = Get-WmiObject Win32_Process -Filter "Name='mysqld.exe' and CommandLine LIKE '%port $MaPort%'"
    if (!$proc)
    {
        Push-Location "mariadb"
        $p = CMD.EXE /C "START /B bin\mysqld --defaults-file=my.ini --port $MaPort 2>&1"
        Write-Host "  Starting MariaDB on port $MaPort;"
        Pop-Location
    }
    else {
        $id = $proc.ProcessId
        Write-Host "  MariaDB already running on port $MaPort as process $id"
    }
}

#
# PHP
#

function Get-Php
{
    param( [string]$PhVersion )
    Write-Host "Verifying PHP"

    if (Test-Path -Path "php\php.exe")
    {
        return "  PHP already downloaded"
    }
    
    Write-Host "  Downloading PHP from windows.php.net"
    $PhpUrl = "https://windows.php.net/downloads/releases/archives/php-$PhVersion-Win32-VC15-x64.zip"
    Get-WebFile -Displayname "PHP" -Url $PhpUrl -OutFile "ph.zip"
    Assert-Path -Path "ph.zip" -Error "PHP download failed"

    Write-Host "  Expanding downloaded PHP zip-archive"
    Expand-Archive -Path "ph.zip" -DestinationPath "ph-dir"
    Move-Item -Path "ph-dir" -Destination "php"
    Assert-Path -Path "php\php.exe" -Error "PHP unzip failed"
    # Remove-Item -Path "ph-dir"
    Remove-Item -Path "ph.zip"

    return "  PHP downloaded"
}

function Set-Php
{
    Write-Host "Verifying PHP configuration"
    # tests: # Remove-Item -Path "php\php.ini" -Verbose
    
    if (Test-Path -Path "php\php.ini")
    {
        return "  PHP already configured"
    }
    
    Copy-Item -Path "tools\_ph.conf" -Destination "php\php.ini"
    
    return "  PHP configured"
}

function Start-Php
{
    param( [int]$PhPort )
    Write-Host "Starting PHP-CGI"

    $proc = Get-WmiObject Win32_Process -Filter "Name='php-cgi.exe' and CommandLine LIKE '%localhost:$PhPort%'"
    if (!$proc)
    {
        Push-Location "php"
        CMD /C "START /B php-cgi.exe -b localhost:$PhPort 2>&1" # assignment hangs if not returning text
        Pop-Location
        Write-Host "  Starting PHP-CGI on port $PhPort"
    }
    else
    {
        $id = $proc.ProcessId
        Write-Host "  PHP-CGI already running on port $PhPort as process $id"
    }
}

#
# Nginx with PHP FastCGI
#
function Get-Nginx
{
    param( [string]$NgVersion )
    Write-Host "Verifying Nginx"

    if (Test-Path -Path "nginx\nginx.exe")
    {
        return "  Nginx already downloaded"
    }
    
    Write-Host "  Downloading Nginx from nginx.org"
    $NginxUrl = "http://nginx.org/download/nginx-$NgVersion.zip"
    Get-WebFile -Displayname "Nginx" -Url $NginxUrl -OutFile "ng.zip"
    Assert-Path -Path "ng.zip" -Error "Nginx download failed"

    Write-Host "  Expanding downloaded Nginx zip-archive"
    Expand-Archive -Path "ng.zip" -DestinationPath "ng-dir"
    Move-Item -Path "ng-dir\nginx*" -Destination "nginx"
    Assert-Path -Path "nginx\nginx.exe" -Error "Nginx unzip failed"
    Remove-Item -Path "ng-dir"
    Remove-Item -Path "ng.zip"
    
    Move-Item "nginx\conf\nginx.conf" "nginx\conf\orig-nginx.xonf"
    Move-Item "nginx\html" "nginx\orig-html"

    return "  Nginx downloaded"
}

function Set-Nginx
{
    param( [int]$NgPort, [int]$PhPort )
    Write-Host "Verifying Nginx configuration"
    # tests: # Remove-Item -Path "nginx\conf\nginx.conf" -Verbose

    if ((Test-Path -Path "nginx\conf\nginx.conf") -and `
        (Select-String -Path "nginx\conf\nginx.conf" -Pattern "listen.*$NgPort") -and `
        (Select-String -Path "nginx\conf\nginx.conf" -Pattern "fastcgi_pass.*$PhPort") -and `
        (Test-Path -Path "nginx\wordpress\index.php") -and `
        (Select-String -Path "nginx\wordpress\index.php" -Pattern "WordPress"))
    {
        return "  Nginx already configured"
    }

    if (!(Test-Path -Path "nginx\conf\nginx.conf"))
    {
        Copy-Item -Path "tools\_ng.conf" -Destination "nginx\conf\nginx.conf"
    }

    if (!((Select-String -Path "nginx\conf\nginx.conf" -Pattern "listen.*$NgPort") -and `
          (Select-String -Path "nginx\conf\nginx.conf" -Pattern "fastcgi_pass.*$PhPort")))
    {
        (Get-Content -Path "nginx\conf\nginx.conf") | ForEach-Object {
            $_ -Replace "listen.*", "listen $NgPort" -Replace "fastcgi_pass.*", "fastcgi_pass localhost:$PhPort"
        } | Set-Content -Path "nginx\conf\nginx.conf"
    }

    if (!(Test-Path -Path "nginx\wordpress"))
    {
        # hardlink nginx\wordpress --> .\wordpress 
        # Start-Process MKLINK -NoNewWindow -WindowStyle Minimized -RedirectStandardOutput
        CMD /C "MKLINK /J nginx\wordpress wordpress 1>NUL"
    }
    Assert-Path -Path "nginx\wordpress\index.php" -Pattern "WordPress" -Error "nginx\wordpress\index.php fail"

    $r = (Get-Netfirewallrule -DisplayName "nginx.exe" | Select-Object -Property action -First 1) 2>&1
    if ($r | Select-String -Pattern "^No ")
    {
        $thisDir = Get-Location
        $r = New-NetFirewallRule -DisplayName "nginx.exe" -Direction Inbound `
            -Program "$thisDir\nginx\nginx.exe" -RemoteAddress LocalSubnet -Action Allow
    }
    
    return "  Nginx configured"
}

function Start-Nginx
{
    param( [int]$NgPort )
    Write-Host "Starting Nginx"

    $proc = Get-WmiObject Win32_Process -Filter "Name='nginx.exe' and CommandLine LIKE '%ngport=$NgPort%'"
    if (!$proc)
    {
        Write-Host "  Starting Nginx on port $NgPort"
        Push-Location "nginx"
        CMD /C "START /B nginx.exe -g ""env ngport=$NgPort;"" 2>&1"
        Pop-Location
    }
    else
    {
        $id = $proc.ProcessId
        Write-Host "  Nginx already running on port $NgPort as process $id"
    }
}

#
# WordPress
#

function Get-WordPress
{
    param( [string]$WoVersion )
    Write-Host "Verifying WordPress"

    if (Test-Path -Path "wordpress\wp-login.php")
    {
        Assert-Path -Path "wordpress\index.php" -Pattern "WordPress" -Error "invalid wordpress\index.php"
        return "  WordPress already downloaded"
    }
    
    Write-Host "  Downloading WordPress from WordPress.org"
    $WordPressUrl = "https://wordpress.org/wordpress-$WoVersion.zip"
    Get-WebFile -Displayname "WordPress" -Url $WordPressUrl -OutFile "wo.zip"
    Assert-Path -Path "wo.zip" -Error "WordPress download failed"

    Write-Host "  Expanding downloaded WordPress zip-archive"
    Expand-Archive -Path "wo.zip" -DestinationPath "wo-dir"
    Move-Item -Path "wo-dir\wordpress*" -Destination "wordpress"
    Assert-Path -Path "wordpress\wp-login.php" -Error "WordPress unzip failed"
    Remove-Item -Path "wo-dir"
    Remove-Item -Path "wo.zip"

    Remove-Item -Path "wordpress\wp-config-sample.php"

    return "  WordPress downloaded"
}

function Set-WordPress
{
    param( [string]$MaPort )
    Write-Host "Verifying WordPress configuration"
    # tests: # Remove-Item -Path "php\php.ini" -Verbose
    
    if ((Test-Path -Path "wordpress\wp-config.php") -and `
        (Select-String -Path "wordpress\wp-config.php" -Pattern "DB_HOST.*localhost:$MaPort"))
    {
        return "  WordPress already configured"
    }
    
    if (!(Test-Path -Path "wordpress\wp-config.php"))
    {
        Copy-Item -Path "tools\_wo.conf" -Destination "wordpress\wp-config.php"
    }
  
    if (!(Select-String -Path "wordpress\wp-config.php" -Pattern "DB_HOST.*localhost:$MaPort"))
    {
        (Get-Content -Path "wordpress\wp-config.php") | ForEach-Object {
            $_ -Replace "DB_HOST.*", "DB_HOST', 'localhost:$MaPort');"
        } | Set-Content -Path "wordpress\wp-config.php"
    }

    if (!(Test-Path -Path "wp-content"))
    {
        Write-Host "  Moving WordPress content to wp-content -folder so that it will not get over-written"
        Move-Item -Path "wordpress\wp-content" -Destination "wp-content"
        CMD /C "MKLINK /J wordpress\wp-content wp-content 1>NUL"
    }
    Assert-Path -Path "wp-content\themes" -Error "WordPress wp-content folder incomplete"

    return "  WordPress configured"
}

function Start-WordPress
{
    param( [string]$MaPort, [string]$PhPort, [string]$NgPort )
    Write-Host "Starting WordPress"

    $ma = Get-WmiObject Win32_Process -Filter "Name='mysqld.exe' and CommandLine LIKE '%port $MaPort%'"
    $ph = Get-WmiObject Win32_Process -Filter "Name='php-cgi.exe' and CommandLine LIKE '%localhost:$PhPort%'"
    $ng = Get-WmiObject Win32_Process -Filter "Name='nginx.exe' and CommandLine LIKE '%ngport=$NgPort%'"

    if (!$ma)
    {
        throw "MariaDB not running on port $MaPort"
    }
    
    if (!$ph)
    {
        throw "PHP-FastCGI not running on port $PhPort"
    }

    if (!$ng)
    {
        throw "Nginx not running on $NgPort"
    }

    $query = "SHOW DATABASES"
    $res = mariadb\bin\mysql.exe --user=root --password= -e $query
    if ($res -notcontains "wordpress")
    {
        Write-Host "  Adding wordpress user and database table"
        $query = "CREATE DATABASE wordpress;"
        $query = "$query GRANT ALL PRIVILEGES ON wordpress.* TO 'wordpress'@'localhost' IDENTIFIED BY 's3cr3t';"
        $query = "$query FLUSH PRIVILEGES;"
        mariadb\bin\mysql.exe --user=root --password= -e $query
    }

    $query = "SELECT option_name, option_value FROM wordpress.wp_options"
    $query = "$query WHERE option_name = 'siteurl' OR option_name = 'home';"
    $res = mariadb\bin\mysql.exe --user=root --password= -e $query 2>&1
    if ($res -notmatch 'ERROR')
    {
        $query = "UPDATE wordpress.wp_options SET option_value='http://localhost:$NgPort'"
        $query = " $query WHERE option_name='siteurl' OR option_name='home';"
        mariadb\bin\mysql.exe --user=root --password= -e $query 2>&1
        # wordpress.wp_options db_version='$NgPort', initial_db_version='$NgPort'    
    }

    Set-Clipboard -Value "HTTP://localhost:${env:NG_PORT}/"
    Write-Host "  WordPress is now running at ""HTTP://localhost:${env:NG_PORT}/"". The URL is in your clip-board"
}

#
# Invoke Main now, when all functions have been parsed
#    

Main -ScriptName $MyInvocation.MyCommand.Name