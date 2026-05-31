# -*- coding: utf-8 -*-
"""
@file test_pgtime.py
@description Pytest integration tests for pgtime Python SDK
@module sdk/python/tests
"""

import time
from datetime import datetime, timezone, timedelta
import psycopg2
import pytest
from pgtime import PgTime

@pytest.fixture(scope="module")
def db_conn():
    conn = psycopg2.connect("postgres://postgres:pgtime@localhost:5432/pgtime_test")
    yield conn
    conn.close()

def test_e2e_sdk_flow(db_conn):
    pt = PgTime(db_conn)
    
    # Drop test tables and clear tracking metadata first
    with db_conn.cursor() as cur:
        cur.execute("DELETE FROM pgtime._tracked_tables WHERE table_name = 'py_items';")
        cur.execute("DROP TABLE IF EXISTS public.py_items CASCADE;")
        cur.execute("DROP TABLE IF EXISTS public.py_items_history CASCADE;")
    db_conn.commit()
    
    # Create test table
    with db_conn.cursor() as cur:
        cur.execute("""
            CREATE TABLE public.py_items (
                id INT PRIMARY KEY,
                name TEXT NOT NULL,
                price NUMERIC
            );
        """)
    db_conn.commit()
    
    try:
        # 1. Attach tracking
        pt.attach("public.py_items")
        
        # Verify metadata registration
        meta = pt._get_tracked_metadata("public.py_items")
        assert meta["table_name"] == "py_items"
        assert meta["pk_column"] == "id"
        
        # 2. INSERT
        with db_conn.cursor() as cur:
            cur.execute("INSERT INTO public.py_items (id, name, price) VALUES (1, 'Latte', 4.50);")
        db_conn.commit()
        
        time.sleep(0.1)
        
        # 3. UPDATE
        with db_conn.cursor() as cur:
            cur.execute("UPDATE public.py_items SET price = 3.99 WHERE id = 1;")
        db_conn.commit()
        
        time.sleep(0.1)
        
        # 4. DELETE
        with db_conn.cursor() as cur:
            cur.execute("DELETE FROM public.py_items WHERE id = 1;")
        db_conn.commit()
        
        # Retrieve the exact database-recorded transaction timestamps
        with db_conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("SELECT sys_from, sys_to FROM public.py_items_history ORDER BY sys_from ASC;")
            history_records = cur.fetchall()
            
        assert len(history_records) == 2
        t_insert_db = history_records[0]["sys_from"]
        t_update_db = history_records[1]["sys_from"]
        t_delete_db = history_records[1]["sys_to"]
        
        # 5. Test as_of snapshots
        # Before insert (1 second before t_insert_db)
        t_before = t_insert_db - timedelta(seconds=1)
        res_before = pt.as_of("public.py_items", t_before)
        assert len(res_before) == 0
        
        # After insert
        res_insert = pt.as_of("public.py_items", t_insert_db)
        assert len(res_insert) == 1
        assert res_insert[0]["name"] == "Latte"
        assert float(res_insert[0]["price"]) == 4.50
        
        # After update
        res_update = pt.as_of("public.py_items", t_update_db)
        assert len(res_update) == 1
        assert float(res_update[0]["price"]) == 3.99
        
        # After delete
        res_delete = pt.as_of("public.py_items", t_delete_db)
        assert len(res_delete) == 0
        
        # 6. Test history API
        history = pt.history("public.py_items", 1)
        assert len(history) == 2
        assert history[0]["_pgtime_op"] == "I"
        assert float(history[0]["price"]) == 4.50
        assert history[1]["_pgtime_op"] == "D"
        assert float(history[1]["price"]) == 3.99
        
        # 7. Test diff API
        diff = pt.diff("public.py_items", t_insert_db, t_delete_db)
        assert len(diff) == 1
        assert diff[0]["_pgtime_op"] == "D"
        
        # 8. Detach
        pt.detach("public.py_items")
        with pytest.raises(ValueError):
            pt._get_tracked_metadata("public.py_items")
            
    except Exception:
        db_conn.rollback()
        raise
    finally:
        # Cleanup test tables and metadata
        with db_conn.cursor() as cur:
            cur.execute("DELETE FROM pgtime._tracked_tables WHERE table_name = 'py_items';")
            cur.execute("DROP TABLE IF EXISTS public.py_items CASCADE;")
            cur.execute("DROP TABLE IF EXISTS public.py_items_history CASCADE;")
        db_conn.commit()
