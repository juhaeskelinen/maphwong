<?php
echo("MaPhWoNg\n");

$servername = "127.0.0.1";
$username = "wordpress";
$password = "s3cr3t";

// Create connection
$conn = new mysqli($servername, $username, $password);

// Check connection
if ($conn->connect_error) {
    echo "Database connection failed: " . $conn->connect_error;
} else {
    echo "Database connected successfully";
}

phpinfo(INFO_MODULES);
