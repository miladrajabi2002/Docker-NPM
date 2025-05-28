#!/bin/bash
# php/scripts/entrypoint.sh
# Enhanced PHP-FPM entrypoint with proper configuration

set -euo pipefail

# رنگ‌بندی خروجی
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_required_vars() {
    local required_vars=(
        "MYSQL_HOST"
        "MYSQL_DATABASE"
        "MYSQL_USER"
        "MYSQL_PASSWORD"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            log_error "Variable $var not set"
            exit 1
        fi
    done
}

echo "🔧 Configuring PHP environment..."

# تولید کانفیگ PHP
generate_php_config() {
    log_info "📝 Generating PHP config..."
    
    cat > /usr/local/etc/php/conf.d/99-runtime.ini << EOF
; Runtime PHP Configuration
; Generated on: $(date)

[PHP]
engine = On
short_open_tag = Off
precision = 14
output_buffering = 4096
zlib.output_compression = Off
implicit_flush = Off
serialize_precision = -1

; Security
disable_functions = exec,passthru,shell_exec,system,proc_open,popen,show_source
expose_php = Off
allow_url_fopen = On
allow_url_include = Off

; Resource Limits
max_execution_time = ${PHP_MAX_EXECUTION_TIME:-300}
max_input_time = ${PHP_MAX_EXECUTION_TIME:-300}
memory_limit = ${PHP_MEMORY_LIMIT:-512M}
max_input_vars = ${PHP_MAX_INPUT_VARS:-3000}

; Error Handling
error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT
display_errors = Off
display_startup_errors = Off
log_errors = On
log_errors_max_len = 1024
error_log = /var/log/php/php-error.log

; Data Handling
variables_order = "GPCS"
request_order = "GP"
register_argc_argv = Off
auto_globals_jit = On
post_max_size = ${PHP_POST_MAX_SIZE:-100M}
default_charset = "UTF-8"

; File Uploads
file_uploads = On
upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE:-100M}
max_file_uploads = 20
upload_tmp_dir = /tmp/php

; MySQL Native Driver
mysqli.default_host = ${MYSQL_HOST}
mysqli.default_user = ${MYSQL_USER}
mysqli.default_pw = ${MYSQL_PASSWORD}

; Sessions
session.save_handler = files
session.save_path = "/tmp/php/sessions"
session.use_strict_mode = 1
session.use_cookies = 1
session.use_only_cookies = 1
session.name = PHPSESSID
session.cookie_lifetime = 0
session.cookie_path = /
session.cookie_domain =
session.cookie_httponly = 1
session.cookie_secure = 0
session.cookie_samesite = Strict
session.gc_maxlifetime = 1440
session.gc_probability = 1
session.gc_divisor = 100

; Date
date.timezone = Asia/Tehran

; Realpath Cache
realpath_cache_size = 4096K
realpath_cache_ttl = 600
EOF
    
    log_success "کانفیگ PHP تولید شد"
}

# تولید کانفیگ OPcache
generate_opcache_config() {
    log_info "⚡ Generating OPcache config..."

    rm -fr /usr/local/etc/php/conf.d/docker-php-ext-opcache.ini
    
    cat > /usr/local/etc/php/conf.d/10-opcache.ini << EOF
; OPcache Configuration
; Generated on: $(date)

[opcache]
zend_extension=opcache
opcache.enable=1
opcache.enable_cli=0

; Memory settings
opcache.memory_consumption=${PHP_OPCACHE_MEMORY:-256}
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=${PHP_OPCACHE_MAX_FILES:-10000}

; Performance settings
opcache.max_wasted_percentage=5
opcache.validate_timestamps=0
opcache.revalidate_freq=0
opcache.fast_shutdown=1
opcache.optimization_level=0x7FFFBFFF

; JIT Configuration (PHP 8.3)
opcache.jit_buffer_size=${PHP_OPCACHE_JIT_BUFFER:-128M}
opcache.jit=1255
opcache.jit_hot_loop=64
opcache.jit_hot_func=16
opcache.jit_hot_return=8
opcache.jit_hot_side_exit=8
EOF
    
    log_success "OPcache config generated"
}

