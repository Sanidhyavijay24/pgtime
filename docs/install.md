# Installation Guide

`pgtime` runs as a native PostgreSQL C extension. For the `v0.1` release, it is installed by compiling from source. Package manager registry support is planned for future releases.

---

## Method 1: Building From Source (Current)
If you are compiling locally or inside a custom database container:

### Prerequisites
* PostgreSQL 14, 15, or 16.
* `pg_config` dev tools installed (e.g. `postgresql-server-dev-16` on Debian/Ubuntu).
* C compiler (`gcc` or `clang`) and `make`.

### Build Steps
1. Clone the repository and navigate to the extension directory:
   ```bash
   git clone https://github.com/yourorg/pgtime
   cd pgtime/extension
   ```
2. Compile and install:
   ```bash
   make
   make install
   ```
3. Load the extension in your database:
   ```sql
   CREATE EXTENSION pgtime;
   ```

---

## Method 2: Package Managers (Coming Soon)

Pre-compiled registry distribution is planned. In the future, you will be able to install `pgtime` instantly without local compilation tools:

### Via pgxman (Planned)
```bash
pgxman install pgtime
```

### Via PGXN (Planned)
```bash
pgxn install pgtime
```
