/**
 * @file pgtime.c
 * @description AFTER ROW C trigger for tracking temporal table history
 * @module extension
 */

#include "postgres.h"
#include "fmgr.h"
#include "executor/spi.h"
#include "commands/trigger.h"
#include "utils/rel.h"
#include "utils/lsyscache.h"
#include "utils/builtins.h"
#include "catalog/pg_type.h"
#include "lib/stringinfo.h"

PG_MODULE_MAGIC;

#define MAX_CACHE_ENTRIES 64

typedef struct {
    Oid relid;
    char pk_col[NAMEDATALEN];
    Oid pk_type_oid;
    bool is_valid;
} RelationMetadataCacheEntry;

static RelationMetadataCacheEntry rel_metadata_cache[MAX_CACHE_ENTRIES];
static int rel_metadata_cache_count = 0;

PG_FUNCTION_INFO_V1(pgtime_trigger_fn);

static bool get_pk_metadata(const char *schema_name, const char *table_name, char **pk_col, Oid *pk_type_oid) {
    int ret;
    bool found = false;
    TupleDesc tupdesc;
    HeapTuple tuple;
    char *col;
    
    // Query metadata from pgtime._tracked_tables
    const char *query = "SELECT pk_column, pk_type::regtype::oid FROM pgtime._tracked_tables WHERE schema_name = $1 AND table_name = $2";
    
    Oid argtypes[2] = {TEXTOID, TEXTOID};
    Datum values[2];
    
    values[0] = PointerGetDatum(cstring_to_text(schema_name));
    values[1] = PointerGetDatum(cstring_to_text(table_name));
    
    ret = SPI_execute_with_args(query, 2, argtypes, values, NULL, true, 1);
    if (ret == SPI_OK_SELECT && SPI_processed > 0) {
        tupdesc = SPI_tuptable->tupdesc;
        tuple = SPI_tuptable->vals[0];
        
        col = SPI_getvalue(tuple, tupdesc, 1);
        if (col) {
            bool is_null;
            Datum type_oid_datum;
            
            *pk_col = pstrdup(col);
            
            type_oid_datum = SPI_getbinval(tuple, tupdesc, 2, &is_null);
            if (!is_null) {
                *pk_type_oid = DatumGetObjectId(type_oid_datum);
            } else {
                *pk_type_oid = InvalidOid;
            }
            found = true;
        }
    }
    
    return found;
}

