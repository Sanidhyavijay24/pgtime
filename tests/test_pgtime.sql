/**
 * @file test_pgtime.sql
 * @description pgTAP test suite for pgtime temporal tables extension
 * @module tests
 */

-- Setup pgTAP
CREATE EXTENSION IF NOT EXISTS pgtap;
CREATE EXTENSION IF NOT EXISTS pgtime;

-- Setup pgTAP plan (19 assertions total)
SELECT plan(19);

-- 1. Verify extension is loaded
SELECT has_extension('pgtime');

-- Setup test table (drop first to ensure clean slate)
DROP TABLE IF EXISTS public.items CASCADE;
DROP TABLE IF EXISTS public.items_history CASCADE;

CREATE TABLE public.items (
    id INT PRIMARY KEY,
    name TEXT NOT NULL,
    price NUMERIC
);

-- 2. Verify pgtime.attach() works
SELECT lives_ok(
    $$ SELECT pgtime.attach('public.items') $$,
    'pgtime.attach should attach temporal tracking to public.items successfully'
);

-- 3. Verify history table was created
SELECT has_table('public', 'items_history', 'History table public.items_history should be created');

-- 4-8. Verify history table has temporal tracking columns
SELECT has_column('public', 'items_history', 'sys_from', 'items_history must have sys_from');
SELECT has_column('public', 'items_history', 'sys_to', 'items_history must have sys_to');
SELECT has_column('public', 'items_history', 'valid_from', 'items_history must have valid_from');
SELECT has_column('public', 'items_history', 'valid_to', 'items_history must have valid_to');
SELECT has_column('public', 'items_history', '_pgtime_op', 'items_history must have _pgtime_op');

-- Create temporary table to log timestamps across transactions
CREATE TEMP TABLE test_timestamps (
    event TEXT PRIMARY KEY,
    ts TIMESTAMPTZ
);

-- 9. Test trigger on INSERT
INSERT INTO public.items (id, name, price) VALUES (1, 'Widget A', 10.99);
INSERT INTO test_timestamps VALUES ('after_insert', transaction_timestamp());

SELECT results_eq(
    $$ SELECT id, name, price, _pgtime_op::text FROM public.items_history $$,
    $$ VALUES (1, 'Widget A', 10.99::numeric, 'I') $$,
    'INSERT should trigger creation of a history row with operation code I'
);

-- 10. Test trigger on UPDATE
-- We perform update in a separate statement (so a different transaction timestamp is used)
UPDATE public.items SET price = 12.99 WHERE id = 1;
INSERT INTO test_timestamps VALUES ('after_update', transaction_timestamp());

SELECT results_eq(
    $$ SELECT price, _pgtime_op::text FROM public.items_history ORDER BY sys_from ASC $$,
    $$ VALUES (10.99::numeric, 'I'), (12.99::numeric, 'U') $$,
    'UPDATE should close the previous version and insert a new version with op U'
);

-- 11. Test trigger on DELETE
DELETE FROM public.items WHERE id = 1;
INSERT INTO test_timestamps VALUES ('after_delete', transaction_timestamp());

-- Under our design, DELETE updates the current active history row's _pgtime_op to 'D' and sets sys_to = now()
SELECT results_eq(
    $$ SELECT price, _pgtime_op::text FROM public.items_history ORDER BY sys_from ASC $$,
    $$ VALUES (10.99::numeric, 'I'), (12.99::numeric, 'D') $$,
    'DELETE should update the latest version to close it and set its op to D'
);

-- 12. Test pgtime.as_of() before first insert
SELECT is(
    (SELECT count(*)::int FROM public.items_as_of((SELECT ts - interval '10 seconds' FROM test_timestamps WHERE event = 'after_insert'))),
    0,
    'as_of a timestamp before first insert should return empty set'
);

-- 13. Test pgtime.as_of() after insert
SELECT set_eq(
    $$ SELECT id, name, price FROM public.items_as_of((SELECT ts FROM test_timestamps WHERE event = 'after_insert')) $$,
    $$ VALUES (1, 'Widget A', 10.99::numeric) $$,
    'as_of a timestamp during the first version should return the version details'
);

-- 14. Test pgtime.as_of() after update
SELECT set_eq(
    $$ SELECT id, name, price FROM public.items_as_of((SELECT ts FROM test_timestamps WHERE event = 'after_update')) $$,
    $$ VALUES (1, 'Widget A', 12.99::numeric) $$,
    'as_of a timestamp during the second version should return the updated details'
);

-- 15. Test pgtime.as_of() after delete
SELECT is(
    (SELECT count(*)::int FROM public.items_as_of((SELECT ts FROM test_timestamps WHERE event = 'after_delete'))),
    0,
    'as_of a timestamp after deletion should return empty set'
);

-- 16. Test pgtime.history() API
SELECT results_eq(
    $$ SELECT price, _pgtime_op::text FROM public.items_history(1) $$,
    $$ VALUES (10.99::numeric, 'I'), (12.99::numeric, 'D') $$,
    'pgtime.history should list the complete change ledger for a given row id'
);

-- 17. Test pgtime.versions() API
SELECT is(
    pgtime.versions('public.items', 1),
    2::bigint,
    'pgtime.versions should return version count of 2'
);

-- 18. Test pgtime.diff() API
SELECT results_eq(
    $$ SELECT price, _pgtime_op::text FROM public.items_diff((SELECT ts FROM test_timestamps WHERE event = 'after_insert'), (SELECT ts FROM test_timestamps WHERE event = 'after_delete')) $$,
    $$ VALUES (12.99::numeric, 'D') $$,
    'pgtime.diff should return rows created/modified between t1 and t2'
);

-- 19. Test pgtime.detach() API
SELECT lives_ok(
    $$ SELECT pgtime.detach('public.items') $$,
    'pgtime.detach should execute successfully'
);

-- Cleanup
DROP TABLE IF EXISTS public.items CASCADE;
DROP TABLE IF EXISTS public.items_history CASCADE;

-- Conclude tests
SELECT * FROM finish();
