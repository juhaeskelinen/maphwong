<#
.SYNOPSIS
MaphWong setup script for WordPress localhost development environment in Windows 10 PC.
Download, configure, and start MariaDB and Nginx with PHP-FastCGI to run WordPress

.DESCRIPTION
MaphWong sets up WordPress localhost development environment in Windows 10 PC.
It downloads, configures, and starts MariaDB and Nginx with PHP-FastCGI to run WordPress.
This PowerShell script is invoked by the associated "start.bat" Windows command -script
The "tools\config.txt" configuration file contains the port numbers and version identifiers for the components.
  (MA_PORT, PH_PORT, NG_PORT, MA_VERSION, PH_VERSION, WO_VERSION, NG_VERSION )
Main -function contains the logic-flow. It will be invoked after all other functions have been parsed
  (at the end of this file).

.EXAMPLE
start.bat (or start.ps1)

.NOTES
Written by: Juha Eskelinen, https://juhaeskelinen.com
#>

# stop on any error
$ErrorActionPreference = "Stop"

#
# Main will be invoked after all other functions have been parsed (at the end of this file)
#
function Main
{
    param( [string]$ScriptName )

    #Set-PsDebug -Trace 2 -Strict # un-comment and run as administrator start.bat > debug.txt to get full debug trace
    Start-Transcript -path .\tools\trace.txt | Out-Null

    Try { Setup }
    Catch { $_ }
    Finally { $Host.UI.RawUI.ReadKey('NoEcho, IncludeKeyDown') | Out-Null}
}

function Setup
{
    Write-Host "Setting up MariaDB database, PHP-FastCGI platform, WordPress software, and Nginx web server"
    Write-Host "#    __  __         _____   _  __          __     _   _        "
    Write-Host "#   |  \/  |       |  __ \ | | \ \        / /    | \ | |       "
    Write-Host "#   | \  / |  __ _ | |__) || |__\ \  /\  / /___  |  \| |  __ _ "
    Write-Host "#   | |\/| | / _  ||  ___/ |  _ \\ \/  \/ // _ \ |     | / _  |"
    Write-Host "#   | |  | || (_| || |     | | | |\  /\  /| (_) || |\  || (_| |"
    Write-Host "#   |_|  |_| \__ _||_|     |_| |_| \/  \/  \___/ |_| \_| \__  |"
    Write-Host "#                                                         __/ |"
    Write-Host "#                                                        |___/ "

    # Set current working directory to MaphWong folder
    Split-Path -Path $PsScriptRoot -Parent | Set-Location
    $conf = Get-Config("tools\config.txt")
    
    # Install pre-requisites
    if (!(Test-Vc2017Redist))
    {
        Install-Vc2017Redist
    }

    # Download components
    Get-MariaDb -MaVersion $conf.MA_VERSION
    Get-Php -PhVersion $conf.PH_VERSION
    Get-WordPress -WoVersion $conf.WO_VERSION
    Get-Nginx -NgVersion $conf.NG_VERSION

    # Configure components
    Set-MariaDb -MaPort $conf.MA_PORT
    Set-Php
    Set-WordPress -MaPort $conf.MA_PORT
    Set-Nginx -NgPort $conf.NG_PORT -PhPort $conf.PH_PORT
    
    # Start components
    Start-MariaDb -MaPort $conf.MA_PORT 
    Start-Php -PhPort $conf.PH_PORT
    Start-Nginx -NgPort $conf.NG_PORT

    # Verify that components are running and update database content
    Start-Wordpress -MaPort $conf.MA_PORT -PhPort $conf.PH_PORT -NgPort $conf.NG_PORT
}

