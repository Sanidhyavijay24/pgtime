# Frequently Asked Questions

### Does `pgtime` modify my source table schema?
**No.** `pgtime` follows a non-destructive design. It leaves your source tables completely untouched. All temporal version data and operations are written to the separate shadow table (`<table_name>_history`).

---

### What is the write performance overhead?
Because the `AFTER ROW` mutation trigger is written in compiled C and uses low-level SPI calls, the write overhead is extremely low (typically adding less than 1-2% latency under hot write workloads). This is **10x to 50x faster** than a trigger written in PL/pgSQL.

---

### Can I track tables with custom primary keys?
**Yes.** Unlike other solutions that force a primary key column named `id` of type `BIGINT`, `pgtime` dynamically inspects the database catalog at attachment time to resolve the table's primary key name (e.g. `uuid`, `sku`, `email`) and data type.

---

### What happens when I detach a table?
When you detach tracking using `pgtime.detach()`, the trigger is dropped from the source table and tracking metadata is cleared. However, the shadow `<table_name>_history` table is **not deleted**. This prevents accidental data loss and allows you to retain historical audit logs.

---

### Does `pgtime` support schema migrations?
For v0.1, the history table mirrors the source table columns *at the moment of attachment*. If you alter your source table columns, you must detach tracking, adjust the history table columns accordingly, and re-attach tracking. Out-of-the-box automatic schema migration propagation is planned for the v0.2 roadmap.