generate_php_fpm_config() {
    log_info "🔧 Generating PHP-FPM config..."

    # تولید کانفیگ اصلی PHP-FPM (اصلاح مسیر فایل)
    cat > "/usr/local/etc/php-fpm.conf" << EOF
[global]
pid = /var/run/php-fpm.pid
error_log = /var/log/php/php-fpm.log
log_level = warning
emergency_restart_threshold = 10
emergency_restart_interval = 1m
process_control_timeout = 10s
daemonize = no

include=/usr/local/etc/php-fpm.d/*.conf
EOF

    # تولید کانفیگ pool
    cat > "/usr/local/etc/php-fpm.d/www.conf" << EOF
[www]
user = www-data
group = www-data
listen = 9000
listen.owner = www-data
listen.group = www-data
listen.mode = 0660

pm = dynamic
pm.max_children = ${PHP_FPM_MAX_CHILDREN:-40}
pm.start_servers = ${PHP_FPM_START_SERVERS:-4}
pm.min_spare_servers = ${PHP_FPM_MIN_SPARE_SERVERS:-2}
pm.max_spare_servers = ${PHP_FPM_MAX_SPARE_SERVERS:-6}
pm.max_requests = ${PHP_FPM_MAX_REQUESTS:-1000}
pm.process_idle_timeout = 10s

pm.status_path = /fpm-status
ping.path = /fpm-ping
ping.response = pong

slowlog = /var/log/php/php-fpm-slow.log
request_slowlog_timeout = 10s
request_terminate_timeout = ${PHP_MAX_EXECUTION_TIME:-300}

php_admin_value[sendmail_path] = /usr/sbin/sendmail -t -i
php_flag[display_errors] = off
php_admin_value[error_log] = /var/log/php/php-error.log
php_admin_flag[log_errors] = on
php_admin_value[memory_limit] = ${PHP_MEMORY_LIMIT:-512M}
php_admin_value[max_execution_time] = ${PHP_MAX_EXECUTION_TIME:-300}
php_admin_value[max_input_time] = ${PHP_MAX_EXECUTION_TIME:-300}
php_admin_value[post_max_size] = ${PHP_POST_MAX_SIZE:-100M}
php_admin_value[upload_max_filesize] = ${PHP_UPLOAD_MAX_FILESIZE:-100M}
php_admin_value[max_input_vars] = ${PHP_MAX_INPUT_VARS:-3000}
php_admin_value[disable_functions] = exec,passthru,shell_exec,system,proc_open,popen
php_admin_value[open_basedir] = /var/www/html:/tmp:/var/log/php
EOF

    log_success "PHP-FPM config generated"
}

# ایجاد دایرکتوری‌های مورد نیاز
create_directories() {
    log_info "📁 Creating required directories..."
    
    mkdir -p \
        /var/log/php \
        /tmp/php/sessions \
        /var/run
    
    # تنظیم مالکیت
    chown -R www-data:www-data /var/log/php /tmp/php
    chmod -R 755 /var/log/php
    chmod -R 777 /tmp/php/sessions
    
    log_success success "Directories created"
}

# بررسی متغیرها
check_required_vars

# تولید کانفیگ‌ها
create_directories
generate_php_config
generate_opcache_config
generate_php_fpm_config

# نمایش تنظیمات اعمال شده
echo ""
echo "📊 Applied PHP Settings:"
echo "  - PHP Memory Limit: ${PHP_MEMORY_LIMIT:-512M}"
echo "  - Max Execution Time: ${PHP_MAX_EXECUTION_TIME:-300}"
echo "  - Upload Max Filesize: ${PHP_UPLOAD_MAX_FILESIZE:-100M}"
echo "  - Post Max Size: ${PHP_POST_MAX_SIZE:-100M}"
echo "  - OPcache Memory: ${PHP_OPCACHE_MEMORY:-256}M"
echo "  - PHP-FPM Max Children: ${PHP_FPM_MAX_CHILDREN:-40}"
echo ""

log_success "🚀 Starting PHP-FPM..."

# Start PHP-FPM
exec "$@"