function Get-Config
{
    param( [string]$Path )
    $hsh = @{};
    Get-Content $Path | foreach-object `
        -process { $kv = [regex]::split($_ , '='); `
            if ($kv[0] -and (!$kv[0].StartsWith("#"))) `
                { $hsh.Add($kv[0], $kv[1]) } }
    $hsh
}

function Assert-Path
{
    param( [string]$Path, [switch]$Missing, [string]$Pattern, [string]$Error )
    if ($Missing)
    {
        if (Test-Path -Path $Path)
        {
            throw $Error
        }
        return
    }
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
    Invoke-RestMethod -URI "https://ipinfo.io/loc"
}

function Get-WebFile
{
    param( [string]$Displayname, [string]$Url, [string]$OutFile )

    Import-Module BitsTransfer
    $null = Start-BitsTransfer -Source $url -Destination $OutFile `
     -Displayname "Downloading $Displayname    (in case of emergency break process with Ctrl-C)" `
     -Description "from $Url "
}

function Test-Vc2017Redist
{
    $p64 = Get-ItemProperty -ErrorAction SilentlyContinue -Path Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64
    if ($p64.Minor -gt 0)
    {
        $True
        return
    }
    $False
}

function Install-Vc2017Redist
{
    Write-Host("Installing Microsoft Visual C++ Redistributable for Visual Studio 2017 library to run WordPress with PHP-FastCGI")
    Get-Webfile -DisplayName "VC_redist.x64.exe" -Url "https://aka.ms/vs/15/release/VC_redist.x64.exe" -OutFile "VC_redist.x64.exe"
    Start-Process -Wait -NoNewWindow -FilePath "VC_redist.x64.exe" -ArgumentList "/passive", "/norestart"
    Remove-Item -Path "VC_redist.x64.exe"
}

function DbQuery
{
    param( [string]$Query )
    (mariadb\bin\mysql.exe --user=root --password= -e $Query 2>&1) | Out-String
}

#
# MariaDB
#
function Get-MariaDb
{
    param( [string]$MaVersion )
    Write-Host "Verifying MariaDB folder"

    if (Test-Path -Path "mariadb\bin\mysql.exe")
    {
        Write-Host "  MariaDB already downloaded"
        return
    }
    Assert-Path -Missing -Path "mariadb" -Error "MariaDB folder exists, but is incomplete"

    Write-Host "  Downloading MariaDB from closest DigitalOcean.com mirror"
    $MariaDbZip = "mariadb/mariadb-" + $MaVersion + "/winx64-packages/mariadb-" + $MaVersion + "-winx64.zip"
    $GeoLocation = Get-GeoLocation # format 61.4354,23.8622
    $longitude = [int]$GeoLocation.Split(",.")[2]
    if (!$longitude) { $longitude = 116 }
    if ($longitude -ge 60) { $MariaDbMirror = "http://sgp1.mirrors.digitalocean.com/" } # Asia, Australia
    elseif ($longitude -ge -30) { $MariaDbMirror = "http://ams2.mirrors.digitalocean.com/" } # Europe, Africa
    else { $MariaDbMirror = "http://nyc2.mirrors.digitalocean.com/" } # Americas
    $MariaDbUrl = $MariaDbMirror + $MariaDbZip
    Remove-Item -Path "ma.zip" -ErrorAction SilentlyContinue
    Get-WebFile -Displayname "MariaDB" -Url $MariaDbUrl -OutFile "ma.zip"
    Assert-Path -Path "ma.zip" -Error "MariaDB download failed"

    Write-Host "  Expanding downloaded MariaDB zip-archive"
    Remove-Item -Path "ma-dir" -ErrorAction SilentlyContinue
    Expand-Archive -Path "ma.zip" -DestinationPath "ma-dir"
    Remove-Item -Path "ma.zip"
    Move-Item -Path "ma-dir\mariadb*" -Destination "mariadb"
    Remove-Item -Path "ma-dir"
    Assert-Path -Path "mariadb\bin\mysql.exe" -Error "MariaDB unzip failed"

    Write-Host "  MariaDB downloaded"
}

function Set-MariaDb
{
    param( [int]$MaPort )
    Write-Host "Verifying MariaDB configuration"

    $thisDir = Get-Location
    $thisDirUnix = $thisDir -Replace "\\", "/"

    if (!(Test-Path -Path "mariadb\my.ini"))
    {
        Copy-Item -Path "tools\_ma.conf" -Destination "mariadb\my.ini"
    }

    if (!((Select-String -Path "mariadb\my.ini" -Pattern "port.*$MaPort") -and `
          (Select-String -Path "mariadb\my.ini" -SimpleMatch "$thisDirUnix/mariadb-data")))
    {
        (Get-Content -Path "mariadb\my.ini") | ForEach-Object {
            $_ -Replace "port.*", "port = $MaPort" -Replace "socket.*", "socket = mydb$MaPort" `
            -Replace "datadir.*", "datadir = $thisDirUnix/mariadb-data"
        } | Set-Content -Path "mariadb\my.ini"
    }

    if (Test-Path -Path "mariadb\data") 
    {
        if (Test-Path -Path "mariadb-data")
        {
            Write-Host "  Folder mariadb-data already exists. Keeping the old version"
            #Remove-Item -Force -Recurse -Path "mariadb\data"
            Remove-Item -Path "mariadb\data"
        }
        else
        {
            Write-Host "  Moving MariaDB data to folder mariadb-data so that it will not get over-written"
            Move-Item -Path "mariadb\data" -Destination "mariadb-data"
        }
    }
    Assert-Path -Path "mariadb-data\mysql" -Error "MariaDB mariadb-data folder incomplete"

    Write-Host "  MariaDB configured"
}

function Start-MariaDb
{
    param( [int]$MaPort, [int]$NgPort )
    Write-Host "Starting MariaDB"

    if (Get-WmiObject Win32_Process -Filter "Name='mysqld.exe' and CommandLine LIKE '%port $MaPort%'")
    {
        Write-Host "  MariaDB already running on port $MaPort"
        return
    }

    Write-Host "  Starting MariaDB on port $MaPort"
    Start-Process -NoNewWindow -WorkingDirectory "mariadb" -FilePath "mariadb\bin\mysqld.exe"`
        -ArgumentList "--defaults-file=my.ini", "--port $MaPort"
}

#
# PHP
#

function Get-Php
{
    param( [string]$PhVersion )
    Write-Host "Verifying PHP-FastCGI folder"

    if (Test-Path -Path "php\php.exe")
    {
        Write-Host "  PHP-FastCGI already downloaded"
        return
    }
    Assert-Path -Missing -Path "php"  -Error "PHP-FastCGI folder exists, but is incomplete"

    Write-Host "  Downloading PHP-FastCGI from windows.php.net"
    $PhpUrl = "https://windows.php.net/downloads/releases/archives/php-$PhVersion-Win32-VC15-x64.zip"
    Remove-Item -Path "ph.zip" -ErrorAction SilentlyContinue
    Get-WebFile -Displayname "PHP FastCGI" -Url $PhpUrl -OutFile "ph.zip"
    Assert-Path -Path "ph.zip" -Error "PHP-FastCGI download failed"

    Write-Host "  Expanding downloaded PHP-FastCGI zip-archive"
    Remove-Item -Path "ph-dir" -ErrorAction SilentlyContinue
    Expand-Archive -Path "ph.zip" -DestinationPath "ph-dir"
    Remove-Item -Path "ph.zip"
    Move-Item -Path "ph-dir" -Destination "php"
    Assert-Path -Path "php\php.exe" -Error "PHP-FastCGI unzip failed"

    Write-Host "  PHP-FastCGI downloaded"
}

function Set-Php
{
    Write-Host "Verifying PHP-FastCGI configuration"
    
    if (!(Test-Path -Path "php\php.ini"))
    {
        Copy-Item -Path "tools\_ph.conf" -Destination "php\php.ini"
    }
    
    Write-Host "  PHP-FastCGI configured"
}

function Start-Php
{
    param( [int]$PhPort )
    Write-Host "Starting PHP-FastCGI"

    if (Get-WmiObject Win32_Process -Filter "Name='php-cgi.exe' and CommandLine LIKE '%localhost:$PhPort%'")
    {
        Write-Host "  PHP-FastCGI already running on port $PhPort"
        return
    }

    Write-Host "  Starting PHP-FastCGI on port $PhPort"
    Start-Process -NoNewWindow -WorkingDirectory "php" -FilePath "php\php-cgi.exe"`
        -ArgumentList "-b", "localhost:$PhPort"
}

#
# Nginx with PHP FastCGI
#
function Get-Nginx
{
    param( [string]$NgVersion )
    Write-Host "Verifying Nginx folder"

    if (Test-Path -Path "nginx\nginx.exe")
    {
        Write-Host "  Nginx already downloaded"
        return
    }
    Assert-Path -Missing -Path "nginx" -Error "Nginx folder exists, but is incomplete"
    
    Write-Host "  Downloading Nginx from nginx.org"
    $NginxUrl = "http://nginx.org/download/nginx-$NgVersion.zip"
    Remove-Item -Path "ng.zip" -ErrorAction SilentlyContinue
    Get-WebFile -Displayname "Nginx" -Url $NginxUrl -OutFile "ng.zip"
    Assert-Path -Path "ng.zip" -Error "Nginx download failed"

    Write-Host "  Expanding downloaded Nginx zip-archive"
    Remove-Item -Path "ng-dir" -ErrorAction SilentlyContinue
    Expand-Archive -Path "ng.zip" -DestinationPath "ng-dir"
    Remove-Item -Path "ng.zip"
    Move-Item -Path "ng-dir\nginx*" -Destination "nginx"
    Remove-Item -Path "ng-dir"
    Assert-Path -Path "nginx\nginx.exe" -Error "Nginx unzip failed"
    
    Move-Item "nginx\conf\nginx.conf" "nginx\conf\orig-nginx.xonf"
    Move-Item "nginx\html" "nginx\orig-html"

    Write-Host "  Nginx downloaded"
}

function Set-Nginx
{
    param( [int]$NgPort, [int]$PhPort )
    Write-Host "Verifying Nginx configuration"

    if (!(Test-Path -Path "nginx\conf\nginx.conf"))
    {
        Copy-Item -Path "tools\_ng.conf" -Destination "nginx\conf\nginx.conf"
    }

    if (!((Select-String -Path "nginx\conf\nginx.conf" -Pattern "listen.*$NgPort") -and `
          (Select-String -Path "nginx\conf\nginx.conf" -Pattern "fastcgi_pass.*$PhPort")))
    {
        (Get-Content -Path "nginx\conf\nginx.conf") | ForEach-Object {
            $_ -Replace "listen.*", "listen $NgPort;" -Replace "fastcgi_pass.*", "fastcgi_pass localhost:$PhPort;"
        } | Set-Content -Path "nginx\conf\nginx.conf"
    }

    $link = Get-Item "nginx\wordpress" -ErrorAction SilentlyContinue
    if ($link.Target -and (($link.Target | Split-Path -parent) -ne (Get-Location)))
    {
        Write-Host "  Adjusting wordpress link"
        #Remove-Item "nginx\wordpress" -Force -Confirm:$False
        (Get-Item "nginx\wordpress").Delete()
    }

    if (!(Test-Path -Path "nginx\wordpress"))
    {
        # link nginx\wordpress --> wordpress 
        $null = New-Item -ItemType Junction -Name nginx\wordpress -Target wordpress
    }
    
    Assert-Path -Path "nginx\wordpress\index.php" -Pattern "WordPress" -Error "nginx\wordpress\index.php fail"
    
    Write-Host "  Nginx configured"
}

