# SQL API Reference

All `pgtime` extension functions are registered under the `pgtime` schema namespace.

---

### `pgtime.attach(table_name TEXT) -> VOID`
Enables temporal version tracking on a target table.
* **Introspection:** Automatically reads `pg_catalog` to identify the table's single-column primary key and data type.
* **DDL generation:** Creates a shadow table named `<table_name>_history` in the same schema.
* **Trigger setup:** Attaches a compiled C trigger `AFTER INSERT OR UPDATE OR DELETE` to the source table.
* **Indexing:** Builds a GiST index on the `sys_from` / `sys_to` range and a partial BTree index on active rows.

---

### `pgtime.detach(table_name TEXT) -> VOID`
Disables temporal tracking on a table.
* **Triggers:** Drops the trigger from the source table.
* **Metadata:** Deletes the table's registration record from `pgtime._tracked_tables`.
* **History:** The shadow history table is **preserved** to prevent data loss.

---

### `pgtime.as_of(table_name TEXT, ts TIMESTAMPTZ) -> SETOF RECORD`
Reconstructs the point-in-time state (snapshot) of a table at the specified timestamp.
* **Parameters:**
  * `table_name`: Table to query.
  * `ts`: Target snapshot timestamp.
* **Query Signature Requirement:** Callers must append an `AS (column_definitions...)` signature representing the shadow history table columns.

---

### `pgtime.history(table_name TEXT, row_id anyelement) -> SETOF RECORD`
Returns the complete change ledger (audit log) of a specific row.
* **Parameters:**
  * `table_name`: Source table name.
  * `row_id`: Value of the primary key. Type is generic (`anyelement`), matching integer, text, or UUID keys dynamically.

---

### `pgtime.versions(table_name TEXT, row_id anyelement) -> BIGINT`
Returns the total number of versions recorded for a given row.
* **Parameters:**
  * `table_name`: Source table.
  * `row_id`: Primary key value.

---

### `pgtime.diff(table_name TEXT, t1 TIMESTAMPTZ, t2 TIMESTAMPTZ) -> SETOF RECORD`
Returns all row versions created or modified in a table between two timestamps.
* **Parameters:**
  * `table_name`: Source table.
  * `t1`: Start boundary timestamp.
  * `t2`: End boundary timestamp.

---

## Dynamically Generated Helper Functions (Recommended UX)

When you run `SELECT pgtime.attach('orders');`, `pgtime` automatically generates three typed helper functions inside the target table's schema. These functions are bound to the history table's row-type, meaning **no manual `AS (...)` column definition list is required** when querying them from SQL clients:

### `<schema>.<table_name>_as_of(ts TIMESTAMPTZ) -> SETOF <schema>.<table_name>_history`
Reconstructs the point-in-time state (snapshot) of all active rows in the table at the target timestamp.
```sql
SELECT * FROM public.orders_as_of('2026-01-15 10:00:00+00');
```

### `<schema>.<table_name>_history(row_id ANYELEMENT) -> SETOF <schema>.<table_name>_history`
Returns the chronological change ledger (audit log) of a specific row.
```sql
SELECT * FROM public.orders_history(42);
```

### `<schema>.<table_name>_diff(t1 TIMESTAMPTZ, t2 TIMESTAMPTZ) -> SETOF <schema>.<table_name>_history`
Returns all row versions created or modified in the table between the two timestamps.
```sql
SELECT * FROM public.orders_diff('2026-01-01', '2026-02-01');
```
