#!/bin/bash
# scripts/auto-configure.sh
# Auto-detect server resources and generate optimized configurations

set -euo pipefail

# Output colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Check requirements
check_requirements() {
    log_info "Checking requirements..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed."
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_error "Docker Compose is not installed."
        exit 1
    fi
    
    if [ "$(id -u)" -eq 0 ]; then
        log_warning "Running as root is not recommended."
        read -p "Do you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Generate strong password
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-24
}

# Input validation
validate_domain() {
    local domain=$1
    if [[ ! $domain =~ ^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$ ]]; then
        log_error "Invalid domain format"
        return 1
    fi
}

validate_email() {
    local email="$1"
    if [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+\.)+[A-Za-z]{2,}$ ]]; then
        log_error "Invalid domain format."
        return 1
    fi
}

# Get user input with validation
get_user_input() {
    log_info "🔧 Starting auto-configuration..."
    echo
    
    # Domain
    while true; do
        read -p "🌐 Domain name (e.g., example.com): " DOMAIN_NAME
        if [ -z "$DOMAIN_NAME" ]; then
            DOMAIN_NAME="localhost"
            break
        elif validate_domain "$DOMAIN_NAME"; then
            break
        fi
    done
    
    # Email for SSL
    while true; do
        read -p "📧 Email for SSL (default: admin@$DOMAIN_NAME): " EMAIL_FOR_SSL
        EMAIL_FOR_SSL=${EMAIL_FOR_SSL:-admin@$DOMAIN_NAME}
        if validate_email "$EMAIL_FOR_SSL"; then
            break
        fi
    done
    
    # Passwords
    log_info "🔐 Generating secure passwords..."
    MYSQL_ROOT_PASSWORD=$(generate_password)
    MYSQL_PASSWORD=$(generate_password)
    
    # MySQL user and database
    read -p "🧰 MySQL username (default: app_user): " MYSQL_USER
    MYSQL_USER=${MYSQL_USER:-app_user}
    
    read -p "🗃️  MySQL database name (default: app_database): " MYSQL_DATABASE
    MYSQL_DATABASE=${MYSQL_DATABASE:-app_database}
    
    # Show generated passwords
    log_success "Generated passwords:"
    echo "  - MySQL Root: $MYSQL_ROOT_PASSWORD"
    echo "  - MySQL App: $MYSQL_PASSWORD"
    echo
}

# Detect system resources
detect_system_resources() {
    log_info "🔍 Detecting system resources..."
    
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_RAM_GB=$((TOTAL_RAM_KB / 1024 / 1024))
    CPU_CORES=$(nproc)
    AVAILABLE_DISK_GB=$(df -BG / | tail -1 | awk '{print $4}' | sed 's/G//')
    
    log_success "📊 System Information:"
    echo "  - RAM: ${TOTAL_RAM_GB}GB"
    echo "  - CPU Cores: ${CPU_CORES}"
    echo "  - Available Disk: ${AVAILABLE_DISK_GB}GB"
    echo
    
    if [ $TOTAL_RAM_GB -lt 1 ]; then
        log_error "Minimum 1GB RAM is required."
        exit 1
    fi
    
    if [ $AVAILABLE_DISK_GB -lt 5 ]; then
        log_warning "Low disk space (less than 5GB)"
    fi
}