Datum pgtime_trigger_fn(PG_FUNCTION_ARGS) {
    TriggerData *trigdata = (TriggerData *) fcinfo->context;
    Relation rel;
    HeapTuple old_tuple = NULL;
    HeapTuple new_tuple = NULL;
    char op;
    int ret;
    char *relname;
    Oid nspoid;
    char *nspname;
    char *pk_col = NULL;
    Oid pk_type_oid = InvalidOid;
    Oid relid;
    bool cache_found = false;
    char *history_table_name = NULL;
    
    // Safety checks
    if (!CALLED_AS_TRIGGER(fcinfo)) {
        elog(ERROR, "pgtime_trigger_fn: not called by trigger manager");
    }
    
    rel = trigdata->tg_relation;
    relid = RelationGetRelid(rel);
    
    if (TRIGGER_FIRED_BY_INSERT(trigdata->tg_event)) {
        new_tuple = trigdata->tg_trigtuple;
        op = 'I';
    } else if (TRIGGER_FIRED_BY_UPDATE(trigdata->tg_event)) {
        old_tuple = trigdata->tg_trigtuple;
        new_tuple = trigdata->tg_newtuple;
        op = 'U';
    } else if (TRIGGER_FIRED_BY_DELETE(trigdata->tg_event)) {
        old_tuple = trigdata->tg_trigtuple;
        op = 'D';
    } else {
        elog(ERROR, "pgtime_trigger_fn: unknown trigger event");
    }

    // Retrieve schema and relation name (fast metadata lookup)
    relname = RelationGetRelationName(rel);
    nspoid = rel->rd_rel->relnamespace;
    nspname = get_namespace_name(nspoid);
    if (!nspname) {
        elog(ERROR, "pgtime_trigger_fn: failed to get namespace name");
    }

    // 1. Check local session cache for table metadata
    for (int i = 0; i < rel_metadata_cache_count; i++) {
        if (rel_metadata_cache[i].relid == relid && rel_metadata_cache[i].is_valid) {
            pk_col = rel_metadata_cache[i].pk_col;
            pk_type_oid = rel_metadata_cache[i].pk_type_oid;
            cache_found = true;
            break;
        }
    }

    // 2. Connect to SPI and fetch metadata if not cached
    if (!cache_found) {
        char *temp_pk_col = NULL;
        Oid temp_pk_type_oid = InvalidOid;

        if ((ret = SPI_connect()) != SPI_OK_CONNECT) {
            elog(ERROR, "pgtime_trigger_fn: SPI_connect failed");
        }

        if (!get_pk_metadata(nspname, relname, &temp_pk_col, &temp_pk_type_oid)) {
            SPI_finish();
            elog(ERROR, "pgtime_trigger_fn: table %s.%s is not registered in pgtime._tracked_tables", nspname, relname);
        }

        // Cache the metadata to avoid database lookup on subsequent operations
        if (rel_metadata_cache_count < MAX_CACHE_ENTRIES) {
            RelationMetadataCacheEntry *entry = &rel_metadata_cache[rel_metadata_cache_count++];
            entry->relid = relid;
            strncpy(entry->pk_col, temp_pk_col, NAMEDATALEN - 1);
            entry->pk_col[NAMEDATALEN - 1] = '\0';
            entry->pk_type_oid = temp_pk_type_oid;
            entry->is_valid = true;
            
            pk_col = entry->pk_col;
            pk_type_oid = entry->pk_type_oid;
        } else {
            // Fallback for cache overflow
            pk_col = pstrdup(temp_pk_col);
            pk_type_oid = temp_pk_type_oid;
        }
    } else {
        // Connect to SPI to execute modification queries
        if ((ret = SPI_connect()) != SPI_OK_CONNECT) {
            elog(ERROR, "pgtime_trigger_fn: SPI_connect failed");
        }
    }

    history_table_name = psprintf("%s_history", relname);
    
    // 1. UPDATE / DELETE: Supersede the current version by setting sys_to = now()
    if (op == 'U' || op == 'D') {
        TupleDesc tupdesc;
        int pk_attnum;
        bool is_null;
        Datum pk_val;
        StringInfoData update_query;
        Oid argtypes[1];
        Datum values[1];

        tupdesc = RelationGetDescr(rel);
        pk_attnum = SPI_fnumber(tupdesc, pk_col);
        if (pk_attnum == SPI_ERROR_NOATTRIBUTE) {
            SPI_finish();
            elog(ERROR, "pgtime_trigger_fn: primary key column %s not found in table", pk_col);
        }
        
        pk_val = SPI_getbinval(old_tuple, tupdesc, pk_attnum, &is_null);
        if (is_null) {
            SPI_finish();
            elog(ERROR, "pgtime_trigger_fn: primary key value cannot be null");
        }
        
        // Execute target row closing query safely utilizing quoted identifiers
        initStringInfo(&update_query);
        
        if (op == 'D') {
            // For Delete, close it and record operation as D (indicating it ended in deletion)
            appendStringInfo(&update_query, 
                "UPDATE %s.%s SET sys_to = transaction_timestamp(), _pgtime_op = 'D' "
                "WHERE %s = $1 AND sys_to IS NULL",
                quote_identifier(nspname), quote_identifier(history_table_name), quote_identifier(pk_col));
        } else {
            // For Update, close the version
            appendStringInfo(&update_query, 
                "UPDATE %s.%s SET sys_to = transaction_timestamp() "
                "WHERE %s = $1 AND sys_to IS NULL",
                quote_identifier(nspname), quote_identifier(history_table_name), quote_identifier(pk_col));
        }
        
        argtypes[0] = pk_type_oid;
        values[0] = pk_val;
        
        ret = SPI_execute_with_args(update_query.data, 1, argtypes, values, NULL, false, 0);
        if (ret != SPI_OK_UPDATE) {
            SPI_finish();
            elog(ERROR, "pgtime_trigger_fn: failed to update history row: SPI_execute_with_args returned %d", ret);
        }
    }
    
    // 2. INSERT / UPDATE: Write the new snapshot into the history table
    if (op == 'I' || op == 'U') {
        TupleDesc tupdesc;
        int natts;
        StringInfoData cols_info;
        StringInfoData vals_info;
        Oid *argtypes;
        Datum *values;
        char *nulls;
        int param_idx;
        StringInfoData insert_query;

        tupdesc = RelationGetDescr(rel);
        natts = tupdesc->natts;
        
        initStringInfo(&cols_info);
        initStringInfo(&vals_info);
        
        argtypes = (Oid *) palloc((natts + 3) * sizeof(Oid));
        values = (Datum *) palloc((natts + 3) * sizeof(Datum));
        nulls = (char *) palloc((natts + 3) * sizeof(char));
        
        param_idx = 1;
        for (int i = 0; i < natts; i++) {
            Form_pg_attribute attr = TupleDescAttr(tupdesc, i);
            bool is_null;
            Datum val;

            if (attr->attisdropped)
                continue;
                
            if (param_idx > 1) {
                appendStringInfo(&cols_info, ", ");
                appendStringInfo(&vals_info, ", ");
            }
            
            appendStringInfo(&cols_info, "%s", quote_identifier(NameStr(attr->attname)));
            appendStringInfo(&vals_info, "$%d", param_idx);
            
            val = SPI_getbinval(new_tuple, tupdesc, i + 1, &is_null);
            
            argtypes[param_idx - 1] = attr->atttypid;
            values[param_idx - 1] = val;
            nulls[param_idx - 1] = is_null ? 'n' : ' ';
            
            param_idx++;
        }
        
        // Append history system columns
        appendStringInfo(&cols_info, ", \"sys_from\", \"sys_to\", \"_pgtime_op\"");
        appendStringInfo(&vals_info, ", transaction_timestamp(), NULL, $%d", param_idx);
        
        argtypes[param_idx - 1] = CHAROID;
        values[param_idx - 1] = CharGetDatum(op);
        nulls[param_idx - 1] = ' ';
        
        initStringInfo(&insert_query);
        appendStringInfo(&insert_query, "INSERT INTO %s.%s (%s) VALUES (%s)",
                         quote_identifier(nspname), quote_identifier(history_table_name), cols_info.data, vals_info.data);
                         
        ret = SPI_execute_with_args(insert_query.data, param_idx, argtypes, values, nulls, false, 0);
        if (ret != SPI_OK_INSERT) {
            SPI_finish();
            elog(ERROR, "pgtime_trigger_fn: failed to insert history row: SPI_execute_with_args returned %d", ret);
        }
    }
    
    SPI_finish();
    
    // Return original tuple to complete parent table operation
    if (op == 'D') {
        return PointerGetDatum(old_tuple);
    } else {
        return PointerGetDatum(new_tuple);
    }
}
