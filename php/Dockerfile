FROM php:8.3-fpm-alpine


RUN apk update && apk add --no-cache \
    bash \
    curl \
    wget \
    unzip \
    git \
    libzip-dev \
    oniguruma-dev \
    # پاکسازی cache
    && rm -rf /var/cache/apk/*

RUN docker-php-ext-install -j$(nproc) \
    pdo \
    pdo_mysql \
    mysqli \
    zip \
    mbstring \
    opcache \
# پاکسازی فایل‌های اضافی
&& docker-php-source delete

# نصب composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# کپی فایل‌های تنظیمات و entrypoint
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh


# ساخت دایرکتوری لاگ
RUN mkdir -p \
    /var/www/html \
    /var/log/php \
    /var/run/php \
    /tmp/php/sessions 

WORKDIR /var/www/html

EXPOSE 9000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["php-fpm"]
