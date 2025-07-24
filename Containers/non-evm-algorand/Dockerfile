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
COPY scripts/aggregate-all-logs.js ./scripts/
COPY entrypoint.sh ./
COPY tests/test_contract_suite.py /app/tests/

RUN chmod +x /app/entrypoint.sh

RUN mkdir -p /app/input /app/logs/coverage /app/logs/reports /app/logs/benchmarks /app/logs/security /app/logs/xray

ENV PYTHONUNBUFFERED=1

ENTRYPOINT ["/app/entrypoint.sh"]
