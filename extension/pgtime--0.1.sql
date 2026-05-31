/**
 * @file pgtime--0.1.sql
 * @description SQL-level interface and PL/pgSQL setup for pgtime extension
 * @module extension
 */

-- Create schema if not exists
CREATE SCHEMA IF NOT EXISTS pgtime;

-- Internal metadata table
CREATE TABLE pgtime._tracked_tables (
  schema_name TEXT NOT NULL,
  table_name  TEXT NOT NULL,
  pk_column   TEXT NOT NULL,
  pk_type     TEXT NOT NULL,
  attached_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (schema_name, table_name)
);

-- Link the C trigger function
CREATE FUNCTION pgtime.pgtime_trigger_fn()
  RETURNS TRIGGER AS 'MODULE_PATHNAME', 'pgtime_trigger_fn' LANGUAGE C;

-- Public attach function
CREATE OR REPLACE FUNCTION pgtime.attach(target_table TEXT)
RETURNS VOID AS $$
DECLARE
  v_relid regclass;
  v_schema_name TEXT;
  v_table_name TEXT;
  v_pk_column TEXT;
  v_pk_type TEXT;
  v_history_table TEXT;
BEGIN
  -- Resolve table OID (throws error if table doesn't exist)
  v_relid := target_table::regclass;
  
  -- Extract actual schema and table name
  SELECT n.nspname, c.relname
  INTO v_schema_name, v_table_name
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.oid = v_relid;

  -- Validate that table is not already attached
  IF EXISTS (
    SELECT 1 
    FROM pgtime._tracked_tables 
    WHERE schema_name = v_schema_name AND table_name = v_table_name
  ) THEN
    RAISE EXCEPTION 'Table %.% is already attached to pgtime', v_schema_name, v_table_name;
  END IF;

  -- Find single-column primary key dynamically
  SELECT a.attname, format_type(a.atttypid, a.atttypmod)
  INTO v_pk_column, v_pk_type
  FROM pg_index i
  JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
  WHERE i.indrelid = v_relid
    AND i.indisprimary
    AND i.indnatts = 1;

  -- Enforce primary key existence
  IF v_pk_column IS NULL THEN
    RAISE EXCEPTION 'Table %.% must have a single-column primary key to attach pgtime', v_schema_name, v_table_name;
  END IF;

  v_history_table := v_table_name || '_history';

  -- Create history table mirroring the structure (excluding constraints and indexes)
  EXECUTE format('CREATE TABLE %I.%I (LIKE %I.%I INCLUDING DEFAULTS EXCLUDING CONSTRAINTS EXCLUDING INDEXES)',
                 v_schema_name, v_history_table, v_schema_name, v_table_name);

  -- Add temporal metadata and audit columns
  EXECUTE format('ALTER TABLE %I.%I 
                  ADD COLUMN sys_from TIMESTAMPTZ NOT NULL DEFAULT transaction_timestamp(),
                  ADD COLUMN sys_to TIMESTAMPTZ,
                  ADD COLUMN valid_from TIMESTAMPTZ,
                  ADD COLUMN valid_to TIMESTAMPTZ,
                  ADD COLUMN _pgtime_op CHAR(1)', 
                 v_schema_name, v_history_table);

  -- Create GiST index on transaction range for fast AS OF point-in-time scans
  EXECUTE format('CREATE INDEX %I ON %I.%I USING GIST (tstzrange(sys_from, sys_to))',
                 v_history_table || '_sys_range_idx', v_schema_name, v_history_table);

  -- Create partial index on primary key for active row version lookups
  EXECUTE format('CREATE INDEX %I ON %I.%I (%I) WHERE sys_to IS NULL',
                 v_history_table || '_pk_current_idx', v_schema_name, v_history_table, v_pk_column);

  -- Register table metadata
  INSERT INTO pgtime._tracked_tables (schema_name, table_name, pk_column, pk_type)
  VALUES (v_schema_name, v_table_name, v_pk_column, v_pk_type);

  -- Create and bind C-based AFTER ROW trigger to capture mutations
  EXECUTE format('CREATE TRIGGER pgtime_trig AFTER INSERT OR UPDATE OR DELETE ON %I.%I ' ||
                 'FOR EACH ROW EXECUTE FUNCTION pgtime.pgtime_trigger_fn()',
                 v_schema_name, v_table_name);
END;
$$ LANGUAGE plpgsql;

-- Public detach function (keeps history table, removes tracking and triggers)
CREATE OR REPLACE FUNCTION pgtime.detach(target_table TEXT)
RETURNS VOID AS $$
DECLARE
  v_relid regclass;
  v_schema_name TEXT;
  v_table_name TEXT;
  v_pk_column TEXT;
BEGIN
  -- Resolve table OID (throws error if table doesn't exist)
  v_relid := target_table::regclass;
  
  -- Extract actual schema and table name
  SELECT n.nspname, c.relname
  INTO v_schema_name, v_table_name
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.oid = v_relid;

  -- Verify tracking metadata
  SELECT pk_column INTO v_pk_column
  FROM pgtime._tracked_tables
  WHERE schema_name = v_schema_name AND table_name = v_table_name;

  IF v_pk_column IS NULL THEN
    RAISE EXCEPTION 'Table %.% is not currently attached to pgtime', v_schema_name, v_table_name;
  END IF;

  -- Drop trigger from source table
  EXECUTE format('DROP TRIGGER IF EXISTS pgtime_trig ON %I.%I', v_schema_name, v_table_name);

  -- Delete metadata entry
  DELETE FROM pgtime._tracked_tables
  WHERE schema_name = v_schema_name AND table_name = v_table_name;
END;
$$ LANGUAGE plpgsql;

-- Public as_of function to fetch point-in-time state
CREATE OR REPLACE FUNCTION pgtime.as_of(target_table TEXT, ts TIMESTAMPTZ)
RETURNS SETOF record AS $$
DECLARE
  v_relid regclass;
  v_schema_name TEXT;
  v_table_name TEXT;
  v_history_table TEXT;
  v_query TEXT;
BEGIN
  v_relid := target_table::regclass;
  
  SELECT n.nspname, c.relname
  INTO v_schema_name, v_table_name
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.oid = v_relid;

  IF NOT EXISTS (
    SELECT 1 FROM pgtime._tracked_tables 
    WHERE schema_name = v_schema_name AND table_name = v_table_name
  ) THEN
    RAISE EXCEPTION 'Table %.% is not tracked by pgtime', v_schema_name, v_table_name;
  END IF;

  v_history_table := quote_ident(v_schema_name) || '.' || quote_ident(v_table_name || '_history');
  v_query := format('SELECT * FROM %s WHERE sys_from <= $1 AND (sys_to IS NULL OR sys_to > $1)', v_history_table);
  
  RETURN QUERY EXECUTE v_query USING ts;
END;
$$ LANGUAGE plpgsql;

-- Public history function to fetch versions of a specific row by primary key
CREATE OR REPLACE FUNCTION pgtime.history(target_table TEXT, row_id anyelement)
RETURNS SETOF record AS $$
DECLARE
  v_relid regclass;
  v_schema_name TEXT;
  v_table_name TEXT;
  v_pk_column TEXT;
  v_history_table TEXT;
  v_query TEXT;
BEGIN
  v_relid := target_table::regclass;
  
  SELECT n.nspname, c.relname
  INTO v_schema_name, v_table_name
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.oid = v_relid;

  SELECT pk_column INTO v_pk_column
  FROM pgtime._tracked_tables
  WHERE schema_name = v_schema_name AND table_name = v_table_name;

  IF v_pk_column IS NULL THEN
    RAISE EXCEPTION 'Table %.% is not tracked by pgtime', v_schema_name, v_table_name;
  END IF;

  v_history_table := quote_ident(v_schema_name) || '.' || quote_ident(v_table_name || '_history');
  v_query := format('SELECT * FROM %s WHERE %I = $1 ORDER BY sys_from ASC', v_history_table, v_pk_column);
  
  RETURN QUERY EXECUTE v_query USING row_id;
END;
$$ LANGUAGE plpgsql;

-- Public versions function to count versions of a specific row
CREATE OR REPLACE FUNCTION pgtime.versions(target_table TEXT, row_id anyelement)
RETURNS BIGINT AS $$
DECLARE
  v_relid regclass;
  v_schema_name TEXT;
  v_table_name TEXT;
  v_pk_column TEXT;
  v_history_table TEXT;
  v_query TEXT;
  v_count BIGINT;
BEGIN
  v_relid := target_table::regclass;
  
  SELECT n.nspname, c.relname
  INTO v_schema_name, v_table_name
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.oid = v_relid;

  SELECT pk_column INTO v_pk_column
  FROM pgtime._tracked_tables
  WHERE schema_name = v_schema_name AND table_name = v_table_name;

  IF v_pk_column IS NULL THEN
    RAISE EXCEPTION 'Table %.% is not tracked by pgtime', v_schema_name, v_table_name;
  END IF;

  v_history_table := quote_ident(v_schema_name) || '.' || quote_ident(v_table_name || '_history');
  v_query := format('SELECT count(*) FROM %s WHERE %I = $1', v_history_table, v_pk_column);
  
  EXECUTE v_query INTO v_count USING row_id;
  RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- Public diff function to see changes between two points in time
CREATE OR REPLACE FUNCTION pgtime.diff(target_table TEXT, t1 TIMESTAMPTZ, t2 TIMESTAMPTZ)
RETURNS SETOF record AS $$
DECLARE
  v_relid regclass;
  v_schema_name TEXT;
  v_table_name TEXT;
  v_history_table TEXT;
  v_query TEXT;
BEGIN
  v_relid := target_table::regclass;
  
  SELECT n.nspname, c.relname
  INTO v_schema_name, v_table_name
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.oid = v_relid;

  IF NOT EXISTS (
    SELECT 1 FROM pgtime._tracked_tables 
    WHERE schema_name = v_schema_name AND table_name = v_table_name
  ) THEN
    RAISE EXCEPTION 'Table %.% is not tracked by pgtime', v_schema_name, v_table_name;
  END IF;

  v_history_table := quote_ident(v_schema_name) || '.' || quote_ident(v_table_name || '_history');
  v_query := format('SELECT * FROM %s WHERE sys_from > $1 AND sys_from <= $2 ORDER BY sys_from ASC', v_history_table);
  
  RETURN QUERY EXECUTE v_query USING t1, t2;
END;
$$ LANGUAGE plpgsql;