# Calculate optimal settings
calculate_optimal_settings() {
    log_info "⚙️  Calculating optimal settings..."
    
    MYSQL_BUFFER_POOL_MB=$((TOTAL_RAM_GB * 1024 * 50 / 100))
    PHP_MEMORY_LIMIT_MB=$((TOTAL_RAM_GB * 1024 * 30 / 100))
    
    if [ $TOTAL_RAM_GB -le 2 ]; then
        MYSQL_MAX_CONNECTIONS=50
        PHP_FPM_MAX_CHILDREN=10
        PHP_FPM_START_SERVERS=2
        PHP_FPM_MIN_SPARE=2
        PHP_FPM_MAX_SPARE=5
        NGINX_WORKER_CONNECTIONS=1024
        OPCACHE_MEMORY=64
        REDIS_MEMORY=64
    elif [ $TOTAL_RAM_GB -le 4 ]; then
        MYSQL_MAX_CONNECTIONS=100
        PHP_FPM_MAX_CHILDREN=20
        PHP_FPM_START_SERVERS=4
        PHP_FPM_MIN_SPARE=4
        PHP_FPM_MAX_SPARE=10
        NGINX_WORKER_CONNECTIONS=2048
        OPCACHE_MEMORY=128
        REDIS_MEMORY=128
    elif [ $TOTAL_RAM_GB -le 8 ]; then
        MYSQL_MAX_CONNECTIONS=200
        PHP_FPM_MAX_CHILDREN=40
        PHP_FPM_START_SERVERS=8
        PHP_FPM_MIN_SPARE=8
        PHP_FPM_MAX_SPARE=20
        NGINX_WORKER_CONNECTIONS=4096
        OPCACHE_MEMORY=256
        REDIS_MEMORY=256
    else
        MYSQL_MAX_CONNECTIONS=500
        PHP_FPM_MAX_CHILDREN=80
        PHP_FPM_START_SERVERS=16
        PHP_FPM_MIN_SPARE=16
        PHP_FPM_MAX_SPARE=40
        NGINX_WORKER_CONNECTIONS=8192
        OPCACHE_MEMORY=512
        REDIS_MEMORY=512
    fi
    
    NGINX_WORKER_PROCESSES=$CPU_CORES
    
    if [ $TOTAL_RAM_GB -ge 8 ]; then
        PHP_UPLOAD_MAX_SIZE="500M"
        PHP_POST_MAX_SIZE="500M"
    elif [ $TOTAL_RAM_GB -ge 4 ]; then
        PHP_UPLOAD_MAX_SIZE="200M"
        PHP_POST_MAX_SIZE="200M"
    else
        PHP_UPLOAD_MAX_SIZE="100M"
        PHP_POST_MAX_SIZE="100M"
    fi
    
    log_success "⚙️  Calculated optimal values:"
    echo "  - MySQL Buffer Pool: ${MYSQL_BUFFER_POOL_MB}MB"
    echo "  - PHP Memory: ${PHP_MEMORY_LIMIT_MB}MB"
    echo "  - Max Connections: ${MYSQL_MAX_CONNECTIONS}"
    echo "  - PHP-FPM Children: ${PHP_FPM_MAX_CHILDREN}"
    echo "  - OPcache: ${OPCACHE_MEMORY}MB"
    echo
}

# Generate .env file
generate_env_file() {
    log_info "📄 Creating .env file..."
    
    cat > .env << EOF
# Automatically generated on: $(date)
# System: ${TOTAL_RAM_GB}GB RAM, ${CPU_CORES} CPU cores

COMPOSE_PROJECT_NAME=myapp

# Database Information
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
MYSQL_DATABASE=${MYSQL_DATABASE}
MYSQL_USER=${MYSQL_USER}
MYSQL_PASSWORD=${MYSQL_PASSWORD}

# MySQL Settings
MYSQL_INNODB_BUFFER_POOL_SIZE=${MYSQL_BUFFER_POOL_MB}M
MYSQL_MAX_CONNECTIONS=${MYSQL_MAX_CONNECTIONS}
MYSQL_QUERY_CACHE_SIZE=32M
MYSQL_TMP_TABLE_SIZE=64M
MYSQL_MAX_HEAP_TABLE_SIZE=64M

# PHP Settings
PHP_MEMORY_LIMIT=${PHP_MEMORY_LIMIT_MB}M
PHP_MAX_EXECUTION_TIME=300
PHP_UPLOAD_MAX_FILESIZE=${PHP_UPLOAD_MAX_SIZE}
PHP_POST_MAX_SIZE=${PHP_POST_MAX_SIZE}
PHP_MAX_INPUT_VARS=3000

# OPcache Settings
PHP_OPCACHE_MEMORY=${OPCACHE_MEMORY}
PHP_OPCACHE_MAX_FILES=20000
PHP_OPCACHE_JIT_BUFFER=128M

# PHP-FPM Settings
PHP_FPM_MAX_CHILDREN=${PHP_FPM_MAX_CHILDREN}
PHP_FPM_START_SERVERS=${PHP_FPM_START_SERVERS}
PHP_FPM_MIN_SPARE_SERVERS=${PHP_FPM_MIN_SPARE}
PHP_FPM_MAX_SPARE_SERVERS=${PHP_FPM_MAX_SPARE}
PHP_FPM_MAX_REQUESTS=1000

# Nginx Settings
NGINX_WORKER_PROCESSES=${NGINX_WORKER_PROCESSES}
NGINX_WORKER_CONNECTIONS=${NGINX_WORKER_CONNECTIONS}

# Redis Settings
REDIS_MEMORY=${REDIS_MEMORY}M

# Domain & SSL Info
DOMAIN_NAME=${DOMAIN_NAME}
EMAIL_FOR_SSL=${EMAIL_FOR_SSL}

# Application Settings
APP_ENV=production
APP_DEBUG=false
APP_URL=https://${DOMAIN_NAME}
APP_KEY=$(openssl rand -base64 32)

# Security
SECURE_KEY=$(openssl rand -hex 32)
EOF

    chmod 600 .env
    log_success ".env file created successfully."
}

