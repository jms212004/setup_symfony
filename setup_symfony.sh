#!/bin/bash

# Colors for messages
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display messages
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_question() {
    echo -e "${BLUE}[QUESTION]${NC} $1"
}

# Function to check if a directory is empty
is_dir_empty() {
    if [ -d "$1" ] && [ -n "$(ls -A "$1" 2>/dev/null)" ]; then
        return 1
    fi
    return 0
}

# Define base directory
BASE_DIR="/home/vagrant"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Ask for MySQL root password
print_question "Enter MySQL root password:"
read -s MYSQL_ROOT_PASSWORD
echo "" # For line break after password input

# Ask for installation directory
print_question "Do you want to install the project in the current directory? (y/n)"
read -r response

if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    PROJECT_DIR="$SCRIPT_DIR"
    print_message "Installing in current directory: $PROJECT_DIR"
else
    print_question "Enter the directory name for the project (relative or absolute path):"
    read -r PROJECT_DIR
    
    # If path is relative, convert to absolute
    if [[ ! "$PROJECT_DIR" = /* ]]; then
        PROJECT_DIR="$BASE_DIR/$PROJECT_DIR"
    fi
    
    # If directory exists, remove it
    if [ -d "$PROJECT_DIR" ]; then
        print_warning "Directory $PROJECT_DIR already exists."
        print_warning "Removing existing directory..."
        rm -Rf "$PROJECT_DIR"
    fi
    
    print_message "Creating directory $PROJECT_DIR"
    mkdir -p "$PROJECT_DIR"
fi

# Extract database name from project path and clean it
DB_NAME=$(basename "$PROJECT_DIR" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')
DB_TEST_NAME="${DB_NAME}_test"

# Check MySQL connection
print_message "Checking MySQL connection..."
if ! mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1" &> /dev/null; then
    print_error "Unable to connect to MySQL. Please check the root password."
    exit 1
fi

# Remove existing databases
print_warning "Checking for existing databases..."

# Function to drop a database
drop_database() {
    local db_name=$1
    if mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SHOW DATABASES LIKE '$db_name'" | grep -q "$db_name"; then
        print_warning "Database $db_name exists."
        print_question "Do you want to drop it? (y/n)"
        read -r drop_response
        if [[ "$drop_response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "DROP DATABASE IF EXISTS $db_name"
            print_message "Database $db_name dropped."
        else
            print_error "Installation cancelled. Database $db_name already exists."
            exit 1
        fi
    fi
}

# Drop databases
drop_database "$DB_NAME"
drop_database "$DB_TEST_NAME"

# Cleanup
print_message "Cleaning environment..."

# Remove temporary files in project directory
print_warning "Cleaning temporary files..."
if [ -d "$PROJECT_DIR" ]; then
    rm -f "$PROJECT_DIR/composer.lock"
    rm -f "$PROJECT_DIR/.env"
    rm -f "$PROJECT_DIR/.env.local"
    rm -f "$PROJECT_DIR/.env.test"
    rm -f "$PROJECT_DIR/.env.test.local"
fi

# Clean Composer cache
print_warning "Cleaning Composer cache..."
composer clear-cache

# Check prerequisites
print_message "Checking prerequisites..."

# Check if Composer is installed
if ! command -v composer &> /dev/null; then
    print_error "Composer is not installed. Please install it first."
    exit 1
fi

# Check if PHP is installed
if ! command -v php &> /dev/null; then
    print_error "PHP is not installed. Please install it first."
    exit 1
fi

# Check if MySQL is installed
if ! command -v mysql &> /dev/null; then
    print_error "MySQL is not installed. Please install it first."
    exit 1
fi

# Check PHP version
PHP_VERSION=$(php -v | head -n 1 | cut -d " " -f 2 | cut -d "." -f 1)
if [ "$PHP_VERSION" -lt 8 ]; then
    print_error "PHP 8.0 or higher is required. Current version: $(php -v | head -n 1)"
    exit 1
fi

# Create Symfony project
print_message "Creating Symfony project in $PROJECT_DIR..."
cd "$PROJECT_DIR" || exit 1

# Check available disk space
AVAILABLE_SPACE=$(df -BG "$PROJECT_DIR" | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$AVAILABLE_SPACE" -lt 1 ]; then
    print_error "Insufficient disk space. At least 1 GB is required."
    exit 1
fi

composer create-project symfony/skeleton:"6.4.*" .

if [ $? -ne 0 ]; then
    print_error "Error creating Symfony project"
    exit 1
fi

# Install webapp dependencies
print_message "Installing webapp dependencies..."
composer require webapp

if [ $? -ne 0 ]; then
    print_error "Error installing webapp dependencies"
    exit 1
fi

# Configure database
print_message "Configuring database..."
cat > .env << EOL
###> doctrine/doctrine-bundle ###
DATABASE_URL="mysql://root:${MYSQL_ROOT_PASSWORD}@127.0.0.1:3306/${DB_NAME}?serverVersion=8.0.32&charset=utf8mb4"
###< doctrine/doctrine-bundle ###
EOL

# Create database
print_message "Creating database..."
mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
php bin/console doctrine:database:create --if-not-exists

if [ $? -ne 0 ]; then
    print_error "Error creating database"
    exit 1
fi

# Install assets
print_message "Installing assets..."
php bin/console assets:install public

# Configure permissions
print_message "Configuring permissions..."
chmod -R 777 var/cache var/log

print_message "Installation completed successfully!"

# Offer to start the server
print_question "Do you want to start the development server now? (y/n)"
read -r start_server

if [[ "$start_server" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    print_message "Starting development server..."
    print_message "The site will be accessible at: http://${DB_NAME}.localhost:8000"
    print_message "Press Ctrl+C to stop the server"
    cd "$PROJECT_DIR" && symfony server:start --host=${DB_NAME}.localhost
else
    print_message "To start the server later, run:"
    print_message "cd $PROJECT_DIR && symfony server:start --host=${DB_NAME}.localhost"
    print_message "The site will then be accessible at: http://${DB_NAME}.localhost:8000"
fi 