function Start-Nginx
{
    param( [int]$NgPort )
    Write-Host "Starting Nginx"

    if (Get-WmiObject Win32_Process -Filter "Name='nginx.exe' and CommandLine LIKE '%ngport=$NgPort%'")
    {
        Write-Host "  Nginx already running on port $NgPort"
        return
    }
    
    if (!(Get-NetFirewallRule -DisplayName "nginx" -ErrorAction SilentlyContinue))
    {
        Write-Host "  If you get a firewall prompt for Nginx, allow none or Private networks"
    }

    Write-Host "  Starting Nginx on port $NgPort"
    Start-Process -NoNewWindow -WorkingDirectory "nginx" -FilePath "nginx\nginx.exe"`
        -ArgumentList "-g", "`"env ngport=$NgPort;`""
}

#
# WordPress
#

function Get-WordPress
{
    param( [string]$WoVersion )
    Write-Host "Verifying WordPress folder"

    if (Test-Path -Path "wordpress\wp-login.php")
    {
        Assert-Path -Path "wordpress\index.php" -Pattern "WordPress" -Error "invalid wordpress\index.php"
        Write-Host "  WordPress already downloaded"
        return
    }
    Assert-Path -Missing -Path "wordpress" -Error "WordPress folder exists, but is incomplete"
    
    Write-Host "  Downloading WordPress from WordPress.org"
    $WordPressUrl = "https://wordpress.org/wordpress-$WoVersion.zip"
    Remove-Item -Path "wo.zip" -ErrorAction SilentlyContinue
    Get-WebFile -Displayname "WordPress" -Url $WordPressUrl -OutFile "wo.zip"
    Assert-Path -Path "wo.zip" -Error "WordPress download failed"

    Write-Host "  Expanding downloaded WordPress zip-archive"
    Remove-Item -Path "wo-dir" -ErrorAction SilentlyContinue
    Expand-Archive -Path "wo.zip" -DestinationPath "wo-dir"
    Remove-Item -Path "wo.zip"
    Move-Item -Path "wo-dir\wordpress*" -Destination "wordpress"
    Remove-Item -Path "wo-dir"
    Assert-Path -Path "wordpress\wp-login.php" -Error "WordPress unzip failed"

    Remove-Item -Path "wordpress\wp-config-sample.php"

    Write-Host "  WordPress downloaded"
}

