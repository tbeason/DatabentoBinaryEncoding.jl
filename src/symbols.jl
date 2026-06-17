# Symbol resolution: join the human-readable symbol back onto records.
#
# Every record carries only a numeric `hd.instrument_id` — opaque on its own.
# The mapping from that id to a tradable symbol lives in the file/stream
# `Metadata.mappings`: a flat list of
#     (raw_symbol, mapped_symbol, start_date, end_date)
# tuples, one per validity interval (`start_date`/`end_date` are raw `YYYYMMDD`
# integers; the same `raw_symbol` appears in several consecutive tuples when an
# instrument rolls or is renamed). When the query was resolved with
# `stype_out = INSTRUMENT_ID` (the historical default), `mapped_symbol` is the
# decimal instrument-id string, so the table is really an interval-keyed
# `instrument_id -> raw_symbol` map. These helpers invert it for joining.

"""
    symbol_map(metadata) -> Dict{UInt32,Vector{Tuple{Int64,Int64,String}}}

Build an `instrument_id -> [(start_date, end_date, raw_symbol), …]` lookup from
`metadata.mappings`, suitable for repeated [`symbol_for`](@ref) calls in a hot
loop (build once, reuse). Each value is the list of validity intervals for that
instrument id, sorted by `start_date`; dates are raw `YYYYMMDD` integers and the
interval is half-open `[start_date, end_date)`.

The join is only meaningful when the query was resolved with
`stype_out = SType.INSTRUMENT_ID` — that is what makes the mapping's
`mapped_symbol` field the decimal instrument-id string that record headers carry.
For any other `stype_out` (or empty mappings) the returned dict is empty.
"""
function symbol_map(metadata::Metadata)
    smap = Dict{UInt32,Vector{Tuple{Int64,Int64,String}}}()
    # Records key on instrument_id; only an instrument-id-resolved query has a
    # mapped_symbol we can parse back into that key.
    metadata.stype_out == SType.INSTRUMENT_ID || return smap
    for (raw, mapped, sd, ed) in metadata.mappings
        isempty(mapped) && continue
        id = tryparse(UInt32, mapped)
        id === nothing && continue   # defensive: skip a non-numeric mapped_symbol
        push!(get!(() -> Tuple{Int64,Int64,String}[], smap, id), (sd, ed, raw))
    end
    for intervals in values(smap)
        sort!(intervals, by = first)
    end
    return smap
end

# Nanoseconds-since-epoch (UTC) -> YYYYMMDD integer, matching the date encoding
# used in Metadata.mappings. Pure integer arithmetic — no float round-trip.
function _ts_ns_to_yyyymmdd(ts_ns::Integer)
    days = fld(Int64(ts_ns), 86_400_000_000_000)
    d = Date(1970, 1, 1) + Day(days)
    return year(d) * 10000 + month(d) * 100 + day(d)
end

"""
    symbol_for(smap::AbstractDict, instrument_id, ts_event) -> Union{String,Nothing}
    symbol_for(metadata::Metadata, instrument_id, ts_event) -> Union{String,Nothing}

Resolve the `raw_symbol` for `instrument_id` valid at `ts_event` (nanoseconds
since the Unix epoch, i.e. a record's `hd.ts_event`). Returns `nothing` when the
id is unknown or no interval covers the timestamp's date.

The `AbstractDict` form takes a prebuilt [`symbol_map`](@ref) and is the one to
use in a loop; the `Metadata` form rebuilds the map on every call (convenient for
one-off lookups, wasteful otherwise).
"""
function symbol_for(smap::AbstractDict, instrument_id::Integer, ts_event::Integer)
    intervals = get(smap, UInt32(instrument_id), nothing)
    intervals === nothing && return nothing
    d = _ts_ns_to_yyyymmdd(ts_event)
    for (sd, ed, raw) in intervals
        # Half-open [sd, ed); a degenerate single-day interval can arrive with
        # sd == ed, so accept that as a point match too.
        (sd <= d < ed || (sd == ed && d == sd)) && return raw
    end
    return nothing
end

symbol_for(metadata::Metadata, instrument_id::Integer, ts_event::Integer) =
    symbol_for(symbol_map(metadata), instrument_id, ts_event)

"""
    add_symbol_column!(df, metadata; column=:symbol) -> df

Join the human-readable `raw_symbol` onto an already-built records DataFrame,
in place, as a new `column` (default `:symbol`). The join keys on the frame's
`instrument_id` and `ts_event` columns, so it works for both flat schemas and
the row-expanded MBP-10 frame; unmatched rows get `missing`.

A no-op (returns `df` unchanged) when the frame lacks `instrument_id`/`ts_event`
(e.g. an empty frame). When `metadata` has mappings but was resolved with a
`stype_out` other than `INSTRUMENT_ID` — so nothing can be joined — the column is
filled with `missing` and a single warning is emitted.
"""
function add_symbol_column!(df::DataFrame, metadata::Metadata; column::Symbol = :symbol)
    (hasproperty(df, :instrument_id) && hasproperty(df, :ts_event)) || return df
    smap = symbol_map(metadata)
    if isempty(smap)
        if !isempty(metadata.mappings) && metadata.stype_out != SType.INSTRUMENT_ID
            @warn "add_symbol_column!: cannot join symbols — metadata.stype_out is not \
                   INSTRUMENT_ID, so records' instrument_id has no mapping" stype_out = metadata.stype_out
        end
        df[!, column] = Vector{Union{Missing,String}}(missing, nrow(df))
        return df
    end
    df[!, column] = [something(symbol_for(smap, id, ts), missing)
                     for (id, ts) in zip(df.instrument_id, df.ts_event)]
    return df
end

"""
    records_to_dataframe(records, metadata; symbols=true)

Like [`records_to_dataframe`](@ref), but joins the human-readable `raw_symbol`
onto the result as a `:symbol` column using `metadata.mappings` (see
[`add_symbol_column!`](@ref)). Pass `symbols=false` to skip the join and get the
same frame as the one-argument form.
"""
function records_to_dataframe(records::Vector, metadata::Metadata; symbols::Bool = true)
    df = records_to_dataframe(records)
    symbols && add_symbol_column!(df, metadata)
    return df
end
