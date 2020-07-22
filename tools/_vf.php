<?php
echo("MaPhWoNg\n");

$servername = "localhost";
$username = "root";
$password = "MaPhWoNg";
$db = "wordpress";
$port = "0";

// Create connection
$conn = new mysqli($servername, $username, $password, $db, $port);

// Check connection
if ($conn->connect_errno) {
    echo "Database connection failed: " . $conn->connect_error;
    return;
} else {
    echo "Database connected successfully";
}

echo "<br/>databases<br/>";
$result = mysqli_query($conn,"SHOW DATABASES"); 
while ($row = mysqli_fetch_array($result)) { 
    echo $row[0]."<br/>"; 
}

echo "<br/>tables<br/>";
$result = mysqli_query($conn,"SHOW TABLES"); 
while ($row = mysqli_fetch_array($result)) { 
    echo $row[0]."<br/>"; 
}

//    phpinfo(INFO_MODULES);

