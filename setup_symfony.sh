#!/bin/bash

# Couleurs pour les messages
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonction pour afficher les messages
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

# Fonction pour vérifier si un répertoire est vide
is_dir_empty() {
    if [ -d "$1" ] && [ -n "$(ls -A "$1" 2>/dev/null)" ]; then
        return 1
    fi
    return 0
}

# Définir le répertoire de base
BASE_DIR="/home/vagrant"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Demander le mot de passe root de MySQL
print_question "Entrez le mot de passe root de MySQL :"
read -s MYSQL_ROOT_PASSWORD
echo "" # Pour le retour à la ligne après la saisie du mot de passe

# Demander le répertoire d'installation
print_question "Voulez-vous installer le projet dans le répertoire courant ? (y/n)"
read -r response

if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    PROJECT_DIR="$SCRIPT_DIR"
    print_message "Installation dans le répertoire courant : $PROJECT_DIR"
else
    print_question "Entrez le nom du répertoire pour le projet (chemin relatif ou absolu) :"
    read -r PROJECT_DIR
    
    # Si le chemin est relatif, le convertir en absolu
    if [[ ! "$PROJECT_DIR" = /* ]]; then
        PROJECT_DIR="$BASE_DIR/$PROJECT_DIR"
    fi
    
    # Si le répertoire existe, le supprimer
    if [ -d "$PROJECT_DIR" ]; then
        print_warning "Le répertoire $PROJECT_DIR existe déjà."
        print_warning "Suppression du répertoire existant..."
        rm -Rf "$PROJECT_DIR"
    fi
    
    print_message "Création du répertoire $PROJECT_DIR"
    mkdir -p "$PROJECT_DIR"
fi

# Extraire le nom de la base de données du chemin du projet et le nettoyer
DB_NAME=$(basename "$PROJECT_DIR" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')
DB_TEST_NAME="${DB_NAME}_test"

# Vérifier la connexion MySQL
print_message "Vérification de la connexion MySQL..."
if ! mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1" &> /dev/null; then
    print_error "Impossible de se connecter à MySQL. Vérifiez le mot de passe root."
    exit 1
fi

# Suppression des bases de données existantes
print_warning "Vérification des bases de données existantes..."

# Fonction pour supprimer une base de données
drop_database() {
    local db_name=$1
    if mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SHOW DATABASES LIKE '$db_name'" | grep -q "$db_name"; then
        print_warning "La base de données $db_name existe."
        print_question "Voulez-vous la supprimer ? (y/n)"
        read -r drop_response
        if [[ "$drop_response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "DROP DATABASE IF EXISTS $db_name"
            print_message "Base de données $db_name supprimée."
        else
            print_error "Installation annulée. La base de données $db_name existe déjà."
            exit 1
        fi
    fi
}

# Suppression des bases de données
drop_database "$DB_NAME"
drop_database "$DB_TEST_NAME"

# Nettoyage
print_message "Nettoyage de l'environnement..."

# Suppression des fichiers temporaires dans le répertoire du projet
print_warning "Nettoyage des fichiers temporaires..."
if [ -d "$PROJECT_DIR" ]; then
    rm -f "$PROJECT_DIR/composer.lock"
    rm -f "$PROJECT_DIR/.env"
    rm -f "$PROJECT_DIR/.env.local"
    rm -f "$PROJECT_DIR/.env.test"
    rm -f "$PROJECT_DIR/.env.test.local"
fi

# Nettoyage du cache Composer
print_warning "Nettoyage du cache Composer..."
composer clear-cache

# Vérification des prérequis
print_message "Vérification des prérequis..."

# Vérifier si Composer est installé
if ! command -v composer &> /dev/null; then
    print_error "Composer n'est pas installé. Veuillez l'installer d'abord."
    exit 1
fi

# Vérifier si PHP est installé
if ! command -v php &> /dev/null; then
    print_error "PHP n'est pas installé. Veuillez l'installer d'abord."
    exit 1
fi

# Vérifier si MySQL est installé
if ! command -v mysql &> /dev/null; then
    print_error "MySQL n'est pas installé. Veuillez l'installer d'abord."
    exit 1
fi

# Vérifier la version de PHP
PHP_VERSION=$(php -v | head -n 1 | cut -d " " -f 2 | cut -d "." -f 1)
if [ "$PHP_VERSION" -lt 8 ]; then
    print_error "PHP 8.0 ou supérieur est requis. Version actuelle : $(php -v | head -n 1)"
    exit 1
fi

# Création du projet Symfony
print_message "Création du projet Symfony dans $PROJECT_DIR..."
cd "$PROJECT_DIR" || exit 1

# Vérifier l'espace disque disponible
AVAILABLE_SPACE=$(df -BG "$PROJECT_DIR" | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$AVAILABLE_SPACE" -lt 1 ]; then
    print_error "Espace disque insuffisant. Au moins 1 Go est requis."
    exit 1
fi

composer create-project symfony/skeleton:"6.4.*" .

if [ $? -ne 0 ]; then
    print_error "Erreur lors de la création du projet Symfony"
    exit 1
fi

# Installation des dépendances webapp
print_message "Installation des dépendances webapp..."
composer require webapp

if [ $? -ne 0 ]; then
    print_error "Erreur lors de l'installation des dépendances webapp"
    exit 1
fi

# Configuration de la base de données
print_message "Configuration de la base de données..."
cat > .env << EOL
###> doctrine/doctrine-bundle ###
DATABASE_URL="mysql://root:${MYSQL_ROOT_PASSWORD}@127.0.0.1:3306/${DB_NAME}?serverVersion=8.0.32&charset=utf8mb4"
###< doctrine/doctrine-bundle ###
EOL

# Création de la base de données
print_message "Création de la base de données..."
mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
php bin/console doctrine:database:create --if-not-exists

if [ $? -ne 0 ]; then
    print_error "Erreur lors de la création de la base de données"
    exit 1
fi

# Installation des assets
print_message "Installation des assets..."
php bin/console assets:install public

# Configuration des permissions
print_message "Configuration des permissions..."
chmod -R 777 var/cache var/log

print_message "Installation terminée avec succès !"

# Proposer de démarrer le serveur
print_question "Voulez-vous démarrer le serveur de développement maintenant ? (y/n)"
read -r start_server

if [[ "$start_server" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    print_message "Démarrage du serveur de développement..."
    print_message "Le site sera accessible à l'adresse : http://${DB_NAME}.localhost:8000"
    print_message "Appuyez sur Ctrl+C pour arrêter le serveur"
    cd "$PROJECT_DIR" && symfony server:start --host=${DB_NAME}.localhost
else
    print_message "Pour démarrer le serveur plus tard, exécutez :"
    print_message "cd $PROJECT_DIR && symfony server:start --host=${DB_NAME}.localhost"
    print_message "Le site sera alors accessible à l'adresse : http://${DB_NAME}.localhost:8000"
fi 