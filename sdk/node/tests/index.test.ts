/**
 * @file index.test.ts
 * @description Bun integration tests for pgtime Node SDK
 * @module sdk/node/tests
 */

import { expect, test, beforeAll, afterAll } from "bun:test";
import { Pool } from "pg";
import { PgTime } from "../src/index";

let pool: Pool;
let pt: PgTime;

beforeAll(async () => {
  pool = new Pool({
    connectionString: "postgres://postgres:pgtime@localhost:5432/pgtime_test",
  });
  pt = new PgTime(pool);

  // Clean slate
  await pool.query("DELETE FROM pgtime._tracked_tables WHERE table_name = 'sdk_items';");
  await pool.query("DROP TABLE IF EXISTS public.sdk_items CASCADE;");
  await pool.query("DROP TABLE IF EXISTS public.sdk_items_history CASCADE;");

  // Create test table
  await pool.query(`
    CREATE TABLE public.sdk_items (
      id SERIAL PRIMARY KEY,
      name TEXT NOT NULL,
      price NUMERIC
    );
  `);
});

afterAll(async () => {
  await pool.query("DROP TABLE IF EXISTS public.sdk_items CASCADE;");
  await pool.query("DROP TABLE IF EXISTS public.sdk_items_history CASCADE;");
  await pool.end();
});

test("E2E Sdk Flow", async () => {
  // 1. Attach temporal tracking
  await pt.attach("public.sdk_items");

  // Verify registration
  const trackedRes = await pool.query(
    "SELECT 1 FROM pgtime._tracked_tables WHERE table_name = 'sdk_items';"
  );
  expect(trackedRes.rowCount).toBe(1);

  // 2. Perform INSERT
  await pool.query(
    "INSERT INTO public.sdk_items (id, name, price) VALUES (1, 'Tablet', 299.99);"
  );
  
  // Sleep to ensure timestamps partition cleanly
  await new Promise((resolve) => setTimeout(resolve, 100));
 
  // 3. Perform UPDATE
  await pool.query(
    "UPDATE public.sdk_items SET price = 249.99 WHERE id = 1;"
  );
 
  await new Promise((resolve) => setTimeout(resolve, 100));
 
  // 4. Perform DELETE
  await pool.query(
    "DELETE FROM public.sdk_items WHERE id = 1;"
  );

  // Retrieve the exact database-recorded transaction timestamps
  const dbTimestamps = await pool.query(
    "SELECT sys_from, sys_to FROM public.sdk_items_history ORDER BY sys_from ASC;"
  );
  expect(dbTimestamps.rows.length).toBe(2);
  const tInsert = dbTimestamps.rows[0].sys_from; // Date object
  const tUpdate = dbTimestamps.rows[1].sys_from; // Date object
  const tDelete = dbTimestamps.rows[1].sys_to;   // Date object
 
  // 5. Test asOf API
  // Before insert: should be empty
  const beforeInsertRes = await pt.asOf("public.sdk_items", new Date(tInsert.getTime() - 1000));
  expect(beforeInsertRes.length).toBe(0);
 
  // After insert: should have tablet at 299.99
  const afterInsertRes = await pt.asOf("public.sdk_items", new Date(tInsert.getTime() + 50));
  expect(afterInsertRes.length).toBe(1);
  expect(afterInsertRes[0].name).toBe("Tablet");
  expect(Number(afterInsertRes[0].price)).toBe(299.99);
 
  // After update: should have tablet at 249.99
  const afterUpdateRes = await pt.asOf("public.sdk_items", new Date(tUpdate.getTime() + 50));
  expect(afterUpdateRes.length).toBe(1);
  expect(Number(afterUpdateRes[0].price)).toBe(249.99);
 
  // After delete: should be empty
  const afterDeleteRes = await pt.asOf("public.sdk_items", new Date(tDelete.getTime() + 50));
  expect(afterDeleteRes.length).toBe(0);

  // 6. Test history API
  const historyRes = await pt.history("public.sdk_items", 1);
  expect(historyRes.length).toBe(2);
  expect(historyRes[0]._pgtime_op).toBe("I");
  expect(Number(historyRes[0].price)).toBe(299.99);
  expect(historyRes[1]._pgtime_op).toBe("D"); // Closed by delete
  expect(Number(historyRes[1].price)).toBe(249.99);

  // 7. Test diff API
  const diffRes = await pt.diff("public.sdk_items", new Date(tInsert.getTime() + 50), tDelete);
  expect(diffRes.length).toBe(1); // returns modification update
  expect(diffRes[0]._pgtime_op).toBe("D");

  // 8. Test detach API
  await pt.detach("public.sdk_items");
  const trackedResAfter = await pool.query(
    "SELECT 1 FROM pgtime._tracked_tables WHERE table_name = 'sdk_items';"
  );
  expect(trackedResAfter.rowCount).toBe(0);
});
