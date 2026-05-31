# -*- coding: utf-8 -*-
"""
@file __init__.py
@description Python SDK for pgtime temporal tables extension
@module sdk/python/pgtime
"""

import re
from datetime import datetime
from typing import Any, Dict, List, Union
import psycopg2
import psycopg2.extras

class PgTime:
    """
    Python client wrapper for managing pgtime temporal tables.
    """
    def __init__(self, conn):
        """
        Initialize a new PgTime instance.
        
        :param conn: An active psycopg2 connection.
        """
        if not conn:
            raise ValueError("An active psycopg2 database connection is required.")
        self.conn = conn

    def _validate_table_name(self, table: str) -> None:
        """
        Validate table name format to prevent SQL injection.
        """
        table_regex = r"^[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z_][a-zA-Z0-9_]*)?$"
        if not re.match(table_regex, table):
            raise ValueError(
                f"Invalid table name: '{table}'. Only alphanumeric characters, "
                f"underscores, and a single dot schema separator are allowed."
            )

    def _get_tracked_metadata(self, table: str) -> Dict[str, Any]:
        """
        Resolve schema, table name, and primary key column for a tracked table.
        """
        self._validate_table_name(table)
        
        query = """
            SELECT schema_name, table_name, pk_column, pk_type
            FROM pgtime._tracked_tables
            WHERE table_name = %s OR (schema_name || '.' || table_name) = %s
            LIMIT 1;
        """
        
        with self.conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(query, (table, table))
            row = cur.fetchone()
            if not row:
                raise ValueError(f"Table '{table}' is not currently tracked by pgtime.")
            return row

    def attach(self, table: str) -> None:
        """
        Attach temporal version tracking to a table.
        
        :param table: Table name (optionally schema-prefixed).
        """
        self._validate_table_name(table)
        with self.conn.cursor() as cur:
            cur.execute("SELECT pgtime.attach(%s);", (table,))
        self.conn.commit()

    def detach(self, table: str) -> None:
        """
        Detach temporal tracking from a table, retaining the history data.
        
        :param table: Table name (optionally schema-prefixed).
        """
        self._validate_table_name(table)
        with self.conn.cursor() as cur:
            cur.execute("SELECT pgtime.detach(%s);", (table,))
        self.conn.commit()

    def as_of(self, table: str, timestamp: Union[datetime, str]) -> List[Dict[str, Any]]:
        """
        Fetch the point-in-time state (snapshot) of a table.
        
        :param table: Table name.
        :param timestamp: Target datetime object or ISO-8601 string.
        """
        meta = self._get_tracked_metadata(table)
        schema = meta["schema_name"]
        tbl = meta["table_name"]
        
        ts = timestamp
        if isinstance(ts, str):
            # Parse ISO string, mapping Z suffix to UTC offset
            ts = datetime.fromisoformat(ts.replace("Z", "+00:00"))
            
        query = f'SELECT * FROM "{schema}"."{tbl}_history" WHERE sys_from <= %s AND (sys_to IS NULL OR sys_to > %s);'
        
        with self.conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(query, (ts, ts))
            return cur.fetchall()

    def history(self, table: str, id: Any) -> List[Dict[str, Any]]:
        """
        Retrieve the complete change history (audit ledger) for a row by its primary key.
        
        :param table: Table name.
        :param id: Primary key value of the row.
        """
        meta = self._get_tracked_metadata(table)
        schema = meta["schema_name"]
        tbl = meta["table_name"]
        pk = meta["pk_column"]
        
        query = f'SELECT * FROM "{schema}"."{tbl}_history" WHERE "{pk}" = %s ORDER BY sys_from ASC;'
        
        with self.conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(query, (id,))
            return cur.fetchall()

    def diff(self, table: str, t_from: Union[datetime, str], t_to: Union[datetime, str]) -> List[Dict[str, Any]]:
        """
        Fetch rows modified or created in a table between two timestamps.
        
        :param table: Table name.
        :param t_from: Start boundary datetime or ISO-8601 string.
        :param t_to: End boundary datetime or ISO-8601 string.
        """
        meta = self._get_tracked_metadata(table)
        schema = meta["schema_name"]
        tbl = meta["table_name"]
        
        ts_from = t_from
        if isinstance(ts_from, str):
            ts_from = datetime.fromisoformat(ts_from.replace("Z", "+00:00"))
        ts_to = t_to
        if isinstance(ts_to, str):
            ts_to = datetime.fromisoformat(ts_to.replace("Z", "+00:00"))
            
        query = f'SELECT * FROM "{schema}"."{tbl}_history" WHERE sys_from > %s AND sys_from <= %s ORDER BY sys_from ASC;'
        
        with self.conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(query, (ts_from, ts_to))
            return cur.fetchall()
