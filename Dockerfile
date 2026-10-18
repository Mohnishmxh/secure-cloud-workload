# ==========================================
# Stage 1: Builder Stage
# ==========================================
FROM python:3.11-slim AS builder

WORKDIR /build

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY app/requirements.txt .
# Install app dependencies, then remove pip, setuptools, and wheel from the venv
# so build/packaging tools (and their vendored CVEs) are not shipped to production
RUN pip install --no-cache-dir -r requirements.txt && \
    pip uninstall -y pip setuptools wheel

# ==========================================
# Stage 2: Hardened Runtime Stage
# ==========================================
FROM python:3.11-slim AS runtime

# Apply latest Debian security patches, remove unused system-level pip/setuptools/wheel,
# and clean apt cache
RUN apt-get update && \
    apt-get upgrade -y --no-install-recommends && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /usr/local/lib/python3.11/site-packages/pip* \
           /usr/local/lib/python3.11/site-packages/setuptools* \
           /usr/local/lib/python3.11/site-packages/wheel* \
           /usr/local/bin/pip*

# Create a non-root system group and user (UID/GID 10001) with no login shell
RUN groupadd -g 10001 appgroup && \
    useradd -u 10001 -g appgroup -M -s /usr/sbin/nologin appuser

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH"

# Copy virtual environment (now containing ONLY runtime dependencies)
COPY --from=builder /opt/venv /opt/venv

# Copy application code and lock down permissions (root owns, appgroup reads/executes)
COPY app/ /app/
RUN chown -R root:appgroup /app && \
    chmod -R 750 /app

# Switch to the non-root user (Remediates DS-0002)
USER 10001:10001

EXPOSE 8000

# Native Python healthcheck (Remediates DS-0026)
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health')"]

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
