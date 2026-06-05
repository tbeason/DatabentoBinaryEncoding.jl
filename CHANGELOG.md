# Changelog

All notable changes to DatabentoBinaryEncoding.jl are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/tbeason/DatabentoBinaryEncoding.jl/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/tbeason/DatabentoBinaryEncoding.jl/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/tbeason/DatabentoBinaryEncoding.jl/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/tbeason/DatabentoBinaryEncoding.jl/releases/tag/v0.1.0
[#18]: https://github.com/tbeason/DatabentoBinaryEncoding.jl/pull/18
[#19]: https://github.com/tbeason/DatabentoBinaryEncoding.jl/pull/19
[#21]: https://github.com/tbeason/DatabentoBinaryEncoding.jl/pull/21
[#22]: https://github.com/tbeason/DatabentoBinaryEncoding.jl/pull/22
[#23]: https://github.com/tbeason/DatabentoBinaryEncoding.jl/issues/23
[#24]: https://github.com/tbeason/DatabentoBinaryEncoding.jl/pull/24
