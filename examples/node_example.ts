/**
 * @file node_example.ts
 * @description Complete usage example for pgtime Node SDK
 * @module examples
 */

import { Pool } from 'pg';
import { PgTime } from '../sdk/node/src/index';

const pool = new Pool({
  connectionString: "postgres://postgres:pgtime@localhost:5432/pgtime_test"
});
const pt = new PgTime(pool);

async function run() {
  console.log("Setting up example table...");
  await pool.query("DROP TABLE IF EXISTS public.example_orders CASCADE;");
  await pool.query("DROP TABLE IF EXISTS public.example_orders_history CASCADE;");
  await pool.query(`
    CREATE TABLE public.example_orders (
      id INT PRIMARY KEY,
      item TEXT NOT NULL,
      price NUMERIC
    );
  `);

  console.log("Attaching pgtime temporal tracking...");
  await pt.attach("public.example_orders");

  console.log("Inserting a record...");
  await pool.query("INSERT INTO public.example_orders VALUES (1, 'Espresso Machine', 899.99);");
  const tInsert = new Date();
  await new Promise(r => setTimeout(r, 100));

  console.log("Updating the record (price drop)...");
  await pool.query("UPDATE public.example_orders SET price = 799.99 WHERE id = 1;");
  const tUpdate = new Date();
  await new Promise(r => setTimeout(r, 100));

  console.log("Deleting the record...");
  await pool.query("DELETE FROM public.example_orders WHERE id = 1;");
  const tDelete = new Date();

  // Fetch snapshots
  console.log("\n--- Querying Snapshots (asOf) ---");
  const state1 = await pt.asOf("public.example_orders", tInsert);
  console.log("State right after Insert:", state1);

  const state2 = await pt.asOf("public.example_orders", tUpdate);
  console.log("State right after Update (price drop):", state2);

  const state3 = await pt.asOf("public.example_orders", tDelete);
  console.log("State right after Delete:", state3);

  // Fetch full history logs
  console.log("\n--- Fetching Row Audit History (history) ---");
  const auditLogs = await pt.history("public.example_orders", 1);
  console.log(auditLogs);

  console.log("\nDetaching tracking...");
  await pt.detach("public.example_orders");

  // Cleanup
  await pool.query("DROP TABLE IF EXISTS public.example_orders CASCADE;");
  await pool.query("DROP TABLE IF EXISTS public.example_orders_history CASCADE;");
  await pool.end();
  console.log("Finished example run successfully.");
}

run().catch(console.error);
