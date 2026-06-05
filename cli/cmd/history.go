/**
 * @file history.go
 * @description history command setup for pgtime CLI
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
	historyFormat string
	historyID     string
)

var historyCmd = &cobra.Command{
	Use:   "history [table]",
	Short: "Show modification history of a row by its primary key value",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		if historyID == "" {
			fmt.Fprintln(os.Stderr, "Error: --id flag is required")
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

		// 1. Resolve table to schema and table name, and get primary key metadata
		var schemaName, tableName, pkColumn, pkType string
		err = conn.QueryRow(ctx, `
			SELECT schema_name, table_name, pk_column, pk_type 
			FROM pgtime._tracked_tables 
			WHERE table_name = $1 OR (schema_name || '.' || table_name) = $1
			LIMIT 1;
		`, table).Scan(&schemaName, &tableName, &pkColumn, &pkType)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: Table '%s' is not registered in pgtime. Check spelling or use 'list' command.\n", table)
			os.Exit(1)
		}

		// 2. Query the history table directly to allow dynamic column scanning
		ident := pgx.Identifier{schemaName, tableName + "_history"}
		historyQuery := fmt.Sprintf(
			"SELECT * FROM %s WHERE %s = $1 ORDER BY sys_from ASC;",
			ident.Sanitize(),
			pgx.Identifier{pkColumn}.Sanitize(),
		)

		rows, err := conn.Query(ctx, historyQuery, historyID)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error querying row history: %v\n", err)
			os.Exit(1)
		}
		defer rows.Close()

		// Get column names from the query descriptor
		fields := rows.FieldDescriptions()
		columns := make([]string, len(fields))
		for i, field := range fields {
			columns[i] = field.Name
		}

		// Read rows dynamically
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
			fmt.Printf("No history found for row with %s = %s\n", pkColumn, historyID)
			return
		}

		if historyFormat == "json" {
			data, _ := json.MarshalIndent(resultList, "", "  ")
			fmt.Println(string(data))
		} else {
			w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
			
			// Print header (dynamic columns)
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
	historyCmd.Flags().StringVar(&historyFormat, "format", "table", "Output format (table, json)")
	historyCmd.Flags().StringVar(&historyID, "id", "", "Primary key value of the row to trace (Required)")
	historyCmd.MarkFlagRequired("id")
	RootCmd.AddCommand(historyCmd)
}
