FROM python:3.9-slim

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

# Install Python dependencies with Cairo compiler support
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir --timeout 600 -r requirements.txt || \
    (echo "Retrying with individual packages..." && \
     pip install --no-cache-dir starknet-py==0.20.0 && \
     pip install --no-cache-dir "cairo-lang>=0.13.0,<0.14.0" && \
     pip install --no-cache-dir pytest pytest-cov pytest-xdist pytest-mock && \
     pip install --no-cache-dir coverage bandit safety pip-audit && \
     pip install --no-cache-dir memory-profiler line-profiler psutil && \
     pip install --no-cache-dir flake8 black mypy pylint autopep8 && \
     pip install --no-cache-dir colorlog rich structlog && \
     pip install --no-cache-dir ipython ipdb click python-dotenv pyyaml && \
     pip install --no-cache-dir requests aiohttp pandas numpy && \
     pip install --no-cache-dir cryptography pycryptodome web3 eth-utils)

# Ensure Cairo compiler tools are available
RUN pip install --no-cache-dir starknet-devnet cairo-rs-py || \
    echo "Additional Cairo tools installation attempted"

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
