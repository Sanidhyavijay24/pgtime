# -*- coding: utf-8 -*-
"""
@file python_example.py
@description Complete usage example for pgtime Python SDK
@module examples
"""

import sys
import os
import time
from datetime import datetime, timezone

# Add Python SDK directory to system path to import pgtime
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '../sdk/python')))

import psycopg2
from pgtime import PgTime

def run():
    conn = psycopg2.connect("postgres://postgres:pgtime@localhost:5432/pgtime_test")
    pt = PgTime(conn)

    with conn.cursor() as cur:
        print("Setting up example table...")
        cur.execute("DROP TABLE IF EXISTS public.example_users CASCADE;")
        cur.execute("DROP TABLE IF EXISTS public.example_users_history CASCADE;")
        cur.execute("""
            CREATE TABLE public.example_users (
                username TEXT PRIMARY KEY,
                email TEXT NOT NULL,
                active BOOLEAN DEFAULT TRUE
            );
        """)
    conn.commit()

    try:
        print("Attaching pgtime temporal tracking...")
        pt.attach("public.example_users")

        print("Inserting user...")
        with conn.cursor() as cur:
            cur.execute("INSERT INTO public.example_users VALUES ('alice', 'alice@old.com', TRUE);")
        conn.commit()
        t_insert = datetime.now(timezone.utc)
        time.sleep(0.1)

        print("Updating user email...")
        with conn.cursor() as cur:
            cur.execute("UPDATE public.example_users SET email = 'alice@new.com' WHERE username = 'alice';")
        conn.commit()
        t_update = datetime.now(timezone.utc)
        time.sleep(0.1)

        print("Deactivating user...")
        with conn.cursor() as cur:
            cur.execute("UPDATE public.example_users SET active = FALSE WHERE username = 'alice';")
        conn.commit()
        t_deactivate = datetime.now(timezone.utc)

        # Fetch snapshots
        print("\n--- Querying Snapshots (as_of) ---")
        state1 = pt.as_of("public.example_users", t_insert)
        print("State right after Insert:", state1)

        state2 = pt.as_of("public.example_users", t_update)
        print("State right after Update (email change):", state2)

        state3 = pt.as_of("public.example_users", t_deactivate)
        print("State right after Deactivation:", state3)

        # Fetch audit history
        print("\n--- Fetching Row Audit History (history) ---")
        audit_logs = pt.history("public.example_users", "alice")
        for log in audit_logs:
            print(f"OP: {log['_pgtime_op']} | Email: {log['email']} | Active: {log['active']} | Version Start: {log['sys_from']}")

        print("\nDetaching tracking...")
        pt.detach("public.example_users")
        
    except Exception as e:
        conn.rollback()
        print("Error occurred:", e)
    finally:
        with conn.cursor() as cur:
            cur.execute("DROP TABLE IF EXISTS public.example_users CASCADE;")
            cur.execute("DROP TABLE IF EXISTS public.example_users_history CASCADE;")
        conn.commit()
        conn.close()
        print("Finished example run successfully.")

if __name__ == "__main__":
    run()