function Set-WordPress
{
    param( [string]$MaPort )
    Write-Host "Verifying WordPress configuration"
    
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

    $item = Get-Item "wordpress\wp-content" -ErrorAction SilentlyContinue
    if ($item)
    {
        if (!$item.Target)
        {
            # normal folder
            if (Test-Path -Path "wp-content")
            {
                Write-Host "  Folder wp-content already exists. Keeping the old version"
                Remove-Item -Force -Recurse -Path "wordpress\wp-content"
            }
            else
            {
                Write-Host "  Moving WordPress content to wp-content -folder so that it will not get over-written"
                Move-Item -Path "wordpress\wp-content" -Destination "wp-content"
            }
        }
        else
        {
            # junction. Check target
            if (($item.Target | Split-Path -parent) -ne (Get-Location))
            {
                Write-Host "  Adjusting wordpress\wp-content link"
                (Get-Item "wordpress\wp-content").Delete()
            }
        }
    }

    $item = Get-Item "wordpress\wp-content" -ErrorAction SilentlyContinue
    if (!$item.Target)
    {
        $null = New-Item -ItemType Junction -Name "wordpress\wp-content" -Target "wp-content"
    }

    Assert-Path -Path "wp-content\themes" -Error "WordPress wp-content folder incomplete"

    Write-Host "  WordPress configured"
}

