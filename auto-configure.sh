#!/bin/bash
# scripts/auto-configure.sh
# Auto-detect server resources and generate optimized configurations

set -euo pipefail

# Output colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_step() { echo -e "${PURPLE}🔧 $1${NC}"; }

# Detect OS
detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        log_error "Cannot detect operating system"
        exit 1
    fi
    
    log_info "Detected OS: $OS $OS_VERSION"
}

# Install Docker on different OS
install_docker() {
    log_step "Installing Docker..."
    
    case $OS in
        ubuntu|debian)
            # Remove old versions
            apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
            
            # Update package index
            apt-get update
            apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
            
            # Add Docker's official GPG key
            curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            
            # Set up stable repository
            echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$OS $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            # Install Docker Engine
            apt-get update
            apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
            
        centos|rhel|fedora)
            # Remove old versions
            yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true
            
            # Install required packages
            yum install -y yum-utils device-mapper-persistent-data lvm2
            
            # Add Docker repository
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            
            # Install Docker
            yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
            
        *)
            log_error "Unsupported operating system: $OS"
            log_info "Please install Docker manually from https://docs.docker.com/engine/install/"
            exit 1
            ;;
    esac
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    # Add current user to docker group (if not root)
    if [ "$(id -u)" -ne 0 ]; then
        usermod -aG docker $USER
        log_warning "You need to log out and back in for Docker group membership to take effect"
    fi
    
    log_success "Docker installed successfully"
}

# Install Docker Compose (standalone version as fallback)
install_docker_compose() {
    log_step "Installing Docker Compose..."
    
    # Check if docker compose plugin is available
    if docker compose version &> /dev/null; then
        log_success "Docker Compose plugin already available"
        return 0
    fi
    
    # Install standalone Docker Compose
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
    curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    log_success "Docker Compose installed successfully"
}

# Check requirements
# Enhanced requirements check with auto-installation
check_requirements() {
    log_info "Checking and installing requirements..."
    
    # Detect OS first
    detect_os
    
    # Check if running as root for installation
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script requires root privileges for installation. Please run with sudo."
        exit 1
    fi
    
    # Check and install Docker
    if ! command -v docker &> /dev/null; then
        log_warning "Docker is not installed. Installing..."
        install_docker
    else
        log_success "Docker is already installed"
        # Ensure Docker is running
        if ! systemctl is-active --quiet docker; then
            systemctl start docker
        fi
    fi
    
    # Check and install Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_warning "Docker Compose is not installed. Installing..."
        install_docker_compose
    else
        log_success "Docker Compose is already installed"
    fi
    
    # Install additional required tools
    log_step "Installing additional tools..."
    case $OS in
        ubuntu|debian)
            apt-get update
            apt-get install -y curl wget openssl net-tools htop
            ;;
        centos|rhel|fedora)
            yum install -y curl wget openssl net-tools htop
            ;;
    esac
    
    log_success "All requirements satisfied"
}

# Generate strong password
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-24
}

# Enhanced domain validation
validate_domain() {
    local domain=$1
    
    # Allow localhost for development
    if [[ "$domain" == "localhost" ]]; then
        return 0
    fi
    
    # Basic domain format validation
    if [[ ! $domain =~ ^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$ ]]; then
        log_error "Invalid domain format: $domain"
        return 1
    fi
    
    # Check if domain resolves (optional)
    if command -v dig &> /dev/null; then
        if ! dig +short "$domain" &> /dev/null; then
            log_warning "Domain $domain might not resolve properly"
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                return 1
            fi
        fi
    fi
    
    return 0
}

# Enhanced email validation
validate_email() {
    local email="$1"
    if [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+\.)+[A-Za-z]{2,}$ ]]; then
        log_error "Invalid email format: $email"
        return 1
    fi
    return 0
}

# Enhanced user input with better defaults
get_user_input() {
    log_info "🔧 Starting interactive configuration..."
    echo
    
    # Domain
    while true; do
        read -p "🌐 Domain name (default: localhost): " DOMAIN_NAME
        DOMAIN_NAME=${DOMAIN_NAME:-localhost}
        if validate_domain "$DOMAIN_NAME"; then
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
    
    # Database configuration
    echo
    log_info "🗃️ Database Configuration"
    read -p "MySQL username (default: app_user): " MYSQL_USER
    MYSQL_USER=${MYSQL_USER:-app_user}
    
    read -p "MySQL database name (default: app_database): " MYSQL_DATABASE
    MYSQL_DATABASE=${MYSQL_DATABASE:-app_database}
    
    # Generate passwords
    log_info "🔐 Generating secure passwords..."
    MYSQL_ROOT_PASSWORD=$(generate_password 24)
    MYSQL_PASSWORD=$(generate_password 24)
    
    # Show generated passwords
    log_success "Generated passwords:"
    echo "  - MySQL Root: $MYSQL_ROOT_PASSWORD"
    echo "  - MySQL App: $MYSQL_PASSWORD"
    echo
}

