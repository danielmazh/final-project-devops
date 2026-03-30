FROM python:3.11-slim

ARG VERSION=dev
LABEL org.opencontainers.image.title="seyoawe-cli"
LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.description="sawectl — SeyoAWE CLI tool"

WORKDIR /app

# Install deps first (cached layer — only rebuilds when requirements change)
COPY cli/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy CLI source (schemas must be beside sawectl.py — required by os.path.dirname(__file__))
COPY cli/ .

# Inject the build-time version into the VERSION constant so --help shows it
RUN sed -i "s/^VERSION = \"[^\"]*\"/VERSION = \"${VERSION}\"/" sawectl.py

ENTRYPOINT ["python", "sawectl.py"]
