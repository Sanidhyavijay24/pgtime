/**
 * @file list.go
 * @description list command setup for pgtime CLI
 * @module cli/cmd
 */

package cmd

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"text/tabwriter"
	"time"

	"github.com/spf13/cobra"
)

var (
	listFormat string
)

var listCmd = &cobra.Command{
	Use:   "list",
	Short: "List all tracked tables and their metadata",
	Run: func(cmd *cobra.Command, args []string) {
		ctx := context.Background()
		conn, err := getConn(ctx)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error connecting to database: %v\n", err)
			os.Exit(1)
		}
		defer conn.Close(ctx)

		rows, err := conn.Query(ctx, "SELECT schema_name, table_name, pk_column, pk_type, attached_at FROM pgtime._tracked_tables ORDER BY schema_name, table_name;")
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error querying tracked tables: %v\n", err)
			os.Exit(1)
		}
		defer rows.Close()

		type TrackedTable struct {
			Schema     string    `json:"schema"`
			Table      string    `json:"table"`
			PKColumn   string    `json:"pk_column"`
			PKType     string    `json:"pk_type"`
			AttachedAt time.Time `json:"attached_at"`
		}

		var tables []TrackedTable
		for rows.Next() {
			var t TrackedTable
			err = rows.Scan(&t.Schema, &t.Table, &t.PKColumn, &t.PKType, &t.AttachedAt)
			if err != nil {
				fmt.Fprintf(os.Stderr, "Error scanning row: %v\n", err)
				os.Exit(1)
			}
			tables = append(tables, t)
		}

		if listFormat == "json" {
			data, _ := json.MarshalIndent(tables, "", "  ")
			fmt.Println(string(data))
		} else {
			w := tabwriter.NewWriter(os.Stdout, 0, 0, 3, ' ', 0)
			fmt.Fprintln(w, "SCHEMA\tTABLE\tPRIMARY KEY\tTYPE\tATTACHED AT")
			for _, t := range tables {
				fmt.Fprintf(w, "%s\t%s\t%s\t%s\t%s\n", t.Schema, t.Table, t.PKColumn, t.PKType, t.AttachedAt.Format(time.RFC3339))
			}
			w.Flush()
		}
	},
}

func init() {
	listCmd.Flags().StringVar(&listFormat, "format", "table", "Output format (table, json)")
	RootCmd.AddCommand(listCmd)
}