# Detect system resources
detect_system_resources() {
    log_info "🔍 Detecting system resources and performance..."
    
    # Memory detection
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_RAM_GB=$((TOTAL_RAM_KB / 1024 / 1024))
    AVAILABLE_RAM_KB=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    AVAILABLE_RAM_GB=$((AVAILABLE_RAM_KB / 1024 / 1024))
    
    # CPU detection
    CPU_CORES=$(nproc)
    CPU_MODEL=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
    
    # Disk detection
    AVAILABLE_DISK_GB=$(df -BG / | tail -1 | awk '{print $4}' | sed 's/G//')
    TOTAL_DISK_GB=$(df -BG / | tail -1 | awk '{print $2}' | sed 's/G//')
    
    # Network detection
    NETWORK_INTERFACES=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -3 | tr '\n' ' ')
    
    # Load average
    LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    
    log_success "📊 System Information:"
    echo "  - CPU: $CPU_MODEL ($CPU_CORES cores)"
    echo "  - Total RAM: ${TOTAL_RAM_GB}GB (Available: ${AVAILABLE_RAM_GB}GB)"
    echo "  - Disk: ${AVAILABLE_DISK_GB}GB available of ${TOTAL_DISK_GB}GB total"
    echo "  - Network: $NETWORK_INTERFACES"
    echo "  - Load Average: $LOAD_AVG"
    echo
    
    # System requirements check
    if [ $TOTAL_RAM_GB -lt 1 ]; then
        log_error "Minimum 1GB RAM is required for stable operation."
        exit 1
    fi
    
    if [ $AVAILABLE_DISK_GB -lt 5 ]; then
        log_warning "Low disk space (less than 5GB available)"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    if [ $CPU_CORES -lt 2 ]; then
        log_warning "Single CPU core detected. Performance may be limited."
    fi
}

