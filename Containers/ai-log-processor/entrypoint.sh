#!/bin/sh
set -e

# Start Ollama in the background
ollama serve &
OLLAMA_PID=$!

# Wait for Ollama to be ready
echo "Waiting for Ollama server to be ready..."
until curl -s http://localhost:11434 > /dev/null; do
  sleep 1
done

# Pull the phi3:mini model
echo "Downloading phi3:mini model..."
ollama pull phi3:mini

# Kill the background server (to restart in foreground)
kill $OLLAMA_PID

# Start Ollama in the foreground
exec ollama serve
