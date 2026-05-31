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
