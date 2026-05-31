# pgtime - Temporal Tables for PostgreSQL

[![CI](https://github.com/Sanidhyavijay24/pgtime/actions/workflows/ci.yml/badge.svg)](https://github.com/Sanidhyavijay24/pgtime/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> **Add a transaction-time versioning axis to any PostgreSQL table in one line.** Query your data at any point in the past, track every change automatically, and stay SQL-native.

---

## The Problem

Every application eventually requires historical tracking:
* **Audit logs:** Who changed what and when?
* **Point-in-time snapshots:** What did this dashboard look like on Jan 1st?
* **System state rollback:** What was the state of the database before a bad deployment?

The standard answer is to build it yourself—adding `created_at` / `updated_at`, custom history tables, and complicated join queries. It is boilerplate code every developer writes from scratch, writes slightly wrong (missing boundary edges), and maintains forever.

`pgtime` handles this transparently at the database layer.

---

## Core Architecture

`pgtime` tracks two time axes on your data:
1. **Transaction Time:** When the data was stored in the database (system time).
2. **Valid Time (Roadmap):** When the data was true in the real world (business time).

When you call `SELECT pgtime.attach('orders');`:
1. A shadow table `orders_history` is created, matching all of your original columns plus tracking fields (`sys_from`, `sys_to`, `_pgtime_op`).
2. A performance-critical `AFTER ROW` C-based trigger is bound to the `orders` table.
3. Every `INSERT`, `UPDATE`, and `DELETE` operation automatically updates the history table.
4. Fast snapshot querying is indexed via GiST and BTree ranges.

---

## Installation

`pgtime` consists of the core database C extension, a migration Go CLI, and client SDKs. For the `v0.1` release, the extension can be compiled either using our pre-configured Docker environment or directly on your host system.

### Option A: Using Docker (Recommended for development & testing)

Our development container includes the compiler toolchain, PostgreSQL 16, and pgTAP for running tests.

1. **Start the database container:**
   ```bash
   cd docker
   docker compose up -d
   cd ..
   ```
2. **Compile and install the extension inside the container:**
   ```bash
   docker exec -t pgtime_dev_postgres make -C /workspace/extension
   docker exec -t pgtime_dev_postgres make install -C /workspace/extension
   ```
3. **Enable the extension in your database:**
   ```bash
   docker exec -t pgtime_dev_postgres psql -U postgres -d pgtime_test -c "CREATE EXTENSION IF NOT EXISTS pgtime;"
   ```
4. **Run the pgTAP test suite:**
   ```bash
   docker exec -t pgtime_dev_postgres pg_prove -U postgres -d pgtime_test /workspace/tests/test_pgtime.sql
   ```

---

### Option B: Local Host Installation (Without Docker)

#### 1. Core C Extension
##### Prerequisites
* PostgreSQL 14, 15, or 16.
* PostgreSQL development headers (e.g., `postgresql-server-dev-16` on Debian/Ubuntu, or `postgresql` package in Homebrew).
* A C compiler (`gcc` or `clang`) and `make`.

##### Build & Install
1. Navigate to the extension directory:
   ```bash
   cd extension
   ```
2. Compile the shared library and copy it to your PostgreSQL system directories (requires administrator privileges):
   ```bash
   make
   sudo make install
   ```
   *Note: If `pg_config` is not in your system PATH or you have multiple PostgreSQL installations, specify it explicitly:*
   ```bash
   make PG_CONFIG=/usr/lib/postgresql/16/bin/pg_config
   sudo make PG_CONFIG=/usr/lib/postgresql/16/bin/pg_config install
   ```
3. Enable the extension in your database:
   ```sql
   CREATE EXTENSION pgtime;
   ```

#### 2. Go CLI
To build and install the `pgtime` CLI binary:
1. Ensure you have [Go 1.21+](https://go.dev/) installed.
2. Navigate to the CLI directory and build:
   ```bash
   cd cli
   go build -o pgtime
   ```
3. Move the binary into your system PATH (optional):
   ```bash
   sudo mv pgtime /usr/local/bin/
   ```

---

### 3. Client SDKs (Source Clone Installation)

Since packages are in active development and not yet published to public registries, install them directly from your local clone:

#### Node.js / TypeScript SDK
Install the SDK into your Node/Bun project from the local path:
```bash
# Via npm
npm install ./sdk/node

# Via Bun
bun add ./sdk/node
```

#### Python SDK
Install the SDK in editable mode:
```bash
pip install -e ./sdk/python
```

---

*Note: Pre-compiled registry packages (`pgxman install pgtime` and `pgxn install pgtime`) will be available in future releases.*

---

## Quick Start (SQL)

```sql
-- 1. Load the extension
CREATE EXTENSION pgtime;

-- 2. Enable temporal tracking on any table (automatically detects primary key)
SELECT pgtime.attach('orders');

-- That's it! Changes are now tracked automatically.

-- 3. Query the past (fetch the state of orders as of Jan 15th, 2026)
SELECT * FROM pgtime.as_of('orders', '2026-01-15 10:00:00+00') 
  AS (id INT, item TEXT, price NUMERIC, sys_from TIMESTAMPTZ, sys_to TIMESTAMPTZ, valid_from TIMESTAMPTZ, valid_to TIMESTAMPTZ, _pgtime_op CHAR(1));

-- 4. View a row's version ledger (auditing changes)
SELECT price, sys_from, _pgtime_op FROM pgtime.history('orders', 42)
  AS (id INT, item TEXT, price NUMERIC, sys_from TIMESTAMPTZ, sys_to TIMESTAMPTZ, valid_from TIMESTAMPTZ, valid_to TIMESTAMPTZ, _pgtime_op CHAR(1));
```

---

## SDKs

We provide thin client wrappers for popular languages.

### Node.js / TypeScript SDK

```typescript
import { Pool } from 'pg';
import { PgTime } from 'pgtime-js';

const pool = new Pool({ connectionString: process.env.DATABASE_URL });
const pt = new PgTime(pool);

// 1. Enable tracking
await pt.attach('orders');

// 2. Fetch point-in-time snapshots (Dynamic typing out of the box!)
interface Order { id: number; item: string; price: number; }
const historicalOrders = await pt.asOf<Order>('orders', '2026-01-15T10:00:00Z');

// 3. Retrieve row audit trail
const orderLogs = await pt.history('orders', 42);
```

### Python SDK

```python
import psycopg2
from pgtime import PgTime

conn = psycopg2.connect("postgres://...")
pt = PgTime(conn)

# 1. Enable tracking
pt.attach("orders")

# 2. Fetch point-in-time snapshots (returns list of dicts)
historical_orders = pt.as_of("orders", "2026-01-15T10:00:00Z")

# 3. Retrieve row audit trail
order_logs = pt.history("orders", 42)
```

---

## Go CLI

A fast Go-based command line binary is included for migrations and terminal operations.

```bash
# Install the extension in a database
pgtime init --db postgres://localhost/mydb

# Track a table
pgtime attach orders --db postgres://localhost/mydb

# List tracked tables
pgtime list --db postgres://localhost/mydb

# Show modifications made to row 42
pgtime history orders --id 42 --db postgres://localhost/mydb

# Diff changes between two dates
pgtime diff orders --from "2026-01-01" --to "2026-02-01" --db postgres://localhost/mydb
```

---

## Running the Examples

The repository includes complete, runnable example scripts for both Node.js (TypeScript) and Python. You can execute them against the Docker development database container.

### Prerequisites
1. Start the Docker development database (with the compiled extension):
   ```bash
   cd docker
   docker compose up -d
   cd ..
   docker exec -t pgtime_dev_postgres make install -C /workspace/extension
   ```

### Running the Node.js / TypeScript Example
1. Install project dependencies in the repository root:
   ```bash
   bun install
   ```
2. Run the example script:
   ```bash
   bun run examples/node_example.ts
   ```

**Expected Console Output:**
```text
Setting up example table...
Attaching pgtime temporal tracking...
Inserting a record...
Updating the record (price drop)...
Deleting the record...

--- Querying Snapshots (asOf) ---
State right after Insert: [
  {
    id: 1,
    item: "Espresso Machine",
    price: "899.99",
    sys_from: 2026-05-31T18:48:46.461Z,
    sys_to: 2026-05-31T18:48:46.579Z,
    valid_from: null,
    valid_to: null,
    _pgtime_op: "I",
  }
]
State right after Update (price drop): [
  {
    id: 1,
    item: "Espresso Machine",
    price: "799.99",
    sys_from: 2026-05-31T18:48:46.579Z,
    sys_to: 2026-05-31T18:48:46.683Z,
    valid_from: null,
    valid_to: null,
    _pgtime_op: "D",
  }
]
State right after Delete: []

--- Fetching Row Audit History (history) ---
[
  {
    id: 1,
    item: "Espresso Machine",
    price: "899.99",
    sys_from: 2026-05-31T18:48:46.461Z,
    sys_to: 2026-05-31T18:48:46.579Z,
    valid_from: null,
    valid_to: null,
    _pgtime_op: "I",
  },
  {
    id: 1,
    item: "Espresso Machine",
    price: "799.99",
    sys_from: 2026-05-31T18:48:46.579Z,
    sys_to: 2026-05-31T18:48:46.683Z,
    valid_from: null,
    valid_to: null,
    _pgtime_op: "D",
  }
]
Finished example run successfully.
```

### Running the Python Example
1. Install the SDK package in editable mode:
   ```bash
   pip install -e ./sdk/python
   ```
2. Run the example script:
   ```bash
   python examples/python_example.py
   ```

---

## Contributing & Development

To get started developing or compiling the extension, see our [CONTRIBUTING.md](file:///workspace/CONTRIBUTING.md) guide.

---

## License

This project is licensed under the [MIT License](file:///workspace/LICENSE).
