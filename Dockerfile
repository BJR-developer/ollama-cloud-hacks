FROM ollama/ollama:latest

# Create the internal Ollama directory structure
RUN mkdir -p /root/.ollama

# Create the credential files inside the container
RUN touch /root/.ollama/id_ed25519 && \
    touch /root/.ollama/id_ed25519.pub && \
    chmod 600 /root/.ollama/id_ed25519

# The entrypoint script reads environment variables at launch and writes them to the keys
ENTRYPOINT ["/bin/sh", "-c", "echo \"$OLLAMA_PRIVATE_KEY\" > /root/.ollama/id_ed25519 && echo \"$OLLAMA_PUBLIC_KEY\" > /root/.ollama/id_ed25519.pub && exec ollama serve"]
