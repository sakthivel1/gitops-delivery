################################################################################
# Stage 1 — deps (cached layer)
################################################################################
FROM python:3.12-alpine AS deps

WORKDIR /app

# Build deps for psycopg2-binary (needs libpq headers on Alpine)
RUN apk add --no-cache gcc musl-dev libpq-dev

COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt

################################################################################
# Stage 2 — runtime (minimal Alpine)
################################################################################
FROM python:3.12-alpine AS runtime

ARG BUILD_DATE
ARG VCS_REF
ARG VERSION

LABEL org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.version="${VERSION}"

# Runtime library for psycopg2
RUN apk add --no-cache libpq

# Non-root user
RUN addgroup -S finapp && adduser -S -G finapp -h /app -s /sbin/nologin finapp

WORKDIR /app

# Copy installed packages from deps stage
COPY --from=deps /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=deps /usr/local/bin/gunicorn /usr/local/bin/gunicorn

COPY src/ ./src/

RUN chown -R finapp:finapp /app

USER finapp

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/healthz')"

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--threads", "4", \
     "--access-logfile", "-", "--error-logfile", "-", "src.app:create_app()"]
