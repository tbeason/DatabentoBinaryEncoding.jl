# DBN types, enums, and data structures

# Constants
"""The current DBN format version supported by this implementation."""
const DBN_VERSION = 3

"""Fixed-length symbol string size for DBN v2/v3 metadata and records."""
const SYMBOL_CSTR_LEN = 71

"""Fixed-point price scaling factor for converting between integer and float prices."""
const FIXED_PRICE_SCALE = Int32(1_000_000_000)

"""Sentinel value indicating an undefined or missing price."""
const UNDEF_PRICE = typemax(Int64)

"""Sentinel value indicating an undefined or missing order size."""
const UNDEF_ORDER_SIZE = typemax(UInt32)

"""Sentinel value indicating an undefined or missing timestamp."""
const UNDEF_TIMESTAMP = typemax(Int64)

"""Multiplier for converting the length field to bytes in record headers."""
const LENGTH_MULTIPLIER = 4

# Enums using EnumX for better namespace management

"""
    Schema

DBN data schemas representing different types of market data.

# Values
- `MBO`: Market-by-order data
- `MBP_1`: Market-by-price with book depth 1 (TBBO)
- `MBP_10`: Market-by-price with book depth 10
- `TBBO`: Top-of-book bid/offer
- `TRADES`: Trade messages only
- `OHLCV_1S`: OHLCV data at 1-second intervals
- `OHLCV_1M`: OHLCV data at 1-minute intervals
- `OHLCV_1H`: OHLCV data at 1-hour intervals
- `OHLCV_1D`: OHLCV data at 1-day intervals
- `DEFINITION`: Instrument definition data
- `STATISTICS`: Market statistics
- `STATUS`: Exchange status messages
- `IMBALANCE`: Order imbalance data
- `CBBO`: Consolidated best bid/offer
- `CBBO_1S`: Consolidated BBO at 1-second intervals
- `CBBO_1M`: Consolidated BBO at 1-minute intervals
- `CMBP_1`: Consolidated market-by-price depth 1
- `TCBBO`: Trade-consolidated BBO
- `BBO_1S`: BBO at 1-second intervals
- `BBO_1M`: BBO at 1-minute intervals
"""
@enumx Schema::UInt16 begin
    MBO = 0
    MBP_1 = 1
    MBP_10 = 2
    TBBO = 3
    TRADES = 4
    OHLCV_1S = 5
    OHLCV_1M = 6
    OHLCV_1H = 7
    OHLCV_1D = 8
    DEFINITION = 9
    STATISTICS = 10
    STATUS = 11
    IMBALANCE = 12
    CBBO = 13
    CBBO_1S = 14
    CBBO_1M = 15
    CMBP_1 = 16
    TCBBO = 17
    BBO_1S = 18
    BBO_1M = 19
    MIX = 0xFFFF
end

"""
    Compression

Compression algorithms supported for DBN files.

# Values
- `NONE`: No compression
- `ZSTD`: Zstandard compression
"""
@enumx Compression::UInt8 begin
    NONE = 0
    ZSTD = 1
end

"""
    Encoding

Output encoding formats for market data.

# Values
- `DBN`: Databento Binary Encoding
- `CSV`: Comma-separated values
- `JSON`: JavaScript Object Notation
"""
@enumx Encoding::UInt8 begin
    DBN = 0
    CSV = 1
    JSON = 2
end

