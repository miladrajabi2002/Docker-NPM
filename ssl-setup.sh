#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Enhanced domain validation
validate_domain() {
    local domain=$1
    
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

while true; do
    read -p "🌐 Domain name (e.g., example.com): " DOMAIN
    if [ -z "$DOMAIN" ]; then
        DOMAIN="localhost"
        break
    elif validate_domain "$DOMAIN"; then
        break
    fi
done

log "Starting SSL setup for domain: $DOMAIN"

log "Restarting nginx..."
docker compose restart nginx

log "Testing access to acme-challenge path..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$DOMAIN/.well-known/acme-challenge/test || echo "000")

if [ "$HTTP_CODE" != "404" ] && [ "$HTTP_CODE" != "200" ]; then
    warning "There might be an issue accessing the domain (HTTP Code: $HTTP_CODE)"
    echo -n "Do you want to continue? (y/N): "
    read CONTINUE
    if [[ ! $CONTINUE =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Request SSL
log "Requesting SSL certificate from Let's Encrypt..."

if docker compose --profile ssl-tools run --rm letsencrypt certonly \
    --webroot \
    --webroot-path=/var/www/certbot \
    --email miladrajabi@example.com \
    --agree-tos \
    --no-eff-email \
    -d $DOMAIN; then
    
    log "SSL certificate obtained successfully!"

    # Update nginx config with SSL
    log "Updating nginx configuration with SSL..."
    cat > nginx/conf.d/default.conf << EOF
server {
    listen 80;
    server_name $DOMAIN;

    # Redirect all HTTP requests to HTTPS
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    root /var/www/html;
    index index.php index.html;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    ssl_buffer_size 4k;


    location ~* \.(jpg|jpeg|png|gif|ico|css|js|pdf|txt|woff|svg|ttf|eot|woff2)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    location ~ \.php$ {
        proxy_redirect off;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
        try_files \$uri =404;
        fastcgi_pass php:9000;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
        fastcgi_busy_buffers_size 256k;
    }

    location / {
        proxy_redirect off;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ /\. {
        deny all;
        access_log off;
    }
}
EOF
    
# Final nginx restart    
log "Final nginx restart..."
docker compose restart nginx
    
sleep 3
    
# Final check
NGINX_STATUS=$(docker compose ps nginx --format "table {{.State}}" | tail -n +2)
if [[ "$NGINX_STATUS" == *"running"* ]]; then
    log "✅ SSL configured successfully!"
    log "🌐 Your website is available at https://$DOMAIN"

    # Test SSL
    log "Testing SSL..."
    SSL_TEST=$(curl -s -o /dev/null -w "%{http_code}" https://$DOMAIN --max-time 10 || echo "000")
    if [ "$SSL_TEST" = "200" ]; then
        log "✅ SSL is working correctly!"
    else
        warning "⚠️  SSL might have issues. HTTP Code: $SSL_TEST"
    fi
else
    error "❌ nginx did not start after SSL configuration!"
    exit 1
fi

else
    error "❌ Error obtaining SSL certificate!"
    error "Please check the following:"
    error "1. Does the domain point to the server's IP?"
    error "2. Is port 80 open?"
    error "3. Is the firewall configured correctly?"
    exit 1
fi

log "🎉 Done!"
