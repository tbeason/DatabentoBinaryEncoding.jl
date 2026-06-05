# Pretty-printing for DBN records.
#
# Julia's default struct `show` dumps every field with fully-qualified type names
# (e.g. `DatabentoBinaryEncoding.TradeMsg(DatabentoBinaryEncoding.RecordHeader(...`),
# which is unreadable when streaming a feed (`for rec in ch; println(rec); end`).
#
# These compact one-line `Base.show(io, r)` methods render only the few fields that
# matter when scanning a live stream: timestamp, instrument id, side/action,
# price(s), and size(s). A single 2-arg `show` per type is enough — it drives
# `println`, `Vector` element display, and the REPL (whose 3-arg `text/plain`
# `show` falls back to the 2-arg form when no specialization exists).
#
# Field-rendering conventions (the `why` is load-bearing — sentinels otherwise
# leak as `NaN` / `9223372036854775807` / `4294967295` onto the line):
#   - prices are Int64 fixed-point (scaled by FIXED_PRICE_SCALE = 1e-9). Rendered
#     via `price_to_float`, which maps the UNDEF_PRICE sentinel to NaN; we show
#     "-" in that case (detected with `isnan`, never `== UNDEF_PRICE` on a float).
#   - timestamps are nanoseconds since the Unix epoch. Rendered with full
#     nanosecond precision; the UNDEF_TIMESTAMP sentinel — and the UInt-max
#     sentinel on the UInt64-typed `ts_recv` fields — show as "-".
#   - sizes carry typemax sentinels (UNDEF_ORDER_SIZE = typemax(UInt32), an unset
#     stat quantity = typemax(Int64)); those show as "-" too.

const _PP_UNDEF = "-"

# Bare enum member name (e.g. "ASK"). `string` of an EnumX value already yields
# the unqualified member name — unlike its `show`, which prints the fully-qualified
# path "DatabentoBinaryEncoding.Side.ASK".
_pp_enum(e) = string(e)

# Fixed-point price -> string; UNDEF_PRICE -> "-".
function _pp_px(p::Int64)
    v = price_to_float(p)
    isnan(v) ? _PP_UNDEF : string(v)
end

# Size-like unsigned -> string; typemax sentinel (e.g. UNDEF_ORDER_SIZE) -> "-".
_pp_sz(s::Unsigned) = s == typemax(typeof(s)) ? _PP_UNDEF : string(s)

# Signed quantity -> string; typemax(Int64) "unset" sentinel -> "-".
_pp_qty(q::Integer) = q == typemax(Int64) ? _PP_UNDEF : string(q)

# Nanosecond timestamp (Int64 or UInt64) -> "YYYY-MM-DDThh:mm:ss.fffffffff".
# Guards the typemax sentinel *before* the Int64 cast so a UInt64 `ts_recv` left
# as typemax(UInt64) does not throw InexactError on conversion.
function _pp_ts(ns::Integer)
    (ns == typemax(typeof(ns)) || ns == UNDEF_TIMESTAMP) && return _PP_UNDEF
    parts = ts_to_date_time(Int64(ns))
    parts === nothing ? _PP_UNDEF : string(parts.date, "T", parts.time)
end

# Best bid/ask from a BidAskPair, rendered as "bid=.. bsz=.. ask=.. asz=..".
_pp_bbo(io::IO, lv::BidAskPair) = print(io,
    "bid=", _pp_px(lv.bid_px), " bsz=", _pp_sz(lv.bid_sz),
    " ask=", _pp_px(lv.ask_px), " asz=", _pp_sz(lv.ask_sz))

# --- trades / orders ---

function Base.show(io::IO, r::TradeMsg)
    print(io, "Trade ", _pp_ts(r.hd.ts_event), " iid=", r.hd.instrument_id,
        " side=", _pp_enum(r.side), " px=", _pp_px(r.price), " sz=", _pp_sz(r.size),
        " seq=", r.sequence)
end

# action is load-bearing for MBO (ADD/MODIFY/CANCEL/CLEAR/...), unlike Trade where
# it is always TRADE; order_id is the defining field so it goes last (widest).
function Base.show(io::IO, r::MBOMsg)
    print(io, "MBO ", _pp_ts(r.hd.ts_event), " iid=", r.hd.instrument_id,
        " act=", _pp_enum(r.action), " side=", _pp_enum(r.side),
        " px=", _pp_px(r.price), " sz=", _pp_sz(r.size), " oid=", r.order_id)
end

# --- book / BBO families ---

# Incremental top-of-book update: the top-level px/sz/act/sd describe THIS change,
# then the resulting BBO from `levels`. Shared by MBP1 and CMBP1 (identical layout).
function _pp_book_incr(io::IO, label, r, lv::BidAskPair)
    print(io, label, " ", _pp_ts(r.hd.ts_event), " iid=", r.hd.instrument_id,
        " act=", _pp_enum(r.action), " side=", _pp_enum(r.side),
        " px=", _pp_px(r.price), " sz=", _pp_sz(r.size), " | ")
    _pp_bbo(io, lv)
end

Base.show(io::IO, r::MBP1Msg) = _pp_book_incr(io, "MBP1", r, r.levels)
Base.show(io::IO, r::CMBP1Msg) = _pp_book_incr(io, "CMBP1", r, r.levels)

# MBP10: levels is an NTuple{10,BidAskPair}; show only level 1 plus a depth hint.
function Base.show(io::IO, r::MBP10Msg)
    _pp_book_incr(io, "MBP10", r, r.levels[1])
    print(io, " (+9 lvls)")