"""
    SType

Symbol types for identifying instruments in DBN data. Numeric values match the
official Databento DBN spec — wire-encoded as a `UInt8` in metadata and in
`SymbolMappingMsg` (v2+).

# Values
- `INSTRUMENT_ID = 0`: Numeric instrument identifier
- `RAW_SYMBOL = 1`: Raw symbol string from exchange
- `SMART = 2`: Deprecated alias (was split into `CONTINUOUS` and `PARENT`)
- `CONTINUOUS = 3`: Continuous contract symbol
- `PARENT = 4`: Parent symbol for derived instruments (e.g. `SPXW.OPT`)
- `NASDAQ_SYMBOL = 5`: Nasdaq-specific symbol
- `CMS_SYMBOL = 6`: CMS symbol
- `ISIN = 7`: ISO 6166 International Securities Identification Number
- `US_CODE = 8`: US Code (CUSIP-style)
- `BBG_COMP_ID = 9`: Bloomberg composite ID
- `BBG_COMP_TICKER = 10`: Bloomberg composite ticker
- `FIGI = 11`: OpenFIGI identifier
- `FIGI_TICKER = 12`: OpenFIGI ticker
- `UNDEF = 255`: Unset/undefined sentinel (`0xFF`). Databento wire-encodes an
  unset `stype` as `0xFF`; this member lets non-nullable `stype` fields (e.g.
  in `SymbolMappingMsg`) represent and round-trip that sentinel. Metadata's
  nullable `stype_in` decodes `0xFF` to `nothing` instead.
"""
@enumx SType::UInt8 begin
    INSTRUMENT_ID   = 0
    RAW_SYMBOL      = 1
    SMART           = 2   # deprecated (kept for round-trip with v1 wire data)
    CONTINUOUS      = 3
    PARENT          = 4
    NASDAQ_SYMBOL   = 5
    CMS_SYMBOL      = 6
    ISIN            = 7
    US_CODE         = 8
    BBG_COMP_ID     = 9
    BBG_COMP_TICKER = 10
    FIGI            = 11
    FIGI_TICKER     = 12
    UNDEF           = 255  # 0xFF "unset" sentinel; see docstring
end

"""
    RType

Record types for different kinds of market data messages in DBN format.

# Values
- `MBP_0_MSG`: Trades (book depth 0)
- `MBP_1_MSG`: TBBO/MBP-1 (book depth 1)
- `MBP_10_MSG`: MBP-10 (book depth 10)
- `STATUS_MSG`: Exchange status record
- `INSTRUMENT_DEF_MSG`: Instrument definition record
- `IMBALANCE_MSG`: Order imbalance record
- `ERROR_MSG`: Error record from live gateway
- `SYMBOL_MAPPING_MSG`: Symbol mapping record from live gateway
- `SYSTEM_MSG`: Non-error record from live gateway
- `STAT_MSG`: Statistics record from publisher
- `OHLCV_1S_MSG`: OHLCV at 1-second cadence
- `OHLCV_1M_MSG`: OHLCV at 1-minute cadence
- `OHLCV_1H_MSG`: OHLCV at hourly cadence
- `OHLCV_1D_MSG`: OHLCV at daily cadence
- `MBO_MSG`: Market-by-order record
- `CMBP_1_MSG`: Consolidated market-by-price with book depth 1
- `CBBO_1S_MSG`: Consolidated market-by-price with book depth 1 at 1-second cadence
- `CBBO_1M_MSG`: Consolidated market-by-price with book depth 1 at 1-minute cadence
- `TCBBO_MSG`: Consolidated market-by-price with book depth 1 (trades only)
- `BBO_1S_MSG`: Market-by-price with book depth 1 at 1-second cadence
- `BBO_1M_MSG`: Market-by-price with book depth 1 at 1-minute cadence
"""
@enumx RType::UInt8 begin
    MBP_0_MSG = 0x00        # Trades (book depth 0)
    MBP_1_MSG = 0x01        # TBBO/MBP-1 (book depth 1)
    MBP_10_MSG = 0x0A       # MBP-10 (book depth 10)
    STATUS_MSG = 0x12       # Exchange status record
    INSTRUMENT_DEF_MSG = 0x13  # Instrument definition record
    IMBALANCE_MSG = 0x14    # Order imbalance record
    ERROR_MSG = 0x15        # Error record from live gateway
    SYMBOL_MAPPING_MSG = 0x16  # Symbol mapping record from live gateway
    SYSTEM_MSG = 0x17       # Non-error record from live gateway
    STAT_MSG = 0x18         # Statistics record from publisher
    OHLCV_1S_MSG = 0x20     # OHLCV at 1-second cadence
    OHLCV_1M_MSG = 0x21     # OHLCV at 1-minute cadence
    OHLCV_1H_MSG = 0x22     # OHLCV at hourly cadence
    OHLCV_1D_MSG = 0x23     # OHLCV at daily cadence
    MBO_MSG = 0xA0          # Market-by-order record
    CMBP_1_MSG = 0xB1       # Consolidated market-by-price with book depth 1
    CBBO_1S_MSG = 0xC0      # Consolidated market-by-price with book depth 1 at 1-second cadence
    CBBO_1M_MSG = 0xC1      # Consolidated market-by-price with book depth 1 at 1-minute cadence
    TCBBO_MSG = 0xC2        # Consolidated market-by-price with book depth 1 (trades only)
    BBO_1S_MSG = 0xC3       # Market-by-price with book depth 1 at 1-second cadence
    BBO_1M_MSG = 0xC4       # Market-by-price with book depth 1 at 1-minute cadence