function Start-WordPress
{
    param( [string]$MaPort, [string]$PhPort, [string]$NgPort )
    Write-Host "Starting WordPress"

    for ($i = 3; $i -ge 0; $i++)
    {
        $allRunning = $True
        if (!(Get-WmiObject Win32_Process -Filter "Name='mysqld.exe' and CommandLine LIKE '%port $MaPort%'"))
        {
            Write-Host "MariaDB not running on port $MaPort"
            $allRunning = $False
        }

        if (!(Get-WmiObject Win32_Process -Filter "Name='php-cgi.exe' and CommandLine LIKE '%localhost:$PhPort%'"))
        {
            Write-Host  "PHP-FastCGI not running on port $PhPort"
            $allRunning = $False
        }

        if (!(Get-WmiObject Win32_Process -Filter "Name='nginx.exe' and CommandLine LIKE '%ngport=$NgPort%'"))
        {
            Write-Host  "Nginx not running on $NgPort"
            $allRunning = $False
        }

        if ($allRunning)
        {
            break
        }

        if ($i -eq 0)
        {
            Throw "Startup failed. Try runing this script once more"
        }

        Start-Sleep -Seconds 10
    }

    $query = "SHOW DATABASES"
    if (!(DbQuery -Query $query | Select-String "wordpress"))
    {
        Start-Sleep 5 # maybe MariaDB was just slow to start
        if (!(DbQuery -Query $query | Select-String "wordpress"))
        {
            Write-Host "  Adding wordpress user and database table"
            $query = "CREATE DATABASE wordpress;"`
                + " GRANT ALL PRIVILEGES ON wordpress.* TO 'wordpress'@'localhost' IDENTIFIED BY 's3cr3t';"`
                + " FLUSH PRIVILEGES;"
            DbQuery -Query $query | Out-Null
        }
    }

    $query = "SHOW TABLES FROM wordpress"
    if (DbQuery -Query $query | Select-String "wordpress")
    {
        $query = "UPDATE wordpress.wp_options SET option_value='http://localhost:$NgPort'"`
        + " WHERE option_name='siteurl' OR option_name='home';"
        DbQuery -Query $query | Out-Null
    }

    Set-Clipboard -Value "HTTP://localhost:$NgPort/"
    Write-Host -NoNewline "  WordPress is now initialized and running at """
    Write-Host -NoNewline -ForegroundColor DarkGreen "HTTP://localhost:$NgPort/"
    Write-Host -NoNewline """. "
    Write-Host "The URL is in your clip-board"
}

#
# Invoke Main now, when all functions have been parsed
#    

Main -ScriptName $MyInvocation.MyCommand.Name