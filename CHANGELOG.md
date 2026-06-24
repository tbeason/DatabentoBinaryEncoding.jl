# Changelog

All notable changes to DatabentoBinaryEncoding.jl are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.6] - 2026-06-24

### Changed

- Parquet read/write is now backed by **DuckDB.jl** instead of **Parquet2.jl**. The
  previous Parquet2-written files were not reliably readable by all Parquet consumers
  (e.g. DuckDB, pandas/pyarrow); DuckDB-written output is broadly compatible. `Parquet2`
  has been dropped as a dependency (replaced by `DuckDB` and `DBInterface`). Both
  `dbn_to_parquet` and `parquet_to_dbn` are affected. `dbn_to_parquet` writes a single
  Parquet file at the exact `output_file` path (pass a `*.parquet` path, not a directory).

### Added

- Timestamp-paced **replay**: `replay_dbn(f, filename; ...)` re-emits a DBN file's
  records in time order, pacing each `f(record)` callback by the gap between record
  timestamps to simulate a live feed (backtesting, demos, driving real-time
  consumers). `replay_records(f, records; ...)` does the same over an already-loaded
  collection. Zstd-aware and skips unknown record types like `DBNStream`. Pacing is
  anchored to absolute wall-clock targets so callback execution time is absorbed
  instead of accumulating as drift. Options: `speed` (time-compression multiplier;
  `Inf` = no waiting), `timestamp` (`:ts_event` or `:ts_recv`, with fallback),
  `max_sleep` (cap large gaps; re-anchors after a clamp), and `precise` (busy-wait
  sub-millisecond gaps, since `Base.sleep` only resolves ~1 ms on Unix / ~15 ms on
  Windows). `clock`/`sleep_fn` are injectable for deterministic testing.
- `dbn_to_parquet` now compresses with **ZSTD by default** and accepts a `compression`
  keyword — one of `"zstd"` (default), `"snappy"`, `"gzip"`, or `"uncompressed"`.
- Symbol resolution helpers that join the human-readable `raw_symbol` back onto
  records using `Metadata.mappings`: `symbol_map(metadata)` builds an
  `instrument_id -> [(start_date, end_date, raw_symbol)]` lookup,
  `symbol_for(map_or_metadata, instrument_id, ts_event)` resolves the symbol
  valid at a record's timestamp, `add_symbol_column!(df, metadata)` joins a
  `:symbol` column onto a records DataFrame in place, and
  `records_to_dataframe(records, metadata; symbols=true)` does the conversion +
  join in one call. The join keys on `instrument_id`/`ts_event` (so it also works
  for the row-expanded MBP-10 frame) and only applies when the query was resolved
  with `stype_out = SType.INSTRUMENT_ID`.

### Fixed

- `records_to_dataframe` (and therefore `dbn_to_csv` / `dbn_to_parquet`) no longer throws
  `FieldError` on **OHLCV**, **STATUS**, **IMBALANCE**, and **DEFINITION** records. The
  converters referenced struct fields that do not exist: `OHLCVMsg.ts_recv`;
  `StatusMsg.ts_in_delta`/`sequence` (and a bogus `Action.T` cast of the status action
  code); `ImbalanceMsg.auction_price`/`ts_in_delta`/`sequence`; and
  `InstrumentDefMsg.multiplier`/`min_price_increment_portfolio_type`/`ts_in_delta`/
  `sequence`. They now read the real fields (e.g. STATUS emits `reason`,
  `trading_event`, `is_trading`/`is_quoting`/`is_short_sell_restricted`; IMBALANCE emits
  `auction_time`, `ssr_filling_price`, `ind_match_price`, `upper_collar`, `lower_collar`;
  DEFINITION emits `tick_rule`).
- `dbn_to_parquet` no longer errors on an **empty record set** (e.g. an OHLCV-1d window
  with no bars). The exported Parquet preserves the file's real schema (built from
  `Metadata.schema` via `empty_dataframe_for_schema`) as a valid, zero-row file that reads
  back as zero records, instead of raising a DuckDB "Table function must return at least
  one column" error. `mbp10_to_dataframe` likewise returns a typed zero-row frame on empty
  input rather than a column-less one.
- `create_metadata_from_dataframe` (used by `parquet_to_dbn` / `csv_to_dbn`) no longer
  throws from `minimum`/`maximum` on a zero-row DataFrame; an empty frame yields
  `start_ts = end_ts = 0`, so a fully-empty Parquet/CSV round-trips back to DBN.
