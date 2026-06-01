# Enums API Reference

Enumeration types used throughout DatabentoBinaryEncoding.jl.

## Schema Types

```@docs
Schema
```

### Available Schemas

The `Schema` enum defines the available data schemas:

- `MBO` - Market-by-order
- `MBP_1` - Market-by-price (top of book)
- `MBP_10` - Market-by-price (10 levels)
- `TBBO` - Top-of-book BBO (trade-sampled)
- `TRADES` - Trade messages
- `OHLCV_1S`, `OHLCV_1M`, `OHLCV_1H`, `OHLCV_1D` - OHLCV bars at different intervals
- `DEFINITION` - Instrument definitions
- `STATISTICS` - Publisher statistics
- `STATUS` - Status messages
- `IMBALANCE` - Imbalance messages
- `CBBO`, `CBBO_1S`, `CBBO_1M` - Consolidated BBO (event, 1-second, 1-minute)
- `CMBP_1` - Consolidated market-by-price (top of book)
- `TCBBO` - Consolidated BBO (trade-sampled)
- `BBO_1S`, `BBO_1M` - BBO at 1-second / 1-minute intervals
- `MIX` - Mixed-schema stream (e.g. live captures interleaving data and control records)

For complete schema details, see [Databento Schemas Documentation](https://databento.com/docs/schemas-and-data-formats/whats-a-schema).

## Record Types

```@docs
RType
```

Record types identify the message type in the binary format. Common values:
- `MBO_MSG` - Market-by-order message
- `TRADE_MSG` - Trade message
- `MBP_0_MSG` - MBP level 0 (trades)
- `MBP_1_MSG` - MBP level 1
- `MBP_10_MSG` - MBP level 10
- `OHLCV_1M_MSG` - 1-minute OHLCV
- And more...

## Symbol Types

```@docs
SType
```

Symbol types specify how instruments are identified. Numeric values match the
official Databento DBN spec (wire-encoded as a `UInt8`):
- `INSTRUMENT_ID` - Numeric instrument ID
- `RAW_SYMBOL` - Raw symbol string from the exchange
- `SMART` - Deprecated alias (split into `CONTINUOUS` and `PARENT`)
- `CONTINUOUS` - Continuous contract symbol
- `PARENT` - Parent symbol for derived instruments (e.g. `SPXW.OPT`)
- `NASDAQ_SYMBOL`, `CMS_SYMBOL` - Venue-specific symbols
- `ISIN`, `US_CODE` - Security identifiers
- `BBG_COMP_ID`, `BBG_COMP_TICKER` - Bloomberg composite ID / ticker
- `FIGI`, `FIGI_TICKER` - OpenFIGI identifier / ticker
- `UNDEF` - Unset/undefined sentinel (`0xFF`). A v3 live gateway can wire-encode
  an unset `stype` (e.g. on a `SymbolMappingMsg`); this member lets the decoder
  represent it instead of erroring. The nullable metadata `stype_in` decodes
  `0xFF` to `nothing` instead.

## Action Types

```@docs
Action
```

Action types for order and trade messages:
- `ADD` - Order added to book
- `MODIFY` - Order modified
- `CANCEL` - Order cancelled
- `TRADE` - Trade execution
- `CLEAR` - Order cleared
- And more...

## Side Types

```@docs
Side
```

Side of market:
- `BID` - Buy side
- `ASK` - Sell side
- `NONE` - No side specified

## Compression Types

```@docs
Compression
```

Compression formats:
- `NONE` - No compression
- `ZSTD` - Zstandard compression

## Encoding Types

```@docs
Encoding
```

File encoding formats:
- `DBN` - Databento Binary Encoding
- `CSV` - Comma-separated values
- `JSON` - JSON format

## Instrument Class

```@docs
InstrumentClass
```

Instrument classification. Values match the Databento DBN single-character
codes:
- `STOCK` (`'K'`) - Equity
- `CALL` (`'C'`) - Call option
- `PUT` (`'P'`) - Put option
- `FUTURE` (`'F'`) - Futures contract
- `BOND` (`'B'`) - Fixed income
- `FX_SPOT` (`'X'`) - Foreign exchange spot
- `COMMODITY_SPOT` (`'Y'`) - Commodity spot
- `MIXED_SPREAD` (`'M'`), `FUTURE_SPREAD` (`'S'`), `OPTION_SPREAD` (`'T'`) - Spreads
- `OTHER` (`'?'`), `UNKNOWN_0`, `UNKNOWN_45` - Fallbacks for unclassified instruments

## Usage Examples

### Working with Schemas

```julia
using DatabentoBinaryEncoding

# Check schema type
if metadata.schema == Schema.TRADES
    trades = read_trades(filename)
end

# Schema to string
schema_name = string(Schema.TRADES)  # "TRADES"
```

### Working with Actions

```julia
# Filter by action
foreach_mbo("file.dbn") do mbo
    if mbo.action == Action.ADD
        # Handle new order
    elseif mbo.action == Action.CANCEL
        # Handle cancellation
    end
end
```

### Working with Sides

```julia
# Count by side
bid_count = 0
ask_count = 0

foreach_trade("file.dbn") do trade
    if trade.side == Side.BID
        bid_count += 1
    else
        ask_count += 1
    end
end
```

## See Also

- [Types](types.md) - Message type reference
- [Databento Schema Documentation](https://databento.com/docs/schemas-and-data-formats) - Schema specifications
