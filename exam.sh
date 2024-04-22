#!/bin/bash

# define variables
apache_package="apache2"
mysql_package="mysql-server"
php_package="php libapache2-mod-php php-mysql"
github_repo="https://github.com/laravel/laravel.git"
app_directory="/var/www/html/laravel"

# Function to check if the last command was successful
check_error() {
    if [ $? -ne 0 ]; then
        echo "Error occurred. Exiting..."
        exit 1
    fi
}

# Function to echo task messages
echo_task() {
    echo "$1"
}

# Updating php index
 sudo add-apt-repository -y ppa:ondrej/php
 check_error

# Update package index
 echo_task "Updating package index"
 sudo apt update

#Install Expect
 sudo apt-get install expect -y

# Install Apache
 echo_task "Installing Apache"
 sudo apt install -y $apache_package

# Start Apache
 sudo systemctl start $apache_package

# Enable Apache to start on boot
 sudo systemctl enable $apache_package

# Install MySQL Server
 echo "Installing MySQL Server"# sudo debconf-set-selections <<< '$mysql_package $mysql_package/root_password password'
 sudo debconf-set-selections <<< '$mysql_package $mysql_package/root_password_again password'
 sudo apt-get -y install $mysql_package

# Secure MySQL installation
 echo_task "Securing MySQL installation"
 expect <<EOF
 spawn sudo mysql_secure_installation

expect "Would you like to setup VALIDATE PASSWORD component?"
send "y\r"
expect{
    "Please enter 0 = LOW, 1 = MEDIUM and 2 = STRONG"{
        send "1\r"
        exp_continue
    }
    "Remove anonymous users?"{
        send "y\r"
        exp_continue
    }
    "Disallow root login remotely?"{
        send "n\r"
        exp_continue
    }
    "Remove test database and access to it?"{
        send "y\r"
        exp_continue
    }
    "Reload privilege tables now?"{
        send "y\r"
        exp_continue
    }
}
EOF


# Install PHP
echo "installing php"
sudo apt install -y $php_package php8.2 php8.2-curl php8.2-dom php8.2-xml php8.2-mysql php8.2-sqlite3
check_error

# Making php 8.2 default
echo "making php default"
sudo update-alternatives --set php /usr/bin/php8.2
sudo a2enmod php8.2
check_error

# Clone PHP application from Github
echo "cloning from github"
git clone $github_repo $app_directory
check_error

# Restart Apache
sudo systemctl restart apache2
check_error

# Display completion message
echo "LAMP stack deployment complete."
check_error

# Navigating to Laravel directory
cd $app_directory
check_error

# Set permissions for the PHP application directory
sudo chown -R www-data:www-data $app_directory
sudo chmod -R 755 $app_directory
check_error

# Installing Composer 
echo "Installing Composer..."
sudo apt install composer -y
check_error

# Download and install Composer
echo "Downloading and installing Composer..."
sudo php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
sudo php composer-setup.php --install-dir=/usr/local/bin --filename=composer
check_error

# Cleanup Composer setup file
echo "Cleaning up..."
sudo rm composer-setup.php

# Set environment variable to allow Composer to run as superuser
export COMPOSER_ALLOW_SUPERUSER=1


# Installing Laravel, PHP dependencies using Composer
echo "Installing Laravel and PHP dependencies using Composer..."
sudo -S <<< "yes" composer install
check_error

echo "Composer installation and Laravel dependencies installation complete."

# Check if Laravel directories exist
if [ ! -d "$app_directory/storage" ] || [ ! -d "$app_directory/bootstrap/cache" ]; then
    echo "Error: Laravel directories not found. Creating..."
    sudo mkdir -p "$app_directory/storage"
    sudo mkdir -p "$app_directory/bootstrap/cache"
    sudo chown -R www-data:www-data "$app_directory/storage"
    sudo chown -R www-data:www-data "$app_directory/bootstrap/cache"
    sudo chmod -R 775 "$app_directory/storage"
    check_error
fi

# Setting permissions for laravel directories
sudo chown -R www-data:www-data $app_directory/storage
sudo chown -R www-data:www-data $app_directory/bootstrap/cache
sudo chmod -R 775 $app_directory/storage/logs
check_error

# Setting up environment configuration
echo "Setting up environment configuration"
sudo cp "$app_directory/.env.example" "$app_directory/.env"

# Check if .env file exists
if [ ! -f "$app_directory/.env" ]; then
    echo "Error: .env file not found. Creating..."
    sudo cp "$app_directory/.env.example" "$app_directory/.env"
fi

# Set permissions for the .env file
sudo chown www-data:www-data "$app_directory/.env"
sudo chmod 640 "$app_directory/.env"
check_error

# Configure Apache to serve the PHP application 
sudo cp /etc/apache2/sites-available/000-default.conf /etc/apache2/sites-available/laravel.conf
sudo a2ensite laravel.conf
check_error

# Check if database directory exists
if [ ! -d "$app_directory/database" ]; then
    echo "Error: Database directory not found. Creating..."
    sudo mkdir -p "$app_directory/database"
fi

# Set permissions for the database directory
sudo chown -R www-data:www-data "$app_directory/database"
sudo chmod -R 755 "$app_directory/database"
check_error

# Reload Apache to apply changes
sudo systemctl reload apache2
check_error


# Create Apache Virtual Host configuration file
echo "Creating Apache Virtual Host configuration file"
sudo tee /etc/apache2/sites-available/laravel.conf >/dev/null <<EOF
<VirtualHost *:80>
    ServerName 192.168.1.100
    ServerAlias *
    DocumentRoot /var/www/html/laravel/public

    <Directory /var/www/html/laravel>
        AllowOverride All
    </Directory>
</VirtualHost>
EOF
check_error

# To activate the new configuration 
sudo systemctl reload apache2
check_error

# Generating artisan application key
sudo php artisan key:generate
check_error

# Migration 
echo "migrating data base"
sudo php artisan migrate --force
check_error

# Setting permission for laravel database
echo "setting permission for database"
sudo chown -R www-data:www-data $app_directory/database/
sudo chmod -R 775 $app_directory/database/
check_error

# Disable the default apache file
sudo a2dissite 000-default.conf
check_error

# Enable the laravel site
sudo a2ensite laravel.conf
check_error

# Reload Apache to apply changes
sudo systemctl restart apache2

echo "PHP application deployment complete"