- `records_to_dataframe` (and therefore `to_dataframe` / `dbn_to_parquet`) no
  longer throws `FieldError` on **TBBO / MBP-1** and **MBP-10**. The converters
  read non-existent flat `bid_px_00…` fields; the bid/ask data actually lives in
  the nested `levels::BidAskPair` (MBP-1) / `levels::NTuple{10,BidAskPair}`
  (MBP-10). MBP-1 now reads through `levels`, MBP-10 indexes the level tuple, and
  the consolidated/BBO family (`CMBP1Msg`, `TCBBOMsg`, `CBBO1sMsg`, `CBBO1mMsg`,
  `BBO1sMsg`, `BBO1mMsg`) — which share the MBP-1 layout — now route to the same
  converter instead of falling through to the generic mixed-record path ([#40]).
- `read_stat_msg` now sizes the record body from `hd.length` instead of assuming
  the 80-byte DBN v3 layout. Pre-v3 64-byte `StatMsg` records (32-bit `quantity`,
  as currently served by the historical gateway for STATISTICS) decode correctly
  and are upgraded to the v3 shape, instead of overrunning the record boundary
  and desyncing every subsequent record in the stream ([#32]).
- `stat_to_dataframe` no longer references nonexistent `StatMsg` fields
  (`stat_value`, `flags`); STATISTICS records export with `price`, `quantity`,
  `flags` (from `stat_flags`), `ts_ref`, `stat_type`, `channel_id`, and
  `update_action` columns ([#33]).
- The metadata decoder reads **all** symbol-mapping intervals instead of only
  the first. `Metadata.mappings` now holds one
  `(raw_symbol, mapped_symbol, start_date, end_date)` tuple per interval, so a
  continuous contract's full roll history survives decoding; the encoder groups
  consecutive same-symbol tuples back into one mapping entry ([#34]).
- Invalid enum bytes are handled uniformly: `Side`, `Action`, and
  `InstrumentClass` all warn (once) and fall back to a sentinel
  (`Side.NONE`, `Action.NONE`, `InstrumentClass.OTHER`) instead of `Side`/
  `Action` throwing and killing the decode stream. The conversions use lookup
  tables, so the hot path stays free of `try`/`catch`. The old `safe_action`
  fallback of `Action.TRADE` was changed to `Action.NONE` ([#35]).

## [0.1.3] - 2026-06-05

### Added

- Compact, single-line `Base.show` for every DBN record type (and `RecordHeader`
  / `BidAskPair`), replacing Julia's fully-qualified struct dump. Streaming a feed
  (`for rec in ch; println(rec); end`) now renders readable lines such as
  `Trade 2026-06-05T00:23:05.040049165 iid=42 side=ASK px=185.42 sz=100 seq=88213`,
  with fixed-point prices decoded, full-nanosecond timestamps, and the unset
  sentinels (`UNDEF_PRICE`, `UNDEF_TIMESTAMP`, `UNDEF_ORDER_SIZE`) shown as `-`.

## [0.1.2] - 2026-06-01

### Added

- `SType.UNDEF` (`255` / `0xFF`) enum member representing the Databento "unset"
  symbol-type sentinel, so non-nullable `stype` fields can hold and round-trip it.
- v3 `InstrumentDefMsg` byte-offset regression test.
- Documentation refresh: registered-installation instructions, corrected enum
  reference lists (`Schema`, `SType`, `InstrumentClass`), and this changelog.

### Fixed

- Generic `read_record` no longer crashes with `ArgumentError: invalid value for
  Enum SType: 255` on DBN v3 captures. A v3 live gateway can wire-encode an unset
  `stype` as `0xFF` on a `SymbolMappingMsg`; the decoder now tolerates it instead
  of throwing on the first control record ([#23], [#24]).
- v3 `InstrumentDefMsg` is decoded/encoded with the fixed binary field layout
  (71-byte v2/v3 symbol fields, signed `Int32` leg ratios) and `InstrumentClass`
  enum values aligned with the Databento DBN codes (`CALL = 'C'`, `PUT = 'P'`,
  `STOCK = 'K'`, …) ([#22]).

## [0.1.1] - 2026-05-25

### Fixed

- `SymbolMappingMsg` `hd.length` is re-derived from the layout being written on a
  cross-version encode, so the record header matches the bytes that follow it
  ([#21]).

## [0.1.0] - 2026-05-18

### Added

- Initial release of DatabentoBinaryEncoding.jl (renamed from DBN.jl): reading,
  writing, and streaming of DBN v2/v3 files; Zstd compression; bidirectional
  conversion to JSON/Parquet/CSV; byte-for-byte compatibility with the official
  Rust implementation ([#18], [#19]).

[0.1.6]: https://github.com/tbeason/DatabentoBinaryEncoding.jl/compare/v0.1.5...v0.1.6
[0.1.3]: https://github.com/tbeason/DatabentoBinaryEncoding.jl/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/tbeason/DatabentoBinaryEncoding.jl/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/tbeason/DatabentoBinaryEncoding.jl/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/tbeason/DatabentoBinaryEncoding.jl/releases/tag/v0.1.0
[#18]: https://github.com/tbeason/DatabentoBinaryEncoding.jl/pull/18
[#19]: https://github.com/tbeason/DatabentoBinaryEncoding.jl/pull/19
[#21]: https://github.com/tbeason/DatabentoBinaryEncoding.jl/pull/21
[#22]: https://github.com/tbeason/DatabentoBinaryEncoding.jl/pull/22
[#23]: https://github.com/tbeason/DatabentoBinaryEncoding.jl/issues/23
[#24]: https://github.com/tbeason/DatabentoBinaryEncoding.jl/pull/24
[#32]: https://github.com/tbeason/DatabentoBinaryEncoding.jl/issues/32
[#33]: https://github.com/tbeason/DatabentoBinaryEncoding.jl/issues/33
[#34]: https://github.com/tbeason/DatabentoBinaryEncoding.jl/issues/34
[#35]: https://github.com/tbeason/DatabentoBinaryEncoding.jl/issues/35
[#40]: https://github.com/tbeason/DatabentoBinaryEncoding.jl/issues/40
