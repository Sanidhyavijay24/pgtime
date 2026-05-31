/**
 * @file root.go
 * @description Root command setup and database connection helpers for pgtime CLI
 * @module cli/cmd
 */

package cmd

import (
	"context"
	"fmt"
	"os"

	"github.com/jackc/pgx/v5"
	"github.com/spf13/cobra"
)

var (
	dbURL   string
	RootCmd = &cobra.Command{
		Use:   "pgtime",
		Short: "pgtime CLI manages temporal table versioning in PostgreSQL",
	}
)

func init() {
	RootCmd.PersistentFlags().StringVar(&dbURL, "db", "", "Database URL (defaults to DATABASE_URL environment variable)")
}

func getConn(ctx context.Context) (*pgx.Conn, error) {
	connStr := dbURL
	if connStr == "" {
		connStr = os.Getenv("DATABASE_URL")
	}
	if connStr == "" {
		return nil, fmt.Errorf("database URL not specified. Use --db flag or set DATABASE_URL environment variable")
	}
	return pgx.Connect(ctx, connStr)
}
