<?php
echo("MaPhWoNg\n");

$servername = "localhost";
$username = "root";
$password = "";
$db = "wordpress";
$port = "0"; // MA_PORT

// Create connection
$conn = new mysqli($servername, $username, $password, $db, $port);

// Check connection
if ($conn->connect_error) {
    echo "Database connection failed: " . $conn->connect_error;
} else {
    echo "Database connected successfully";
}

phpinfo(INFO_MODULES);
