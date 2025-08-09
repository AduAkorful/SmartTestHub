FROM python:3.11-slim

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

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY scripts/package.json /app/scripts/
RUN cd /app/scripts && npm install

COPY src ./src
COPY tests ./tests
COPY config ./config
# Ensure all helper scripts (including test generator) are available in the container
COPY scripts/ ./scripts/
COPY entrypoint.sh ./

RUN chmod +x /app/entrypoint.sh

RUN mkdir -p /app/input /app/logs/coverage /app/logs/reports /app/logs/benchmarks /app/logs/security /app/logs/xray

ENV PYTHONUNBUFFERED=1

ENTRYPOINT ["/app/entrypoint.sh"]
