FROM php:7.4-fpm-alpine

# persistent dependencies
RUN apk add --no-cache \
# in theory, docker-entrypoint.sh is POSIX-compliant, but priority is a working, consistent image
		bash \
# BusyBox sed is not sufficient for some of our sed expressions
		sed \
# Needed for adding timezones and fixing localtime
		tzdata \
# Apache2 with FPM, SSL and HTTP/2 support
		apache2 \
		apache2-proxy \
		apache2-http2 \
		apache2-ssl \
# Supervisor install
		supervisor
# install the PHP extensions we need (https://make.wordpress.org/hosting/handbook/handbook/server-environment/#php-extensions)
RUN set -ex; \
	\
	apk add --no-cache --virtual .build-deps \
		$PHPIZE_DEPS \
		gmp-dev \
		freetype-dev \
		imagemagick-dev \
		libmcrypt-dev \
		libjpeg-turbo-dev \
		libpng-dev \
		libzip-dev \
		pcre-dev \
	; \
	\
	docker-php-ext-configure gd --with-freetype --with-jpeg; \
	docker-php-ext-install -j "$(nproc)" \
		bcmath \
		iconv \
		exif \
		gd \
		gmp \
		pdo_mysql \
		mysqli \
		opcache \
		zip \
	; \
	pecl install mcrypt apcu imagick; \
	docker-php-ext-enable mcrypt apcu imagick; \
	\
	runDeps="$( \
		scanelf --needed --nobanner --format '%n#p' --recursive /usr/local/lib/php/extensions \
			| tr ',' '\n' \
			| sort -u \
			| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
	)"; \
	apk add --virtual .xenforo-phpexts-rundeps $runDeps; \
	apk del .build-deps

# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN { \
		echo 'opcache.memory_consumption=128'; \
		echo 'opcache.interned_strings_buffer=8'; \
		echo 'opcache.max_accelerated_files=4000'; \
		echo 'opcache.revalidate_freq=2'; \
		echo 'opcache.fast_shutdown=1'; \
	} > /usr/local/etc/php/conf.d/opcache-recommended.ini
RUN { \
# https://www.php.net/manual/en/errorfunc.constants.php
		echo 'error_reporting = E_ERROR | E_WARNING | E_PARSE | E_CORE_ERROR | E_CORE_WARNING | E_COMPILE_ERROR | E_COMPILE_WARNING | E_RECOVERABLE_ERROR'; \
		echo 'display_errors = Off'; \
		echo 'display_startup_errors = Off'; \
		echo 'log_errors = On'; \
		echo 'error_log = /dev/stderr'; \
		echo 'log_errors_max_len = 1024'; \
		echo 'ignore_repeated_errors = On'; \
		echo 'ignore_repeated_source = Off'; \
		echo 'html_errors = Off'; \
	} > /usr/local/etc/php/conf.d/error-logging.ini

VOLUME /var/www/html

ENV TZ Europe/Rome
ENV PUID 1000

# Fixes uid/gid of nobody, clearing unused users and groups
RUN sed -i 's/:65534:65534:nobody:\/:/:1000:100:nobody:\/var\/www:/g' /etc/passwd && \
    sed -i '/^\s*www-data/ d' /etc/passwd /etc/group && \
    sed -i '/^\s*apache/ d' /etc/passwd /etc/group && \
    sed -i 's/user = www-data/user = nobody/g' /usr/local/etc/php-fpm.d/www.conf && \
    sed -i 's/group = www-data/group = users/g' /usr/local/etc/php-fpm.d/www.conf

# Setting up Apache2 and PHP
COPY config/httpd.conf /etc/apache2/

# Set timezone
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && echo ${TZ} > /etc/timezone \
    && printf '[PHP]\ndate.timezone = "%s"\n', ${TZ} > /usr/local/etc/php/conf.d/tzone.ini \
    && "date"

# Setting up the Container and Supervisor
COPY entrypoint.sh /usr/bin/
COPY config/supervisord.conf /etc/
RUN chmod +x /usr/bin/entrypoint.sh

EXPOSE 80
EXPOSE 443

ENTRYPOINT ["entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