end

"""
    Action

Market actions that can be applied to orders or trades.

# Values
- `ADD`: Insert a new order into the book
- `MODIFY`: Change an order's price and/or size
- `CANCEL`: Fully or partially cancel an order from the book
- `CLEAR`: Remove all resting orders for the instrument
- `TRADE`: An aggressing order traded. Does not affect the book
- `FILL`: A resting order was filled. Does not affect the book
- `NONE`: No action: does not affect the book, but may carry flags or other information
"""
@enumx Action::UInt8 begin
    ADD = UInt8('A')      # Insert a new order into the book
    MODIFY = UInt8('M')   # Change an order's price and/or size
    CANCEL = UInt8('C')   # Fully or partially cancel an order from the book
    CLEAR = UInt8('R')    # Remove all resting orders for the instrument
    TRADE = UInt8('T')    # An aggressing order traded. Does not affect the book
    FILL = UInt8('F')     # A resting order was filled. Does not affect the book
    NONE = UInt8('N')     # No action: does not affect the book, but may carry flags or other information
end

"""
    Side

Market sides for orders and trades.

# Values
- `ASK`: Ask/offer side (sell orders)
- `BID`: Bid side (buy orders)
- `NONE`: No specific side or not applicable
"""
@enumx Side::UInt8 begin
    ASK = UInt8('A')
    BID = UInt8('B')
    NONE = UInt8('N')
end

"""
    InstrumentClass

Classification of financial instruments. Values match Databento's DBN
`InstrumentClass` enum.

# Values
- `STOCK`: Equity instruments
- `CALL`: Call option contracts
- `PUT`: Put option contracts
- `FUTURE`: Futures contracts
- `INDEX`: Index instruments
- `BOND`: Fixed income securities
- `MIXED_SPREAD`: Mixed spread instruments
- `FUTURE_SPREAD`: Futures spread instruments
- `OPTION_SPREAD`: Option spread instruments
- `FX_SPOT`: Foreign exchange spot
- `COMMODITY_SPOT`: Commodity spot
- `UNKNOWN_0`, `UNKNOWN_45`: Numeric fallback values for unknown classes
"""
@enumx InstrumentClass::UInt8 begin
    BOND = UInt8('B')
    CALL = UInt8('C')
    FUTURE = UInt8('F')
    INDEX = UInt8('I')
    STOCK = UInt8('K')
    MIXED_SPREAD = UInt8('M')
    PUT = UInt8('P')
    FUTURE_SPREAD = UInt8('S')
    OPTION_SPREAD = UInt8('T')
    FX_SPOT = UInt8('X')
    COMMODITY_SPOT = UInt8('Y')
    # Also support numeric values
    UNKNOWN_0 = 0
    UNKNOWN_45 = 45
    OTHER = UInt8('?')
end

# Basic structures

"""
    VersionUpgradePolicy

Encapsulates the version upgrade policy for DBN files.

# Fields
- `upgrade_policy::UInt8`: Policy for handling version upgrades
"""
struct VersionUpgradePolicy
    upgrade_policy::UInt8
end

"""
    DatasetCondition

Conditions and constraints for a dataset.

# Fields
- `last_ts_out::Int64`: Last timestamp output
- `start_ts::Int64`: Dataset start timestamp
- `end_ts::Int64`: Dataset end timestamp
- `limit::UInt64`: Record limit for the dataset
"""
struct DatasetCondition
    last_ts_out::Int64
    start_ts::Int64
    end_ts::Int64
    limit::UInt64
