# Contributing to pgtime

Thank you for your interest in contributing to `pgtime`! We welcome contributions of all kinds, including bug reports, feature suggestions, documentation updates, and pull requests.

---

## Developer Environment Setup

Our development and testing environments are unified and run inside a Docker container. This ensures that you don't need to pollute your host system with PostgreSQL dev headers, compilers, or test harness dependencies.

### Prerequisites
* [Docker Desktop](https://www.docker.com/products/docker-desktop/) (with WSL 2 integration enabled on Windows).
* Go 1.21+ (if you wish to build the CLI locally).
* Bun 1.0+ (if you wish to run Node/TypeScript tests locally).
* Python 3.8+ (if you wish to run Python tests locally).

### 1. Launch the Database Container
Start the PostgreSQL container in detached mode:
```bash
cd docker
docker compose up -d
```
This container runs PostgreSQL 16 and pre-installs the `pgtap` test library and compilation toolchain.

---

## Working on the C Extension

The core extension is located under [extension/](file:///workspace/extension).

### Compiling
To compile the C source files inside the container:
```bash
docker exec -t pgtime_dev_postgres make -C /workspace/extension
```

### Installing
To install the compiled extension files into PostgreSQL's system paths:
```bash
docker exec -t pgtime_dev_postgres make install -C /workspace/extension
```

### Refreshing the Extension
After compiling and installing, refresh the extension in the test database to load the updated code:
```bash
docker exec -t pgtime_dev_postgres psql -U postgres -d pgtime_test -c "DROP EXTENSION IF EXISTS pgtime CASCADE; CREATE EXTENSION pgtime;"
```

---

## Running Tests

### 1. Core SQL & Trigger Tests (pgTAP)
To run the main database test suite:
```bash
docker exec -t pgtime_dev_postgres pg_prove -U postgres -d pgtime_test /workspace/tests/test_pgtime.sql
```

### 2. Node.js SDK Tests (Bun)
To run the Node.js/TypeScript SDK integration tests:
```bash
cd sdk/node
bun install
bun test
```

### 3. Python SDK Tests (Pytest)
To run the Python SDK integration tests:
```bash
cd sdk/python
pip install -r requirements.txt
python -m pytest
```

---

## Code Style Guidelines
* **Indent:** 2 spaces for JS/TS/SQL/Makefile, 4 spaces for Python.
* **C Code Formatting:** Keep all variable declarations at the start of block scopes (C89 compatible) to ensure clean builds across standard compilers.
* **API Safety:** Ensure all client-side wrappers validate schema and table identifiers against regexes before interpolating them into SQL strings to prevent injection.
