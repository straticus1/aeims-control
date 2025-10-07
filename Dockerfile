# AEIMS Control Panel Container
# Management and deployment automation for AEIMS infrastructure

FROM php:8.2-cli-alpine

# Install system dependencies (removing unavailable packages)
RUN apk add --no-cache \
    git \
    curl \
    wget \
    unzip \
    bash \
    openssh-client \
    mysql-client \
    postgresql-client \
    nginx \
    supervisor \
    nodejs \
    npm \
    python3 \
    py3-pip

# Install PHP extensions (simplified)
RUN docker-php-ext-install pdo pdo_mysql

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Set working directory
WORKDIR /app

# Copy application files
COPY . .

# Copy security fixes
COPY security-fixes/ /app/security-fixes/
RUN chmod +x /app/security-fixes/*.sh

# Install PHP dependencies if composer.json exists
RUN if [ -f composer.json ]; then composer install --no-dev --optimize-autoloader; fi

# Install Python dependencies for automation scripts
RUN pip3 install --break-system-packages boto3 requests pyyaml

# Create scripts directory and make scripts executable
RUN mkdir -p /app/scripts && \
    find /app -name "*.sh" -exec chmod +x {} \; && \
    find /app -name "*.py" -exec chmod +x {} \;

# Configure for deployment automation
ENV PATH="/app/scripts:${PATH}"
ENV AEIMS_CONTROL_MODE=production

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD [ "php", "-v" ] || exit 1

# Labels
LABEL maintainer="AEIMS Team"
LABEL version="1.0.0"
LABEL description="AEIMS Control Panel and Deployment Automation"

# Default command
CMD ["php", "-a"]