end

"""
    Metadata

Metadata information for a DBN dataset.

# Fields
- `version::UInt8`: DBN format version
- `dataset::String`: Dataset identifier
- `schema::Schema.T`: Data schema type
- `start_ts::Int64`: Start timestamp for the data
- `end_ts::Union{Int64,Nothing}`: End timestamp (can be null)
- `limit::Union{UInt64,Nothing}`: Record count limit (can be null)
- `stype_in::Union{SType.T,Nothing}`: Input symbol type (can be null)
- `stype_out::SType.T`: Output symbol type
- `ts_out::Bool`: Whether timestamps are included in output
- `symbols::Vector{String}`: List of symbols in the dataset
- `partial::Vector{String}`: Partially available symbols
- `not_found::Vector{String}`: Symbols that were not found
- `mappings::Vector{Tuple{String,String,Int64,Int64}}`: Symbol mappings as
  `(raw_symbol, mapped_symbol, start_date, end_date)`, one tuple per mapping
  interval. A symbol with multiple intervals (e.g. a continuous contract's roll
  history) contributes consecutive tuples sharing the same raw symbol. Dates
  are raw `YYYYMMDD` integers.
"""
struct Metadata
    version::UInt8
    dataset::String
    schema::Schema.T
    start_ts::Int64
    end_ts::Union{Int64,Nothing}  # Can be null
    limit::Union{UInt64,Nothing}  # Can be null
    stype_in::Union{SType.T,Nothing}  # Can be null
    stype_out::SType.T
    ts_out::Bool
    symbols::Vector{String}
    partial::Vector{String}
    not_found::Vector{String}
    mappings::Vector{Tuple{String,String,Int64,Int64}}
end

"""
    DBNHeader

Complete header information for a DBN file.

# Fields
- `version_upgrade_policy::VersionUpgradePolicy`: Version handling policy
- `dataset_condition::DatasetCondition`: Dataset conditions and constraints
- `metadata::Metadata`: Dataset metadata
"""
struct DBNHeader
    version_upgrade_policy::VersionUpgradePolicy
    dataset_condition::DatasetCondition
    metadata::Metadata
end

"""
    RecordHeader

Standard header present in all DBN record types.

# Fields
- `length::UInt8`: Length of the record in 4-byte units (multiply by LENGTH_MULTIPLIER for bytes)
- `rtype::RType.T`: Record type identifier
- `publisher_id::UInt16`: Publisher/venue identifier
- `instrument_id::UInt32`: Instrument identifier
- `ts_event::Int64`: Event timestamp in nanoseconds since Unix epoch
"""
struct RecordHeader
    length::UInt8
    rtype::RType.T
    publisher_id::UInt16
    instrument_id::UInt32
    ts_event::Int64
end

"""
    record_length_bytes(hd::RecordHeader)

Get the actual record length in bytes from a RecordHeader.
The length field stores 4-byte units, so multiply by LENGTH_MULTIPLIER.
"""
record_length_bytes(hd::RecordHeader) = hd.length * LENGTH_MULTIPLIER

"""
    BidAskPair

Bid and ask price/size information for market data.

# Fields
- `bid_px::Int64`: Bid price (scaled by FIXED_PRICE_SCALE)
- `ask_px::Int64`: Ask price (scaled by FIXED_PRICE_SCALE)
- `bid_sz::UInt32`: Bid size/quantity
- `ask_sz::UInt32`: Ask size/quantity
- `bid_ct::UInt32`: Number of bid orders
- `ask_ct::UInt32`: Number of ask orders
"""
struct BidAskPair
    bid_px::Int64
    ask_px::Int64
    bid_sz::UInt32
    ask_sz::UInt32
    bid_ct::UInt32
    ask_ct::UInt32
end

# Timestamp utilities

"""
    DBNTimestamp

High-precision timestamp representation with nanosecond accuracy.

# Fields
- `seconds::Int64`: Unix epoch seconds
- `nanoseconds::Int32`: Nanoseconds within the second (0-999_999_999)
"""
struct DBNTimestamp
    seconds::Int64      # Unix epoch seconds
    nanoseconds::Int32  # Nanoseconds within the second (0-999_999_999)
