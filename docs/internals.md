# Architecture & Internals

`pgtime` is built on low-level PostgreSQL primitives to ensure reliability and speed.

---

## 1. History Table Structure
When tracking is attached to a table, `pgtime` generates a history table mirroring all of the source table's columns plus the following tracking attributes:
* `sys_from` (`TIMESTAMPTZ NOT NULL`): The start transaction timestamp during which this version was current.
* `sys_to` (`TIMESTAMPTZ`): The transaction timestamp when this version was superseded (NULL represents the active current row version).
* `valid_from` / `valid_to` (`TIMESTAMPTZ`): Business-valid range.
* `_pgtime_op` (`CHAR(1)`): The action code representing the mutation: `'I'` (Insert), `'U'` (Update), `'D'` (Delete).

---

## 2. Trigger Mechanics (C extension)
To achieve high write throughput, the mutation trigger is compiled as a shared C library (`pgtime.so`) running inside the PostgreSQL server context.

```
          INSERT / UPDATE / DELETE on [Table]
                         │
                         ▼
        [C Trigger Function: pgtime_trigger_fn]
                         │
        ┌────────────────┴────────────────┐
        ▼                                 ▼
   On UPDATE or DELETE              On INSERT or UPDATE
        │                                 │
   Update previous version           Write new row snapshot
   in history table:                 in history table:
   sys_to = now()                    sys_from = now()
   _pgtime_op = D (if deleted)       _pgtime_op = I / U
```

* **Server Programming Interface (SPI):** The trigger uses PostgreSQL's low-level SPI to prepare and execute dynamic SQL queries on the history table.
* **ANSI C89 compliance:** The C code is strictly formatted to ensure clean compilation across different database compilers.

---

## 3. Query Execution & Indexing
To ensure `as_of` queries scale to millions of historical rows, `pgtime` builds a **GiST** index on the timeperiod range:
```sql
CREATE INDEX ... USING GIST (tstzrange(sys_from, sys_to));
```
When querying `WHERE sys_from <= ts AND (sys_to IS NULL OR sys_to > ts)`, PostgreSQL's planner utilizes a range index scan instead of a full sequential scan, maintaining `O(log N)` query complexity.
Additionally, a partial BTree index is placed on the primary key where `sys_to IS NULL` to ensure normal write lookups remain fast.
