FROM python:3.11-slim

ARG VERSION=dev
LABEL org.opencontainers.image.title="seyoawe-engine"
LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.description="SeyoAWE Community workflow automation engine"

WORKDIR /app

# Install curl (health-check) and clean apt cache in one layer
RUN apt-get update && apt-get install -y --no-install-recommends curl git \
    && rm -rf /var/lib/apt/lists/*

# Install Python deps required by the built-in modules
RUN pip install --no-cache-dir requests pyyaml jinja2 gitpython

# Copy the full engine tree (config, modules, workflows, binary)
COPY engine/ .

# Module loader expects modules/modules/<name>/ — create the self-referencing symlink
# From inside modules/: ln -s . modules  →  modules/modules → modules/
RUN cd modules && ln -sf . modules

# Fail fast with a clear message if the binary is missing
RUN test -f seyoawe.linux \
    || (echo "" && \
        echo "╔══════════════════════════════════════════════════════╗" && \
        echo "║  ERROR: seyoawe.linux binary not found.             ║" && \
        echo "║  Download it from the upstream GitHub releases and  ║" && \
        echo "║  place it at engine/seyoawe.linux before building.  ║" && \
        echo "╚══════════════════════════════════════════════════════╝" && \
        echo "" && exit 1)

RUN chmod +x seyoawe.linux run.sh

# Runtime directories (logs and lifetimes persist via PVC in K8s)
RUN mkdir -p lifetimes logs

EXPOSE 8080 8081

# Engine has no dedicated /health route — any HTTP response confirms the server is up.
# curl without -f returns 0 on any HTTP response (including 404/405), non-zero only on
# connection failure, so this reliably detects whether Flask is accepting requests.
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -s http://localhost:8080/ > /dev/null || exit 1

# Suppress gitpython startup warning (engine bundles gitpython; git CLI is installed above)
ENV GIT_PYTHON_REFRESH=quiet

ENTRYPOINT ["./seyoawe.linux"]
