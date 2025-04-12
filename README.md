# Symfony Project Setup Script

This script automates the setup of a new Symfony project with proper database configuration and environment files.

## Prerequisites

- PHP 8.0 or higher
- MySQL
- Composer
- Git

## Usage

1. Clone this repository:
```bash
git clone https://github.com/jms212004/setup_symfony.git
cd setup_symfony
```

2. Make the script executable:
```bash
chmod +x setup_symfony.sh
```

3. Run the script:
```bash
./setup_symfony.sh
```

4. Follow the prompts:
   - Enter MySQL root password
   - Enter the name of the database to create
   - Choose installation directory (current or specify a new one)

## What the Script Does

1. **Environment Setup**:
   - Creates `.env` file for production configuration
   - Creates `.env.local` for local development
   - Creates `.env.test` for test environment

2. **Database Configuration**:
   - Creates main database with specified name
   - Creates test database with `_test` suffix
   - Sets up proper character set and collation
   - Creates database schema

3. **Project Setup**:
   - Installs Symfony skeleton
   - Installs webapp dependencies
   - Configures proper permissions
   - Installs assets

4. **Development Server**:
   - Option to start the development server
   - Accessible at `http://[database_name].localhost:8000`

## Environment Files

- `.env`: Main configuration file for production
- `.env.local`: Local development configuration (not tracked by git)
- `.env.test`: Test environment configuration

## Notes

- The script will clean up any existing project files in the target directory
- It will prompt before dropping existing databases
- All databases are created with UTF8MB4 character set
- The development server can be started later using:
  ```bash
  cd [project_directory] && symfony server:start --host=[database_name].localhost
  ```

## Troubleshooting

If you encounter any issues:
1. Ensure all prerequisites are installed
2. Check MySQL connection with provided credentials
3. Verify sufficient disk space (minimum 1GB required)
4. Check file permissions in the project directory
