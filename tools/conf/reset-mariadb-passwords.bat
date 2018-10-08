
START /B mariadb\bin\mysqld_safe --skip-grant-tables --defaults-file=%CD%\mariadb\my.ini
mariadb\bin\mysql -uroot -e "update mysql.user set password=password('s3cr3t') where user='root';"
mariadb\bin\mysql -u root -e "update wordpress.wp_users set user_pass=MD5('s3cr3t'), user_login='admin' where id='1';"