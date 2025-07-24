FROM python:3.11-slim

# Install system dependencies
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

# Set up working directory
WORKDIR /app

# Install npm dependencies first
COPY scripts/package.json /app/scripts/
RUN cd /app/scripts && npm install

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Create necessary directories
RUN mkdir -p /app/input /app/logs/coverage /app/logs/reports /app/logs/benchmarks \
    /app/logs/security /app/logs/xray /app/contracts /app/tests

# Copy application files
COPY src ./src
COPY tests/test_contract_suite.py /app/tests/
COPY scripts/aggregate-all-logs.js ./scripts/
COPY entrypoint.sh ./

# Set permissions
RUN chmod +x /app/entrypoint.sh && \
    chmod -R 777 /app/logs

ENV PYTHONUNBUFFERED=1
ENV PATH="/app/scripts:${PATH}"

ENTRYPOINT ["/app/entrypoint.sh"]
