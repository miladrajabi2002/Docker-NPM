<?php
$host = getenv('MYSQL_HOST');
$db   = getenv('MYSQL_DATABASE');
$user = getenv('MYSQL_USER');
$pass = getenv('MYSQL_PASSWORD');

try {
   $pdo = new PDO("mysql:host=$host;dbname=$db", $user, $pass);
   echo "✅ Successfully connected to MariaDB using PDO!";
} catch (PDOException $e) {
   echo "❌ Error connecting to database: " . $e->getMessage();
}
