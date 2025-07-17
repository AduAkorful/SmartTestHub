FROM python:3.11-slim

# System and Node dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        inotify-tools \
        nodejs \
        npm \
        git \
        curl \
        ca-certificates \
        build-essential && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Python dependencies for Algorand dev, test, lint, security, and coverage
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Node.js scripts for log/report aggregation
COPY scripts/package.json /app/scripts/
RUN cd /app/scripts && npm install

# Copy aggregation script (shared with other containers)
COPY scripts/aggregate-all-logs.js /app/scripts/

# Entrypoint and config
COPY entrypoint.sh ./
COPY config ./config

# Prepare logs and input directories
RUN mkdir -p /app/input /app/logs/coverage /app/logs/reports /app/logs/benchmarks /app/logs/security /app/logs/xray

RUN chmod +x /app/entrypoint.sh

ENV PYTHONUNBUFFERED=1

ENTRYPOINT ["/app/entrypoint.sh"]
