# Quick Start Guide

Get up and running with temporal tables in under 5 minutes.

---

### Step 1: Initialize the Extension
Connect to your database via `psql` (or any client) and load the extension:
```sql
CREATE EXTENSION pgtime;
```

---

### Step 2: Track a Table
Enable temporal versioning on your table:
```sql
-- Automatically creates a matching "orders_history" shadow table and binds the triggers
SELECT pgtime.attach('orders');
```
*Note: Your table must have a single-column primary key (e.g. `id` or `uuid`) to be tracked.*

---

### Step 3: Mutate Data
Make insertions, updates, and deletions as normal. Triggers run in the background with minimal overhead:
```sql
-- Version 1
INSERT INTO orders (id, item, price) VALUES (42, 'Coffee Maker', 49.99);

-- Version 2
UPDATE orders SET price = 39.99 WHERE id = 42;

-- Deletion (ends history trail)
DELETE FROM orders WHERE id = 42;
```

---

### Step 4: Query Snapshots
Query what the table looked like at any specific point in transaction history:
```sql
-- Reconstruct table state as of a timestamp (no manual column lists needed!)
SELECT * FROM orders_as_of('2026-06-01 10:00:00+00');
```
*Note: When you attach a table, pgtime dynamically generates typed helper functions (like `<table_name>_as_of`, `<table_name>_history`, and `<table_name>_diff`) inside your table schema so you can query temporal states natively.*

---

### Step 5: Read Row Audit Log
See the full mutation ledger of a specific row over time:
```sql
SELECT price, sys_from, _pgtime_op FROM orders_history(42);
```
* **Output:** Will return version rows with `_pgtime_op` as `'I'` (Insert), `'U'` (Update), and `'D'` (Delete).