end

"""
    DBNTimestamp(ns::Int64)

Construct a DBNTimestamp from nanoseconds since Unix epoch.

# Arguments
- `ns::Int64`: Nanoseconds since Unix epoch

# Returns
- `DBNTimestamp`: Timestamp split into seconds and nanoseconds components
"""
function DBNTimestamp(ns::Int64)
    if ns == UNDEF_TIMESTAMP
        return DBNTimestamp(UNDEF_TIMESTAMP, 0)
    end
    seconds = ns ÷ 1_000_000_000
    nanoseconds = Int32(ns % 1_000_000_000)
    return DBNTimestamp(seconds, nanoseconds)
end

"""
    to_nanoseconds(ts::DBNTimestamp)

Convert a DBNTimestamp back to nanoseconds since Unix epoch.

# Arguments
- `ts::DBNTimestamp`: Timestamp to convert

# Returns
- `Int64`: Nanoseconds since Unix epoch, or UNDEF_TIMESTAMP if undefined
"""
function to_nanoseconds(ts::DBNTimestamp)
    if ts.seconds == UNDEF_TIMESTAMP
        return UNDEF_TIMESTAMP
    end
    return ts.seconds * 1_000_000_000 + ts.nanoseconds
end

"""
    ts_to_datetime(ts::Int64)

Convert a nanosecond timestamp to DateTime with nanosecond precision information.

# Arguments
- `ts::Int64`: Nanoseconds since Unix epoch

# Returns
- `NamedTuple`: Contains `datetime` (DateTime) and `nanoseconds` (Int32), or `nothing` if undefined
"""
function ts_to_datetime(ts::Int64)
    if ts == UNDEF_TIMESTAMP
        return nothing
    end
    # Returns DateTime with millisecond precision and separate nanosecond component
    dbn_ts = DBNTimestamp(ts)
    dt = unix2datetime(Float64(dbn_ts.seconds) + dbn_ts.nanoseconds / 1_000_000_000)
    return (datetime=dt, nanoseconds=dbn_ts.nanoseconds)
end

"""
    datetime_to_ts(dt::DateTime, nanoseconds::Int32=0)

Convert a DateTime with optional nanosecond precision to nanosecond timestamp.

# Arguments
- `dt::DateTime`: DateTime to convert
- `nanoseconds::Int32`: Additional nanoseconds within the second (default: 0)

# Returns
- `Int64`: Nanoseconds since Unix epoch
"""
function datetime_to_ts(dt::DateTime, nanoseconds::Union{Int32,Int64}=0)
    # Convert DateTime to nanoseconds, preserving additional precision
    seconds = Int64(round(datetime2unix(dt)))
    return seconds * 1_000_000_000 + nanoseconds
end

"""
    ts_to_date_time(ts::Int64)

Convert a nanosecond timestamp to separate Date and Time components with full nanosecond precision.

# Arguments
- `ts::Int64`: Nanoseconds since Unix epoch

# Returns
- `NamedTuple`: Contains `date` (Date), `time` (Time), and `timestamp` (DBNTimestamp), or `nothing` if undefined
"""
function ts_to_date_time(ts::Int64)
    if ts == UNDEF_TIMESTAMP
        return nothing
    end
    dbn_ts = DBNTimestamp(ts)
    
    # Get the date part
    dt_seconds = unix2datetime(Float64(dbn_ts.seconds))
    date_part = Date(dt_seconds)
    
    # Get time within the day with nanosecond precision
    seconds_in_day = dbn_ts.seconds % 86400
    time_ns = seconds_in_day * 1_000_000_000 + dbn_ts.nanoseconds
    time_part = Dates.Time(Dates.Nanosecond(time_ns))
    
    return (date=date_part, time=time_part, timestamp=dbn_ts)
end

