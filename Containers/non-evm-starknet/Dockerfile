FROM python:3.11-slim

# Install system dependencies and security tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        inotify-tools \
        nodejs \
        npm \
        git \
        curl \
        ca-certificates \
        build-essential \
        gcc \
        g++ \
        make \
        python3-dev \
        libffi-dev \
        libssl-dev \
        htop \
        procps \
        time \
        && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python dependencies first for better caching
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Install npm dependencies
COPY scripts/package.json /app/scripts/
RUN cd /app/scripts && npm install

# Copy application files and templates
COPY src ./src
COPY tests ./tests
COPY config ./config
COPY scripts/aggregate-all-logs.js ./scripts/
COPY scripts/generate_starknet_tests.py ./scripts/
COPY entrypoint.sh ./

# Set permissions
RUN chmod +x /app/entrypoint.sh

# Create necessary directories with proper permissions
RUN mkdir -p /app/input \
    /app/logs/coverage \
    /app/logs/reports \
    /app/logs/benchmarks \
    /app/logs/security \
    /app/logs/cairo \
    /app/logs/integration \
    /app/logs/metrics \
    /app/logs/debug \
    /app/logs/performance \
    /app/contracts \
    /app/cairo_libs && \
    chmod -R 777 /app/logs /app/input /app/contracts

# Environment variables for optimization
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUTF8=1

ENTRYPOINT ["/app/entrypoint.sh"]
