FROM ollama/ollama:latest

# Download the phi3:mini model at build time (custom entrypoint handles serving)
RUN ollama pull phi3:mini

# Expose Ollama API port
EXPOSE 11434

# Start Ollama server
CMD ["ollama", "serve"]