"""
    date_time_to_ts(date::Date, time::Dates.Time)

Convert separate Date and Time components to nanosecond timestamp.

# Arguments
- `date::Date`: Date component
- `time::Dates.Time`: Time component with nanosecond precision

# Returns
- `Int64`: Nanoseconds since Unix epoch
"""
function date_time_to_ts(date::Date, time::Dates.Time)
    # Convert date to seconds since epoch
    dt = DateTime(date)
    date_seconds = Int64(round(datetime2unix(dt)))
    
    # Extract nanoseconds from time
    time_ns = Dates.value(time)  # Total nanoseconds since midnight
    
    return date_seconds * 1_000_000_000 + time_ns
end

# Price conversion utilities

"""
    price_to_float(price::Int64, scale::Int32=FIXED_PRICE_SCALE)

Convert a fixed-point price to floating-point representation.

# Arguments
- `price::Int64`: Fixed-point price value
- `scale::Int32`: Scaling factor (default: FIXED_PRICE_SCALE)

# Returns
- `Float64`: Floating-point price, or NaN if price is UNDEF_PRICE
"""
function price_to_float(price::Int64, scale::Int32=FIXED_PRICE_SCALE)
    if price == UNDEF_PRICE
        return NaN
    end
    return Float64(price) / Float64(scale)
end

"""
    float_to_price(value::Float64, scale::Int32=FIXED_PRICE_SCALE)

Convert a floating-point price to fixed-point representation.

# Arguments
- `value::Float64`: Floating-point price
- `scale::Int32`: Scaling factor (default: FIXED_PRICE_SCALE)

# Returns
- `Int64`: Fixed-point price, or UNDEF_PRICE if value is NaN or infinite
"""
function float_to_price(value::Float64, scale::Int32=FIXED_PRICE_SCALE)
    if isnan(value) || isinf(value)
        return UNDEF_PRICE
    end
    return Int64(round(value * Float64(scale)))
end

# Helper functions for safe enum conversion.
# All enums share one policy: an invalid byte warns (once per enum) and maps to
# a sentinel value instead of throwing, so one bad byte can't kill a decode
# stream. Lookup tables keep the hot path free of try/catch.

function _build_enum_lookup(::Type{E}, default::E) where {E}
    table = fill(default, 256)
    valid = falses(256)
    for inst in instances(E)
        idx = Int(UInt8(inst)) + 1
        table[idx] = inst
        valid[idx] = true
    end
    return table, valid
end

const _ACTION_LOOKUP, _ACTION_VALID = _build_enum_lookup(Action.T, Action.NONE)
const _SIDE_LOOKUP, _SIDE_VALID = _build_enum_lookup(Side.T, Side.NONE)
const _INSTRUMENT_CLASS_LOOKUP, _INSTRUMENT_CLASS_VALID =
    _build_enum_lookup(InstrumentClass.T, InstrumentClass.OTHER)

"""
    safe_action(raw_val::UInt8)

Convert a raw byte value to an Action enum. `0x00` and invalid values map to
`Action.NONE`; invalid values additionally log a warning (once).
"""
@inline function safe_action(raw_val::UInt8)
    # 0 indicates no action for certain record types
    raw_val == 0x00 && return Action.NONE
    idx = Int(raw_val) + 1
    @inbounds if !_ACTION_VALID[idx]
        @warn "Unknown Action value: $raw_val (0x$(string(raw_val, base=16))), using NONE as default" maxlog = 1
    end
    return @inbounds _ACTION_LOOKUP[idx]
end

"""
    safe_side(raw_val::UInt8)

Convert a raw byte value to a Side enum. `0x00` and invalid values map to
`Side.NONE`; invalid values additionally log a warning (once).
"""
@inline function safe_side(raw_val::UInt8)
    # 0 indicates no side for certain record types
    raw_val == 0x00 && return Side.NONE
    idx = Int(raw_val) + 1
    @inbounds if !_SIDE_VALID[idx]
        @warn "Unknown Side value: $raw_val (0x$(string(raw_val, base=16))), using NONE as default" maxlog = 1
    end
    return @inbounds _SIDE_LOOKUP[idx]
end

"""
    safe_instrument_class(raw_val::UInt8)

Convert a raw byte value to an InstrumentClass enum. Invalid values log a
warning (once) and map to `InstrumentClass.OTHER`.
"""
@inline function safe_instrument_class(raw_val::UInt8)
    idx = Int(raw_val) + 1
    @inbounds if !_INSTRUMENT_CLASS_VALID[idx]
        @warn "Unknown InstrumentClass value: $raw_val (0x$(string(raw_val, base=16))), using OTHER as default" maxlog = 1
    end
    return @inbounds _INSTRUMENT_CLASS_LOOKUP[idx]
