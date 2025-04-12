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

# Ask for database name
print_question "Enter the name of the database to create:"
read -r DB_NAME
DB_NAME=$(echo "$DB_NAME" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')
DB_TEST_NAME="${DB_NAME}_test"

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

# Ask for Symfony version
print_question "Enter the Symfony version to install (e.g., 6.4, 7.0, latest):"
read -r SYMFONY_VERSION

# Validate Symfony version format
if [[ ! "$SYMFONY_VERSION" =~ ^[0-9]+\.[0-9]+$ ]] && [ "$SYMFONY_VERSION" != "latest" ]; then
    print_error "Invalid Symfony version format. Please use format X.Y (e.g., 6.4) or 'latest'"
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

if [ "$SYMFONY_VERSION" == "latest" ]; then
    symfony new . --webapp
else
    symfony new . --version="$SYMFONY_VERSION" --webapp
fi

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

###> symfony/framework-bundle ###
APP_ENV=prod
APP_DEBUG=0
APP_SECRET=\${APP_SECRET:-$(openssl rand -hex 32)}
###< symfony/framework-bundle ###

###> symfony/messenger ###
MESSENGER_TRANSPORT_DSN=doctrine://default
###< symfony/messenger ###
EOL

# Create .env.local file
print_message "Creating .env.local file..."
cat > .env.local << EOL
###> doctrine/doctrine-bundle ###
# Local development database configuration
DATABASE_URL="mysql://root:${MYSQL_ROOT_PASSWORD}@127.0.0.1:3306/${DB_NAME}?serverVersion=8.0.32&charset=utf8mb4"
###< doctrine/doctrine-bundle ###

###> symfony/framework-bundle ###
APP_ENV=dev
APP_DEBUG=1
APP_SECRET=\${APP_SECRET:-$(openssl rand -hex 32)}
###< symfony/framework-bundle ###

###> symfony/messenger ###
MESSENGER_TRANSPORT_DSN=doctrine://default
###< symfony/messenger ###
EOL

# Create .env.test file
print_message "Creating .env.test file..."
cat > .env.test << EOL
###> doctrine/doctrine-bundle ###
# Test environment database configuration
DATABASE_URL="mysql://root:${MYSQL_ROOT_PASSWORD}@127.0.0.1:3306/${DB_NAME}_test?serverVersion=8.0.32&charset=utf8mb4"
###< doctrine/doctrine-bundle ###

###> symfony/framework-bundle ###
APP_ENV=test
APP_DEBUG=1
APP_SECRET=\${APP_SECRET:-$(openssl rand -hex 32)}
###< symfony/framework-bundle ###

###> symfony/messenger ###
MESSENGER_TRANSPORT_DSN=doctrine://default
###< symfony/messenger ###
EOL

# Create database
print_message "Creating database..."
mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS $DB_TEST_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"

# Create database schema
print_message "Creating database schema..."
php bin/console doctrine:database:create --if-not-exists
php bin/console doctrine:schema:create

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

# Create README.md
print_message "Creating README.md file..."
cat > README.md << EOL
# Symfony Project

This is a Symfony project created using the setup_symfony script.

## Requirements

- PHP 8.0 or higher
- MySQL
- Composer

## Installation

1. Clone this repository
2. Install dependencies:
   \`\`\`bash
   composer install
   \`\`\`
3. Configure your database in \`.env\` or \`.env.local\`
4. Create the database:
   \`\`\`bash
   php bin/console doctrine:database:create
   \`\`\`
5. Run migrations if you have any:
   \`\`\`bash
   php bin/console doctrine:migrations:migrate
   \`\`\`

## Development

Start the development server:
\`\`\`bash
symfony server:start
\`\`\`

The site will be accessible at: http://localhost:8000

## Testing

Run the tests:
\`\`\`bash
php bin/phpunit
\`\`\`

## Documentation

- [Symfony Documentation](https://symfony.com/doc/current/index.html)
- [Doctrine ORM Documentation](https://www.doctrine-project.org/projects/doctrine-orm/en/current/index.html)
- [Twig Documentation](https://twig.symfony.com/doc/3.x/)
EOL

# Create .doc directory
print_message "Creating .doc directory..."
mkdir -p .doc


# Create CHANGELOG.md
print_message "Creating CHANGELOG.md file..."
cat > .doc/CHANGELOG.md << EOL
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial project setup
- Basic Symfony installation
- Database configuration
- Development environment setup
- Test environment setup

### Changed
- N/A

### Deprecated
- N/A

### Removed
- N/A

### Fixed
- N/A

### Security
- N/A
EOL

print_message "Installation completed successfully!"

# Ask if user wants to install Bootstrap
print_question "Do you want to install Bootstrap? (y/n)"
read -r INSTALL_BOOTSTRAP

if [[ "$INSTALL_BOOTSTRAP" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    print_message "Installing Bootstrap..."
    npm install bootstrap --save-dev
    
    if [ $? -ne 0 ]; then
        print_error "Error installing Bootstrap"
        exit 1
    fi
    
    print_message "Bootstrap installed successfully!"
fi

# Install Symfony Mailer
print_message "Installing Symfony Mailer..."
composer require symfony/mailer

if [ $? -ne 0 ]; then
    print_error "Error installing Symfony Mailer"
    exit 1
fi

print_message "Symfony Mailer installed successfully!"

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
