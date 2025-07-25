FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        inotify-tools \
        nodejs \
        npm \
        git \
        build-essential && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Install Node.js dependencies
COPY scripts/package.json /app/scripts/
RUN cd /app/scripts && npm install

# Copy application files
COPY src ./src
COPY config ./config
COPY scripts/aggregate-all-logs.js ./scripts/
COPY entrypoint.sh ./

# Set up permissions and directories
RUN chmod +x /app/entrypoint.sh && \
    mkdir -p /app/input /app/logs/coverage /app/logs/reports \
             /app/logs/security /app/logs/performance

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app
ENV LOG_DIR=/app/logs
ENV WATCH_DIR=/app/input

# Set up a non-root user
RUN useradd -m -r -s /bin/bash appuser && \
    chown -R appuser:appuser /app
USER appuser

ENTRYPOINT ["/app/entrypoint.sh"]