end

# ---------------------------------------------------------------------------
# Venue-code enums and record flags
#
# `StatMsg.stat_type` and `StatusMsg.trading_event` stay raw `UInt16` on the
# record structs: the wire fields are plain integers and publishers may emit
# codes outside the published enum. The enums below are for *interpreting*
# those codes. Compare with `r.stat_type == UInt16(StatType.SETTLEMENT_PRICE)`
# or convert with `safe_stat_type(r.stat_type)` / `safe_trading_event(...)`.
# ---------------------------------------------------------------------------

"""
    StatType

Type of statistic carried by a [`StatMsg`](@ref) (`stat_type` field). Values
match the official DBN `StatType` enum (`UInt16`). `UNKNOWN = 0` is a local
sentinel returned by [`safe_stat_type`](@ref) for codes this package does not
recognize (publisher-specific, or newer than this release).

# Values
- `OPENING_PRICE = 1`: Price of the first trade of an instrument
- `INDICATIVE_OPENING_PRICE = 2`: Probable opening price, published pre-open
- `SETTLEMENT_PRICE = 3`: Settlement price
- `TRADING_SESSION_LOW_PRICE = 4`: Lowest trade price of the session
- `TRADING_SESSION_HIGH_PRICE = 5`: Highest trade price of the session
- `CLEARED_VOLUME = 6`: Contracts cleared on the previous trading date
- `LOWEST_OFFER = 7`: Lowest offer price of the session
- `HIGHEST_BID = 8`: Highest bid price of the session
- `OPEN_INTEREST = 9`: Number of outstanding contracts
- `FIXING_PRICE = 10`: VWAP over a fixing period
- `CLOSE_PRICE = 11`: Last trade price of the session
- `NET_CHANGE = 12`: Change from the previous session's close
- `VWAP = 13`: Session volume-weighted average price
- `VOLATILITY = 14`: Implied volatility associated with the settlement price
- `DELTA = 15`: Option delta associated with the settlement price
- `UNCROSSING_PRICE = 16`: Auction uncrossing price
- `UPPER_PRICE_LIMIT = 17`: Exchange-defined upper price limit (published for
  CME GLBX.MDP3 since the 2026-07 normalization change)
- `LOWER_PRICE_LIMIT = 18`: Exchange-defined lower price limit (as above)
- `BLOCK_VOLUME = 19`: Block contracts cleared on the previous trading date
- `INDICATIVE_CLOSE_PRICE = 20`: Probable closing price
- `MWCB_LEVEL_1 = 21`, `MWCB_LEVEL_2 = 22`, `MWCB_LEVEL_3 = 23`: Market-wide
  circuit-breaker thresholds (7% / 13% / 20%)
- `AUCTION_COLLAR_REFERENCE_PRICE = 24`, `AUCTION_COLLAR_UPPER_PRICE = 25`,
  `AUCTION_COLLAR_LOWER_PRICE = 26`: Auction collar prices
- `VENUE_SPECIFIC_VOLUME_1 = 10001`, `VENUE_SPECIFIC_PRICE_1 = 10002`:
  Venue-specific statistics
- `UNKNOWN = 0`: Unrecognized code (local sentinel, not part of the DBN spec)
"""
@enumx StatType::UInt16 begin
    UNKNOWN = 0
    OPENING_PRICE = 1
    INDICATIVE_OPENING_PRICE = 2
    SETTLEMENT_PRICE = 3
    TRADING_SESSION_LOW_PRICE = 4
    TRADING_SESSION_HIGH_PRICE = 5
    CLEARED_VOLUME = 6
    LOWEST_OFFER = 7
    HIGHEST_BID = 8
    OPEN_INTEREST = 9
    FIXING_PRICE = 10
    CLOSE_PRICE = 11
    NET_CHANGE = 12
    VWAP = 13
    VOLATILITY = 14
    DELTA = 15
    UNCROSSING_PRICE = 16
    UPPER_PRICE_LIMIT = 17
    LOWER_PRICE_LIMIT = 18
    BLOCK_VOLUME = 19
    INDICATIVE_CLOSE_PRICE = 20
    MWCB_LEVEL_1 = 21
    MWCB_LEVEL_2 = 22
    MWCB_LEVEL_3 = 23
    AUCTION_COLLAR_REFERENCE_PRICE = 24
    AUCTION_COLLAR_UPPER_PRICE = 25
    AUCTION_COLLAR_LOWER_PRICE = 26
    VENUE_SPECIFIC_VOLUME_1 = 10001
    VENUE_SPECIFIC_PRICE_1 = 10002