# Calculate optimal settings
calculate_optimal_settings() {
    log_info "⚙️ Calculating optimal settings based on system resources..."
    
    # Calculate MySQL buffer pool (50-70% of available RAM)
    MYSQL_BUFFER_POOL_MB=$((AVAILABLE_RAM_GB * 1024 * 60 / 100))
    
    # Calculate PHP memory limit (20-30% of available RAM)
    PHP_MEMORY_LIMIT_MB=$((AVAILABLE_RAM_GB * 1024 * 25 / 100))
    
    # Performance tier based on available RAM
    if [ $AVAILABLE_RAM_GB -le 1 ]; then
        # Minimal tier
        PERFORMANCE_TIER="Minimal"
        MYSQL_MAX_CONNECTIONS=25
        PHP_FPM_MAX_CHILDREN=5
        PHP_FPM_START_SERVERS=2
        PHP_FPM_MIN_SPARE=1
        PHP_FPM_MAX_SPARE=3
        NGINX_WORKER_CONNECTIONS=512
        OPCACHE_MEMORY=32
        REDIS_MEMORY=32
        PHP_UPLOAD_MAX_SIZE="50M"
        PHP_POST_MAX_SIZE="50M"
    elif [ $AVAILABLE_RAM_GB -le 2 ]; then
        # Basic tier
        PERFORMANCE_TIER="Basic"
        MYSQL_MAX_CONNECTIONS=50
        PHP_FPM_MAX_CHILDREN=10
        PHP_FPM_START_SERVERS=3
        PHP_FPM_MIN_SPARE=2
        PHP_FPM_MAX_SPARE=5
        NGINX_WORKER_CONNECTIONS=1024
        OPCACHE_MEMORY=64
        REDIS_MEMORY=64
        PHP_UPLOAD_MAX_SIZE="100M"
        PHP_POST_MAX_SIZE="100M"
    elif [ $AVAILABLE_RAM_GB -le 4 ]; then
        # Standard tier
        PERFORMANCE_TIER="Standard"
        MYSQL_MAX_CONNECTIONS=100
        PHP_FPM_MAX_CHILDREN=20
        PHP_FPM_START_SERVERS=5
        PHP_FPM_MIN_SPARE=4
        PHP_FPM_MAX_SPARE=10
        NGINX_WORKER_CONNECTIONS=2048
        OPCACHE_MEMORY=128
        REDIS_MEMORY=128
        PHP_UPLOAD_MAX_SIZE="200M"
        PHP_POST_MAX_SIZE="200M"
    elif [ $AVAILABLE_RAM_GB -le 8 ]; then
        # Enhanced tier
        PERFORMANCE_TIER="Enhanced"
        MYSQL_MAX_CONNECTIONS=200
        PHP_FPM_MAX_CHILDREN=40
        PHP_FPM_START_SERVERS=8
        PHP_FPM_MIN_SPARE=6
        PHP_FPM_MAX_SPARE=20
        NGINX_WORKER_CONNECTIONS=4096
        OPCACHE_MEMORY=256
        REDIS_MEMORY=256
        PHP_UPLOAD_MAX_SIZE="500M"
        PHP_POST_MAX_SIZE="500M"
    else
        # High-performance tier
        PERFORMANCE_TIER="High-Performance"
        MYSQL_MAX_CONNECTIONS=500
        PHP_FPM_MAX_CHILDREN=80
        PHP_FPM_START_SERVERS=16
        PHP_FPM_MIN_SPARE=12
        PHP_FPM_MAX_SPARE=40
        NGINX_WORKER_CONNECTIONS=8192
        OPCACHE_MEMORY=512
        REDIS_MEMORY=512
        PHP_UPLOAD_MAX_SIZE="1G"
        PHP_POST_MAX_SIZE="1G"
    fi
    
    # Nginx worker processes (equal to CPU cores, max 8)
    NGINX_WORKER_PROCESSES=$CPU_CORES
    if [ $NGINX_WORKER_PROCESSES -gt 8 ]; then
        NGINX_WORKER_PROCESSES=8
    fi
    
    log_success "⚙️ Performance Tier: $PERFORMANCE_TIER"
    echo "  - MySQL Buffer Pool: ${MYSQL_BUFFER_POOL_MB}MB"
    echo "  - PHP Memory Limit: ${PHP_MEMORY_LIMIT_MB}MB"
    echo "  - Max DB Connections: ${MYSQL_MAX_CONNECTIONS}"
    echo "  - PHP-FPM Max Children: ${PHP_FPM_MAX_CHILDREN}"
    echo "  - Nginx Workers: ${NGINX_WORKER_PROCESSES} (${NGINX_WORKER_CONNECTIONS} connections each)"
    echo "  - OPcache Memory: ${OPCACHE_MEMORY}MB"
    echo "  - Redis Memory: ${REDIS_MEMORY}MB"
    echo "  - Max Upload Size: ${PHP_UPLOAD_MAX_SIZE}"
    echo
}

# Generate .env file
generate_env_file() {
    log_info "📄 Creating .env file..."
    
    cat > .env << EOF
# =================================================================
# Auto-generated configuration file
# Generated on: $(date)
# System: ${TOTAL_RAM_GB}GB RAM, ${CPU_CORES} CPU cores
# Performance Tier: ${PERFORMANCE_TIER}
# =================================================================

COMPOSE_PROJECT_NAME=myapp
# Application Settings
APP_ENV=production
APP_DEBUG=false
APP_URL=https://${DOMAIN_NAME}
APP_KEY=$(openssl rand -base64 32)

# Security
SECURE_KEY=$(openssl rand -hex 32)

# Database Configuration
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
MYSQL_DATABASE=${MYSQL_DATABASE}
MYSQL_USER=${MYSQL_USER}
MYSQL_PASSWORD=${MYSQL_PASSWORD}

# MySQL Configuration
MYSQL_INNODB_BUFFER_POOL_SIZE=${MYSQL_BUFFER_POOL_MB}M
MYSQL_MAX_CONNECTIONS=${MYSQL_MAX_CONNECTIONS}
MYSQL_QUERY_CACHE_SIZE=32M
MYSQL_TMP_TABLE_SIZE=64M
MYSQL_MAX_HEAP_TABLE_SIZE=64M
MYSQL_INNODB_LOG_FILE_SIZE=64M
MYSQL_INNODB_LOG_BUFFER_SIZE=8M

# PHP Configuration
PHP_MEMORY_LIMIT=${PHP_MEMORY_LIMIT_MB}M
PHP_MAX_EXECUTION_TIME=21600
PHP_UPLOAD_MAX_FILESIZE=${PHP_UPLOAD_MAX_SIZE}
PHP_POST_MAX_SIZE=${PHP_POST_MAX_SIZE}
PHP_MAX_INPUT_VARS=3000

# OPcache Configuration
PHP_OPCACHE_MEMORY=${OPCACHE_MEMORY}
PHP_OPCACHE_MAX_FILES=20000
PHP_OPCACHE_JIT_BUFFER=128M

# PHP-FPM Configuration
PHP_FPM_MAX_CHILDREN=${PHP_FPM_MAX_CHILDREN}
PHP_FPM_START_SERVERS=${PHP_FPM_START_SERVERS}
PHP_FPM_MIN_SPARE_SERVERS=${PHP_FPM_MIN_SPARE}
PHP_FPM_MAX_SPARE_SERVERS=${PHP_FPM_MAX_SPARE}
PHP_FPM_MAX_REQUESTS=1000
PHP_FPM_PROCESS_IDLE_TIMEOUT=10s

# Nginx Configuration
NGINX_WORKER_PROCESSES=${NGINX_WORKER_PROCESSES}
NGINX_WORKER_CONNECTIONS=${NGINX_WORKER_CONNECTIONS}
NGINX_CLIENT_MAX_BODY_SIZE=${PHP_UPLOAD_MAX_SIZE}

# Redis Configuration
REDIS_MEMORY=${REDIS_MEMORY}M
REDIS_MAXMEMORY_POLICY=allkeys-lru

# Domain & SSL Info
DOMAIN_NAME=${DOMAIN_NAME}
EMAIL_FOR_SSL=${EMAIL_FOR_SSL}
EOF

    chmod 600 .env
    log_success ".env file created successfully."
}

