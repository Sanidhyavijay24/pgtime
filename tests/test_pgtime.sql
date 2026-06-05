/**
 * @file test_pgtime.sql
 * @description pgTAP test suite for pgtime temporal tables extension
 * @module tests
 */

-- Setup pgTAP
CREATE EXTENSION IF NOT EXISTS pgtap;
CREATE EXTENSION IF NOT EXISTS pgtime;

-- Setup pgTAP plan (29 assertions total)
SELECT plan(29);

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

-- Setup for additional audits (Multi-UPDATE, Detach validation, Multi-schema namespaces)
-- Create second test table for multi-update and detach checks
CREATE TABLE public.items2 (
    id INT PRIMARY KEY,
    name TEXT NOT NULL
);

-- 20. Attach items2
SELECT lives_ok(
    $$ SELECT pgtime.attach('public.items2') $$,
    'pgtime.attach should attach tracking to items2 successfully'
);

-- Perform multi-update
INSERT INTO public.items2 (id, name) VALUES (10, 'Alpha');
UPDATE public.items2 SET name = 'Beta' WHERE id = 10;
UPDATE public.items2 SET name = 'Gamma' WHERE id = 10;

-- 21. Verify 3 history versions exist (I, U, U)
SELECT results_eq(
    $$ SELECT name, _pgtime_op::text FROM public.items2_history ORDER BY sys_from ASC $$,
    $$ VALUES ('Alpha', 'I'), ('Beta', 'U'), ('Gamma', 'U') $$,
    'Multi-update sequence should create 3 versions: I, U, U'
);

-- 22. Detach items2
SELECT lives_ok(
    $$ SELECT pgtime.detach('public.items2') $$,
    'pgtime.detach should detach tracking from items2 successfully'
);

-- Perform insert/update post-detach (should not be logged to history)
INSERT INTO public.items2 (id, name) VALUES (20, 'Delta');
UPDATE public.items2 SET name = 'Epsilon' WHERE id = 10;

-- 23. Verify history count did not change
SELECT is(
    (SELECT count(*)::int FROM public.items2_history),
    3,
    'Operations after detach should not write to history table'
);

-- Clean up items2
DROP TABLE IF EXISTS public.items2 CASCADE;
DROP TABLE IF EXISTS public.items2_history CASCADE;

-- Test Multi-schema namespace conflicts
CREATE SCHEMA schema_a;
CREATE SCHEMA schema_b;

CREATE TABLE schema_a.users (
    id INT PRIMARY KEY,
    username TEXT NOT NULL
);

CREATE TABLE schema_b.users (
    id INT PRIMARY KEY,
    username TEXT NOT NULL
);

-- 24. Attach schema_a.users
SELECT lives_ok(
    $$ SELECT pgtime.attach('schema_a.users') $$,
    'Attach on schema_a.users should succeed'
);

-- 25. Attach schema_b.users
SELECT lives_ok(
    $$ SELECT pgtime.attach('schema_b.users') $$,
    'Attach on schema_b.users should succeed'
);

-- Perform writes in different schemas
INSERT INTO schema_a.users VALUES (1, 'alice_a');
INSERT INTO schema_b.users VALUES (1, 'bob_b');

-- 26. Verify schema_a.users_history has correct records
SELECT results_eq(
    $$ SELECT username, _pgtime_op::text FROM schema_a.users_history $$,
    $$ VALUES ('alice_a', 'I') $$,
    'schema_a history trigger should fire independently'
);

-- 27. Verify schema_b.users_history has correct records
SELECT results_eq(
    $$ SELECT username, _pgtime_op::text FROM schema_b.users_history $$,
    $$ VALUES ('bob_b', 'I') $$,
    'schema_b history trigger should fire independently'
);

-- 28. Detach schema_a.users
SELECT lives_ok(
    $$ SELECT pgtime.detach('schema_a.users') $$,
    'Detach on schema_a.users should succeed'
);

-- 29. Detach schema_b.users
SELECT lives_ok(
    $$ SELECT pgtime.detach('schema_b.users') $$,
    'Detach on schema_b.users should succeed'
);

-- Cleanup schemas
DROP SCHEMA schema_a CASCADE;
DROP SCHEMA schema_b CASCADE;

-- Cleanup main items
DROP TABLE IF EXISTS public.items CASCADE;
DROP TABLE IF EXISTS public.items_history CASCADE;

-- Conclude tests
SELECT * FROM finish();