end

"""
    TradingEvent

Additional context for a [`StatusMsg`](@ref) (`trading_event` field). Values
match the official DBN `TradingEvent` enum (`UInt16`).

# Values
- `NONE = 0`: No additional information given
- `NO_CANCEL = 1`: Order entry is allowed; modification and cancellation are not
- `CHANGE_TRADING_SESSION = 2`: A change of trading session occurred; daily
  statistics are reset
- `IMPLIED_MATCHING_ON = 3`: Implied matching is available (CME's matching
  engine is constructing implied depth)
- `IMPLIED_MATCHING_OFF = 4`: Implied matching is not available

CME GLBX.MDP3 publishes `IMPLIED_MATCHING_ON`/`OFF` status records since the
2026-07 normalization change.
"""
@enumx TradingEvent::UInt16 begin
    NONE = 0
    NO_CANCEL = 1
    CHANGE_TRADING_SESSION = 2
    IMPLIED_MATCHING_ON = 3
    IMPLIED_MATCHING_OFF = 4
end

const _STAT_TYPE_LOOKUP = Dict{UInt16,StatType.T}(UInt16(v) => v for v in instances(StatType.T))
const _TRADING_EVENT_LOOKUP = Dict{UInt16,TradingEvent.T}(UInt16(v) => v for v in instances(TradingEvent.T))

"""
    safe_stat_type(raw::Integer) -> StatType.T

Interpret a raw `StatMsg.stat_type` code. Unrecognized codes map to
`StatType.UNKNOWN` without a warning (publisher-specific codes are legitimate).
"""
safe_stat_type(raw::Integer) = get(_STAT_TYPE_LOOKUP, UInt16(raw), StatType.UNKNOWN)

"""
    safe_trading_event(raw::Integer) -> TradingEvent.T

Interpret a raw `StatusMsg.trading_event` code. Unrecognized codes map to
`TradingEvent.NONE` ("no additional information") without a warning.
"""
safe_trading_event(raw::Integer) = get(_TRADING_EVENT_LOOKUP, UInt16(raw), TradingEvent.NONE)

# Record `flags` bit field (MBO / MBP / trade / BBO records). Values match the
# official DBN `flags` module.

"""
Flag bit: last record in the event for a given `instrument_id`. Since the
2026-07 CME normalization change, GLBX.MDP3 MBO emits this on a standalone
record (`action = Action.NONE`, `price = UNDEF_PRICE`, `size = 0`) that
follows the book updates, rather than on the final book update itself.
"""
const F_LAST = 0x80
"""Flag bit: top-of-book record, not an individual order."""
const F_TOB = 0x40
"""Flag bit: record sourced from a replay, such as a snapshot server."""
const F_SNAPSHOT = 0x20
"""Flag bit: aggregated price-level record, not an individual order."""
const F_MBP = 0x10
"""Flag bit: `ts_recv` is inaccurate due to clock issues or packet reordering."""
const F_BAD_TS_RECV = 0x08
"""Flag bit: an unrecoverable gap was detected in the channel."""
const F_MAYBE_BAD_BOOK = 0x04
"""Flag bit: publisher-specific event."""
const F_PUBLISHER_SPECIFIC = 0x02

"""
    has_flag(flags, flag) -> Bool

`true` if the `flag` bit (e.g. [`F_LAST`](@ref)) is set in a record's `flags`.
"""
has_flag(flags::Integer, flag::Integer) = (flags & flag) != 0