# Generate Nginx config
generate_nginx_config() {
mkdir -p nginx/conf.d
cat > nginx/nginx.conf << EOF
# =================================================================
# Auto-generated Nginx configuration
# Generated on: $(date)
# Performance Tier: ${PERFORMANCE_TIER}
# =================================================================

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
    server_name t.miladrajabi.com;
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        try_files \$uri =404;
    }
    
    location / {
        root /var/www/html;
        index index.php index.html index.htm;
	proxy_redirect off;
	proxy_http_version 1.1;
	proxy_set_header Upgrade \$http_upgrade;
	proxy_set_header Connection "upgrade";
	proxy_set_header Host \$http_host;
	try_files \$uri \$uri/ /index.php?\$query_string;
	}
    
    location ~ \.php$ {
        root /var/www/html;
    	proxy_redirect off;
	proxy_http_version 1.1;
	proxy_set_header Upgrade \$http_upgrade;
	proxy_set_header Connection "upgrade";
	proxy_set_header Host \$http_host;
        try_files \$uri \$uri/ /index.php?\$query_string;
        fastcgi_pass php:9000;
        include fastcgi_params;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
        fastcgi_busy_buffers_size 256k;
    }
}
EOF
    
    log_success "Nginx configuration generated successfully"
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
    clear

    echo "🚀 Docker NPM Auto Configuration System"
    echo "================================================"
    echo

    echo "nameserver 1.1.1.1" > /etc/resolv.conf

    echo "nameserver 1.0.0.1" >> /etc/resolv.conf

    wget -N --no-check-certificate https://github.com/teddysun/across/raw/master/bbr.sh && chmod +x bbr.sh && bash bbr.sh

    sleep 2

    apt-get update -y && apt-get upgrade -y

    rm -fr install_bbr.log
    rm -fr bbr.sh

    check_requirements
    sleep 1
    get_user_input
    sleep 1
    detect_system_resources
    sleep 1
    calculate_optimal_settings
    sleep 1
    create_directories
    sleep 1
    generate_env_file
    sleep 1
    generate_mysql_config
    sleep 1
    generate_nginx_config
    sleep 1

    echo
    log_success "✅ Auto configuration complete!"
    echo
    echo "📁 Files generated:"
    echo "  - .env"
    echo "  - data/my.cnf"
    echo "  - nginx/nginx.conf & nginx/conf.d/default.conf"
    echo "📋 Next steps:"
    echo "1. Run: docker compose up -d"
    echo "2. Run: bash ssl-setup.sh"
    echo "3. Test the system"
    echo
    echo "🔐 Important information (save it):"
    echo "   Project configured for: https://${DOMAIN_NAME}"
    echo "   MySQL Root: $MYSQL_ROOT_PASSWORD"
    echo "   MySQL App: $MYSQL_PASSWORD"
    echo
}

# Script Execution
main "$@"
