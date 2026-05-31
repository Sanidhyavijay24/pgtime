# Use the official PostgreSQL 16 image as a base
FROM postgres:16

# Install build tools, pg_config dev headers, pgTAP for testing, and golang
RUN apt-get update && apt-get install -y \
    build-essential \
    postgresql-server-dev-16 \
    postgresql-16-pgtap \
    git \
    golang \
    && rm -rf /var/lib/apt/lists/*

# Set the default working directory
WORKDIR /workspace
