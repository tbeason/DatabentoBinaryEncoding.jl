# Changelog

All notable changes to DatabentoBinaryEncoding.jl are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

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

[Unreleased]: https://github.com/tbeason/DatabentoBinaryEncoding.jl/compare/v0.1.3...HEAD
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