end

# TCBBO is trade-sampled: each record is emitted on a trade, so px/sz/side ARE the
# trade; show them, then the consolidated BBO at that instant.
function Base.show(io::IO, r::TCBBOMsg)
    print(io, "TCBBO ", _pp_ts(r.hd.ts_event), " iid=", r.hd.instrument_id,
        " side=", _pp_enum(r.side), " px=", _pp_px(r.price), " sz=", _pp_sz(r.size), " | ")
    _pp_bbo(io, r.levels)
end

# Interval BBO snapshots: the BBO is the headline; px/sz are the interval's last
# trade (UNDEF_PRICE in a quiet interval -> "-"). Shared by C/BBO 1s/1m.
function _pp_bbo_snap(io::IO, label, r)
    print(io, label, " ", _pp_ts(r.hd.ts_event), " iid=", r.hd.instrument_id, " ")
    _pp_bbo(io, r.levels)
    print(io, " last=", _pp_px(r.price), " lsz=", _pp_sz(r.size))
end

Base.show(io::IO, r::CBBO1sMsg) = _pp_bbo_snap(io, "CBBO1s", r)
Base.show(io::IO, r::CBBO1mMsg) = _pp_bbo_snap(io, "CBBO1m", r)
Base.show(io::IO, r::BBO1sMsg) = _pp_bbo_snap(io, "BBO1s", r)
Base.show(io::IO, r::BBO1mMsg) = _pp_bbo_snap(io, "BBO1m", r)

# --- bars / stats ---

function Base.show(io::IO, r::OHLCVMsg)
    print(io, "OHLCV ", _pp_ts(r.hd.ts_event), " iid=", r.hd.instrument_id,
        " O=", _pp_px(r.open), " H=", _pp_px(r.high), " L=", _pp_px(r.low),
        " C=", _pp_px(r.close), " V=", r.volume)
end

# stat_type is a venue-defined UInt16 code (not an enum). quantity is a signed
# Int64 in v3 (NOT a price) — render as a plain integer, guarding the unset
# sentinel. ts_recv is UInt64; _pp_ts handles the cast/sentinel safely.
function Base.show(io::IO, r::StatMsg)
    print(io, "Stat ", _pp_ts(r.hd.ts_event), " iid=", r.hd.instrument_id,
        " type=", r.stat_type, " px=", _pp_px(r.price), " qty=", _pp_qty(r.quantity),
        " recv=", _pp_ts(r.ts_recv))
end

function Base.show(io::IO, r::ImbalanceMsg)
    print(io, "Imbalance ", _pp_ts(r.hd.ts_event), " iid=", r.hd.instrument_id,
        " ref=", _pp_px(r.ref_price), " side=", _pp_enum(r.side),
        " paired=", r.paired_qty, " imb=", r.total_imbalance_qty,
        " match=", _pp_px(r.ind_match_price))
end

# action/reason/trading_event are UInt16 venue codes (NOT the Action enum, despite
# the field name). The is_* flags are UInt8 tri-state c_chars; `== 1` -> clean bool.
function Base.show(io::IO, r::StatusMsg)
    print(io, "Status ", _pp_ts(r.hd.ts_event), " iid=", r.hd.instrument_id,
        " action=", r.action, " reason=", r.reason,
        " trading=", r.is_trading == 1, " quoting=", r.is_quoting == 1,
        " ssr=", r.is_short_sell_restricted == 1)
end

# --- control / system (gateway-wide, not instrument-scoped) ---

function Base.show(io::IO, r::ErrorMsg)
    print(io, "Error ", _pp_ts(r.hd.ts_event), " msg=", repr(r.err))
end

function Base.show(io::IO, r::SymbolMappingMsg)
    print(io, "SymMap ", _pp_ts(r.hd.ts_event), " iid=", r.hd.instrument_id, " ",
        r.stype_in_symbol, " [", _pp_enum(r.stype_in), "] -> ",
        r.stype_out_symbol, " [", _pp_enum(r.stype_out), "]")
end

function Base.show(io::IO, r::SystemMsg)
    print(io, "System ", _pp_ts(r.hd.ts_event), " code=", repr(r.code), " msg=", repr(r.msg))
end

# --- instrument definition (reference record; identification fields) ---

# strike_price is UNDEF_PRICE for non-options; expiration is UNDEF_TIMESTAMP for
# undated instruments — both -> "-" via the helpers.
function Base.show(io::IO, r::InstrumentDefMsg)
    print(io, "Def ", _pp_ts(r.hd.ts_event), " iid=", r.hd.instrument_id,
        " sym=", r.raw_symbol, " cls=", _pp_enum(r.instrument_class),
        " exch=", r.exchange, " exp=", _pp_ts(r.expiration),
        " strike=", _pp_px(r.strike_price), " tick=", _pp_px(r.min_price_increment),
        " ccy=", r.currency, " act=", r.security_update_action)
end

# --- shared substructures (printed compactly when shown on their own) ---

function Base.show(io::IO, hd::RecordHeader)
    print(io, "RecordHeader(", _pp_enum(hd.rtype), " iid=", hd.instrument_id,
        " pub=", hd.publisher_id, " ts_event=", _pp_ts(hd.ts_event), ")")
end

function Base.show(io::IO, lv::BidAskPair)
    print(io, "BidAskPair(")
    _pp_bbo(io, lv)
    print(io, " bc=", lv.bid_ct, " ac=", lv.ask_ct, ")")
end
