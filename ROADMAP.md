# pgtime Roadmap

This roadmap outlines the planned features, architectural improvements, and distribution milestones for `pgtime`. We encourage contributors to open issues or pull requests to discuss and implement any of these items.

---

## v0.2 Milestone: Core Extension Enhancements

### 1. SQL:2011 Standard `AS OF` Syntax
* **Objective:** Replace the current function-based `pgtime.as_of(...)` query format with native SQL query rewrites.
* **Details:** Implement a PostgreSQL parser hook (`post_parse_analyze_hook`) in C to detect standard `SELECT * FROM table AS OF 'timestamp'` clauses and rewrite the parse tree to target the history shadow tables dynamically behind the scenes.

### 2. True Bi-Temporal (Valid-Time) Support
* **Objective:** Enable valid-time (business-valid range) querying in addition to system-transaction time.
* **Details:** Build catalog functions that allow developers to provide custom `valid_from` and `valid_to` bounds and execute overlaps, containment, and state-reconstructions across both time axes.

### 3. Dynamic Schema Migration Propagation
* **Objective:** Automatically propagate structural schema changes (`ALTER TABLE`) from parent tables to their history tables.
* **Details:** Attach an `Event Trigger` to DDL execution commands (`ddl_command_end`) to mirror column creations, modifications, and deletions instantly on shadow tables.

### 4. History Table Archiving & Partitioning
* **Objective:** Support high-volume databases by preventing history table and range index bloat.
* **Details:**
  * Implement `pgtime.archive(table, before_timestamp)` to offload expired history records to cold storage or files.
  * Integrate automatic history table partitioning based on the `sys_from` transaction date out of the box.

### 5. High-Throughput Write Path Optimizations (C-Trigger)
* **Objective:** Maximize write performance by reducing context switching and execution planning overhead.
* **Details:**
  * **Prepared SPI Plans**: Cache prepared plans (`SPI_prepare`) in relation metadata cache entries to bypass query parsing and planning stages on subsequent row modifications.
  * **Transition Tables / Batch Operations**: Explore migrating row-level C triggers to statement-level triggers utilizing transition tables (`REFERENCING NEW TABLE`) to insert/update historical snapshots in bulk instead of row-by-row.

---

## v0.2 Milestone: Tooling, SDKs & Distribution

### 1. Go SDK (`pgtime-go`)
* **Objective:** Implement the native Go client wrapper matching the API signature of our Node and Python SDKs.

### 2. Extension Registries
* **Objective:** Distribute `pgtime` via standard package managers.
* **Details:** Register and upload build manifests to **PGXN** (PostgreSQL Extension Network) and **pgxman** to enable instant pre-compiled binaries installations.

### 3. CLI State Rollbacks
* **Objective:** Add restoration commands to the CLI.
* **Details:** Implement `pgtime rollback <table> --to <timestamp>` to automatically restore the state of the active database table to any point in the transaction past.
