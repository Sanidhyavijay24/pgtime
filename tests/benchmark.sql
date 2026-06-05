-- Disable client printout noise
SET client_min_messages = WARNING;

-- Clean slate
DELETE FROM pgtime._tracked_tables WHERE schema_name = 'public' AND table_name = 'bench_tracked';
DROP TABLE IF EXISTS public.bench_plain CASCADE;
DROP TABLE IF EXISTS public.bench_tracked CASCADE;
DROP TABLE IF EXISTS public.bench_tracked_history CASCADE;
DROP FUNCTION IF EXISTS public.bench_tracked_as_of(TIMESTAMPTZ);
DROP FUNCTION IF EXISTS public.bench_tracked_history(anyelement);
DROP FUNCTION IF EXISTS public.bench_tracked_diff(TIMESTAMPTZ, TIMESTAMPTZ);

-- Create plain table
CREATE TABLE public.bench_plain (
    id INT PRIMARY KEY,
    name TEXT,
    val NUMERIC
);

-- Create tracked table
CREATE TABLE public.bench_tracked (
    id INT PRIMARY KEY,
    name TEXT,
    val NUMERIC
);

-- Attach pgtime to tracked table
SELECT pgtime.attach('public.bench_tracked');

-- Benchmark function
CREATE OR REPLACE FUNCTION public.run_pgtime_benchmark(num_iterations INT)
RETURNS TABLE(op TEXT, plain_ms NUMERIC, tracked_ms NUMERIC, overhead_pct TEXT) AS $$
DECLARE
    t_start TIMESTAMPTZ;
    t_end TIMESTAMPTZ;
    d_plain_insert NUMERIC;
    d_tracked_insert NUMERIC;
    d_plain_update NUMERIC;
    d_tracked_update NUMERIC;
    d_plain_delete NUMERIC;
    d_tracked_delete NUMERIC;
BEGIN
    -- 1. INSERT BENCHMARK
    -- Plain INSERT
    t_start := clock_timestamp();
    FOR i IN 1..num_iterations LOOP
        INSERT INTO public.bench_plain VALUES (i, 'item_' || i, i * 1.5);
    END LOOP;
    t_end := clock_timestamp();
    d_plain_insert := EXTRACT(EPOCH FROM (t_end - t_start)) * 1000.0;

    -- Tracked INSERT
    t_start := clock_timestamp();
    FOR i IN 1..num_iterations LOOP
        INSERT INTO public.bench_tracked VALUES (i, 'item_' || i, i * 1.5);
    END LOOP;
    t_end := clock_timestamp();
    d_tracked_insert := EXTRACT(EPOCH FROM (t_end - t_start)) * 1000.0;

    -- 2. UPDATE BENCHMARK
    -- Plain UPDATE
    t_start := clock_timestamp();
    FOR i IN 1..num_iterations LOOP
        UPDATE public.bench_plain SET val = val + 1.0 WHERE id = i;
    END LOOP;
    t_end := clock_timestamp();
    d_plain_update := EXTRACT(EPOCH FROM (t_end - t_start)) * 1000.0;

    -- Tracked UPDATE
    t_start := clock_timestamp();
    FOR i IN 1..num_iterations LOOP
        UPDATE public.bench_tracked SET val = val + 1.0 WHERE id = i;
    END LOOP;
    t_end := clock_timestamp();
    d_tracked_update := EXTRACT(EPOCH FROM (t_end - t_start)) * 1000.0;

    -- 3. DELETE BENCHMARK
    -- Plain DELETE
    t_start := clock_timestamp();
    FOR i IN 1..num_iterations LOOP
        DELETE FROM public.bench_plain WHERE id = i;
    END LOOP;
    t_end := clock_timestamp();
    d_plain_delete := EXTRACT(EPOCH FROM (t_end - t_start)) * 1000.0;

    -- Tracked DELETE
    t_start := clock_timestamp();
    FOR i IN 1..num_iterations LOOP
        DELETE FROM public.bench_tracked WHERE id = i;
    END LOOP;
    t_end := clock_timestamp();
    d_tracked_delete := EXTRACT(EPOCH FROM (t_end - t_start)) * 1000.0;

    -- Return comparative results
    op := 'INSERT';
    plain_ms := round(d_plain_insert, 2);
    tracked_ms := round(d_tracked_insert, 2);
    overhead_pct := round(((d_tracked_insert - d_plain_insert) / d_plain_insert) * 100.0, 2)::text || '%';
    RETURN NEXT;

    op := 'UPDATE';
    plain_ms := round(d_plain_update, 2);
    tracked_ms := round(d_tracked_update, 2);
    overhead_pct := round(((d_tracked_update - d_plain_update) / d_plain_update) * 100.0, 2)::text || '%';
    RETURN NEXT;

    op := 'DELETE';
    plain_ms := round(d_plain_delete, 2);
    tracked_ms := round(d_tracked_delete, 2);
    overhead_pct := round(((d_tracked_delete - d_plain_delete) / d_plain_delete) * 100.0, 2)::text || '%';
    RETURN NEXT;
END;
$$ LANGUAGE plpgsql;
