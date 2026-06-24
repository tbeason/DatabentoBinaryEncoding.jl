# Conversion API Reference

Functions for converting between DBN and other formats.

## Export (DBN to Other Formats)

```@docs
dbn_to_csv
dbn_to_json
dbn_to_parquet
records_to_dataframe
```

## Symbol Resolution

Join the human-readable `raw_symbol` back onto records (which carry only the
opaque numeric `instrument_id`) using `Metadata.mappings`.

```@docs
symbol_map
symbol_for
add_symbol_column!
```

## Import (Other Formats to DBN)

```@docs
json_to_dbn
csv_to_dbn
parquet_to_dbn
```

## Usage Examples

### Exporting Data

```julia
# Convert to CSV
dbn_to_csv("trades.dbn", "trades.csv")

# Convert to JSON
dbn_to_json("trades.dbn", "trades.json")

# Convert to Parquet (ZSTD-compressed by default)
dbn_to_parquet("trades.dbn", "trades.parquet")

# Convert to DataFrame for analysis
records = read_trades("trades.dbn")
df = records_to_dataframe(records)
```

### Importing Data

```julia
# From JSON
json_to_dbn("trades.json", "trades.dbn")

# From CSV (requires schema)
csv_to_dbn("trades.csv", "trades.dbn",
           schema=Schema.TRADES,
           dataset="XNAS")

# From Parquet (requires schema)
parquet_to_dbn("trades.parquet", "trades.dbn",
               schema=Schema.TRADES,
               dataset="XNAS")
```

## See Also

- [Conversion Guide](../guide/conversion.md) - Detailed conversion documentation
- [Reading](reading.md) - Reading DBN files
- [Writing](writing.md) - Writing DBN files
