/**
 * @file index.ts
 * @description Node.js SDK for pgtime temporal tables extension
 * @module sdk/node/src
 */

import { Pool, Client } from 'pg';

export class PgTime {
  private client: Pool | Client;

  /**
   * Initialize a new PgTime instance.
   * @param client A pg Pool or Client instance.
   */
  constructor(client: Pool | Client) {
    if (!client) {
      throw new Error('A database client (Pool or Client from the pg package) is required.');
    }
    this.client = client;
  }

  /**
   * Helper to validate schema/table names to protect against SQL Injection.
   */
  private validateTableName(table: string): void {
    const tableRegex = /^[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z_][a-zA-Z0-9_]*)?$/;
    if (!tableRegex.test(table)) {
      throw new Error(
        `Invalid table name: "${table}". Only alphanumeric characters, underscores, and single dot schema separator are allowed.`
      );
    }
  }

  /**
   * Escape identifier for SQL queries to prevent injection.
   */
  private escapeIdentifier(str: string): string {
    return '"' + str.replace(/"/g, '""') + '"';
  }

  /**
   * Resolve a table name to its tracked metadata (schema, table, pk).
   */
  private async getTrackedMetadata(
    table: string
  ): Promise<{ schema_name: string; table_name: string; pk_column?: string }> {
    this.validateTableName(table);

    let query: string;
    let params: string[];

    if (table.includes('.')) {
      const parts = table.split('.');
      const schema = parts[0] ?? '';
      const name = parts[1] ?? '';
      query = `
        SELECT schema_name, table_name, pk_column 
        FROM pgtime._tracked_tables 
        WHERE schema_name = $1 AND table_name = $2
        LIMIT 1;
      `;
      params = [schema, name];
    } else {
      query = `
        SELECT schema_name, table_name, pk_column 
        FROM pgtime._tracked_tables 
        WHERE table_name = $1
        LIMIT 1;
      `;
      params = [table];
    }

    const res = await this.client.query(query, params);
    if (res.rowCount === 0) {
      throw new Error(`Table "${table}" is not currently tracked by pgtime.`);
    }

    return res.rows[0];
  }

  /**
   * Attach temporal version tracking to a table.
   * @param table Name of the table (optionally schema-prefixed).
   */
  async attach(table: string): Promise<void> {
    this.validateTableName(table);
    await this.client.query('SELECT pgtime.attach($1);', [table]);
  }

  /**
   * Detach temporal version tracking from a table (retains the history table).
   * @param table Name of the table (optionally schema-prefixed).
   */
  async detach(table: string): Promise<void> {
    this.validateTableName(table);
    await this.client.query('SELECT pgtime.detach($1);', [table]);
  }

  /**
   * Fetch the point-in-time state (snapshot) of a table.
   * @param table Name of the table.
   * @param timestamp Date or ISO string representing the target snapshot time.
   */
  async asOf<T = any>(table: string, timestamp: Date | string): Promise<T[]> {
    const { schema_name, table_name } = await this.getTrackedMetadata(table);
    const date = timestamp instanceof Date ? timestamp : new Date(timestamp);

    const escSchema = this.escapeIdentifier(schema_name);
    const escHistoryTable = this.escapeIdentifier(table_name + '_history');

    const query = `
      SELECT * FROM ${escSchema}.${escHistoryTable} 
      WHERE sys_from <= $1 AND (sys_to IS NULL OR sys_to > $1);
    `;

    const res = await this.client.query(query, [date]);
    return res.rows as T[];
  }

  /**
   * Retrieve the complete change history (audit ledger) for a row by its primary key.
   * @param table Name of the table.
   * @param id Primary key value of the row.
   */
  async history<T = any>(table: string, id: any): Promise<T[]> {
    const { schema_name, table_name, pk_column } = await this.getTrackedMetadata(table);

    const escSchema = this.escapeIdentifier(schema_name);
    const escHistoryTable = this.escapeIdentifier(table_name + '_history');
    const escPkColumn = this.escapeIdentifier(pk_column || '');

    const query = `
      SELECT * FROM ${escSchema}.${escHistoryTable} 
      WHERE ${escPkColumn} = $1 
      ORDER BY sys_from ASC;
    `;

    const res = await this.client.query(query, [id]);
    return res.rows as T[];
  }

  /**
   * Fetch rows modified or created in a table between two timestamps.
   * @param table Name of the table.
   * @param from Start boundary timestamp.
   * @param to End boundary timestamp.
   */
  async diff<T = any>(table: string, from: Date | string, to: Date | string): Promise<T[]> {
    const { schema_name, table_name } = await this.getTrackedMetadata(table);
    const dateFrom = from instanceof Date ? from : new Date(from);
    const dateTo = to instanceof Date ? to : new Date(to);

    if (dateFrom.getTime() >= dateTo.getTime()) {
      throw new Error(`The 'from' timestamp must be strictly earlier than the 'to' timestamp.`);
    }

    const escSchema = this.escapeIdentifier(schema_name);
    const escHistoryTable = this.escapeIdentifier(table_name + '_history');

    const query = `
      SELECT * FROM ${escSchema}.${escHistoryTable} 
      WHERE sys_from > $1 AND sys_from <= $2 
      ORDER BY sys_from ASC;
    `;

    const res = await this.client.query(query, [dateFrom, dateTo]);
    return res.rows as T[];
  }
}