# Generate Nginx config
generate_nginx_config() {
mkdir -p nginx/conf.d
cat > nginx/nginx.conf << EOF
# Auto-generated Nginx configuration
# Generated on: $(date)

user nginx;
worker_processes ${NGINX_WORKER_PROCESSES};
worker_cpu_affinity auto;
error_log /var/log/nginx/error.log notice;
pid /var/run/nginx.pid;

events {
    worker_connections ${NGINX_WORKER_CONNECTIONS};
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    keepalive_requests 1000;
    types_hash_max_size 2048;
    server_tokens off;

    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript application/json application/javascript application/xml+rss application/atom+xml image/svg+xml;

    client_body_buffer_size 128k;
    client_max_body_size ${PHP_UPLOAD_MAX_SIZE};
    client_header_buffer_size 1k;
    large_client_header_buffers 4 4k;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;

    include /etc/nginx/conf.d/*.conf;
}
EOF

cat > nginx/conf.d/default.conf << EOF
server {
    listen 80;
    server_name ${DOMAIN_NAME};
    
    # مسیر تایید Let's Encrypt
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    # redirect همه چیز به HTTPS
    location / {
        return 301 https://$server_name$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name ${DOMAIN_NAME};

    root /var/www/html;
    index index.php index.html;

    ssl_certificate /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    location ~* \.(jpg|jpeg|png|gif|ico|css|js|pdf|txt|woff|svg|ttf|eot|woff2)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_pass php:9000;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
        fastcgi_busy_buffers_size 256k;
    }

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ /\. {
        deny all;
        access_log off;
    }
}
EOF
}

# Create necessary directories
create_directories() {
    log_info "📁 Creating required directories..."

    directories=(
        "data"
        "logs/nginx"
        "logs/php"
        "nginx"
        "ssl"
    )
    
    for dir in "${directories[@]}"; do
        mkdir -p "$dir"
        log_success "Directories $dir created!"
    done

    chmod 755 src
    chmod 700 data
    chmod 755 logs
}

# Generate MySQL configuration
generate_mysql_config() {
   log_info "⚙️ Creating MySQL config file..."
    
    cat > data/my.cnf << EOF
# Automatically generated on: $(date)

[mysqld]
# Memory Settings
innodb_buffer_pool_size = ${MYSQL_BUFFER_POOL_MB}M
innodb_log_file_size = 128M
innodb_log_buffer_size = 16M

# Performance
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT
innodb_file_per_table = 1
innodb_io_capacity = 200

# Connections
max_connections = ${MYSQL_MAX_CONNECTIONS}
max_connect_errors = 1000
thread_cache_size = 50
table_open_cache = 2000

# Query Cache
query_cache_type = 1
query_cache_size = 32M
query_cache_limit = 2M

# Temporary Tables
tmp_table_size = 64M
max_heap_table_size = 64M

# MyISAM
key_buffer_size = 32M
myisam_sort_buffer_size = 8M

# Binary Logging
binlog_cache_size = 1M
max_binlog_cache_size = 8M

# Character Set
character_set_server = utf8mb4
collation_server = utf8mb4_unicode_ci

# Security
local_infile = 0
symbolic_links = 0

# Monitoring
performance_schema = ON
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 2

[mysql]
default_character_set = utf8mb4

[client]
default_character_set = utf8mb4
EOF
    
   log_success "MySQL config (my.cnf) created."
}

# Main Execution
main() {
    echo "🚀 Docker LAMP Stack Auto Configuration System"
    echo "================================================"
    echo

    check_requirements
    get_user_input
    detect_system_resources
    calculate_optimal_settings
    create_directories
    generate_env_file
    generate_mysql_config
    generate_nginx_config

    echo
    log_success "✅ Auto configuration complete!"
    echo
    echo "📁 Files generated:"
    echo "  - .env"
    echo "  - data/my.cnf"
    echo "  - nginx/nginx.conf & nginx/conf.d/default.conf"
    echo "📋 Next steps:"
    echo "1. Get ssl for domain"
    echo "2. Run: docker compose up -d"
    echo "3. Test the system"
    echo
    echo "🔐 Important information (save it):"
    echo "   MySQL Root: $MYSQL_ROOT_PASSWORD"
    echo "   MySQL App: $MYSQL_PASSWORD"
    echo
}

# Script Execution
main "$@"
