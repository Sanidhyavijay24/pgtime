/**
 * @file diff.go
 * @description diff command setup for pgtime CLI
 * @module cli/cmd
 */

package cmd

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"text/tabwriter"

	"github.com/jackc/pgx/v5"
	"github.com/spf13/cobra"
)

var (
	diffFormat string
	diffFrom   string
	diffTo     string
)

var diffCmd = &cobra.Command{
	Use:   "diff [table]",
	Short: "Show changes made in a table between two timestamps",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		if diffFrom == "" || diffTo == "" {
			fmt.Fprintln(os.Stderr, "Error: both --from and --to flags are required")
			os.Exit(1)
		}

		ctx := context.Background()
		table := args[0]

		conn, err := getConn(ctx)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error connecting to database: %v\n", err)
			os.Exit(1)
		}
		defer conn.Close(ctx)

		// 1. Resolve table schema and check registration
		var schemaName, tableName string
		err = conn.QueryRow(ctx, `
			SELECT schema_name, table_name 
			FROM pgtime._tracked_tables 
			WHERE table_name = $1 OR (schema_name || '.' || table_name) = $1
			LIMIT 1;
		`, table).Scan(&schemaName, &tableName)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: Table '%s' is not tracked by pgtime.\n", table)
			os.Exit(1)
		}

		// 2. Query history table for changes in the time range
		ident := pgx.Identifier{schemaName, tableName + "_history"}
		diffQuery := fmt.Sprintf(
			"SELECT * FROM %s WHERE sys_from > $1 AND sys_from <= $2 ORDER BY sys_from ASC;",
			ident.Sanitize(),
		)

		rows, err := conn.Query(ctx, diffQuery, diffFrom, diffTo)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error executing diff query: %v\n", err)
			os.Exit(1)
		}
		defer rows.Close()

		fields := rows.FieldDescriptions()
		columns := make([]string, len(fields))
		for i, field := range fields {
			columns[i] = field.Name
		}

		var resultList []map[string]interface{}
		for rows.Next() {
			values, err := rows.Values()
			if err != nil {
				fmt.Fprintf(os.Stderr, "Error reading values: %v\n", err)
				os.Exit(1)
			}

			rowMap := make(map[string]interface{})
			for i, colName := range columns {
				rowMap[colName] = values[i]
			}
			resultList = append(resultList, rowMap)
		}

		if len(resultList) == 0 {
			fmt.Printf("No changes found in table %s.%s between %s and %s\n", schemaName, tableName, diffFrom, diffTo)
			return
		}

		if diffFormat == "json" {
			data, err := json.MarshalIndent(resultList, "", "  ")
			if err != nil {
				fmt.Fprintf(os.Stderr, "Error formatting JSON output: %v\n", err)
				os.Exit(1)
			}
			fmt.Println(string(data))
		} else {
			w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
			
			// Print header
			for i, col := range columns {
				if i > 0 {
					fmt.Fprint(w, "\t")
				}
				fmt.Fprint(w, col)
			}
			fmt.Fprintln(w)

			// Print values
			for _, rowMap := range resultList {
				for i, col := range columns {
					if i > 0 {
						fmt.Fprint(w, "\t")
					}
					fmt.Fprintf(w, "%v", rowMap[col])
				}
				fmt.Fprintln(w)
			}
			w.Flush()
		}
	},
}

func init() {
	diffCmd.Flags().StringVar(&diffFormat, "format", "table", "Output format (table, json)")
	diffCmd.Flags().StringVar(&diffFrom, "from", "", "Start timestamp (Required)")
	diffCmd.Flags().StringVar(&diffTo, "to", "", "End timestamp (Required)")
	diffCmd.MarkFlagRequired("from")
	diffCmd.MarkFlagRequired("to")
	RootCmd.AddCommand(diffCmd)
}
