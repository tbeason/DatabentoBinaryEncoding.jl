# DBN replay functionality
#
# "Replay" re-emits the records of a DBN file (or an in-memory record
# collection) in their original time order, pacing each callback by the gap
# between record timestamps so the stream is delivered as if it were arriving
# live. This is useful for backtesting, demos, and exercising consumers that
# expect a real-time feed.

"""
    _replay_as_ns(x) -> Int64

Normalize a timestamp field to `Int64` nanoseconds. `ts_recv` is `UInt64` on a
few record types (`StatusMsg`, `StatMsg`); a value that does not fit in an
`Int64` is treated as the undefined sentinel.
"""
@inline _replay_as_ns(x::Int64) = x
@inline _replay_as_ns(x::UInt64) = x > UInt64(typemax(Int64)) ? UNDEF_TIMESTAMP : Int64(x)

"""
    _replay_timestamp(rec, which::Symbol) -> Int64

Extract the pacing timestamp (in nanoseconds) from a record.

`:ts_event` uses the record header's `ts_event`, which every record type has.
`:ts_recv` uses the record's `ts_recv` field when present and defined, falling
back to `ts_event` otherwise (several record types — `OHLCVMsg`, `ErrorMsg`,
`SystemMsg`, `SymbolMappingMsg` — have no `ts_recv`).
"""
@inline function _replay_timestamp(rec, which::Symbol)
    if which === :ts_event
        return rec.hd.ts_event
    elseif which === :ts_recv
        if hasproperty(rec, :ts_recv)
            ts = _replay_as_ns(getproperty(rec, :ts_recv))
            return ts == UNDEF_TIMESTAMP ? rec.hd.ts_event : ts
        end
        return rec.hd.ts_event
    else
        throw(ArgumentError("`timestamp` must be :ts_event or :ts_recv, got $(which)"))
    end
end

"""
    _replay_loop(f, produce; speed, timestamp, max_sleep, clock, sleep_fn) -> Int

Core replay engine. `produce` is a zero-argument function returning the next
record or `nothing` when the stream is exhausted. Returns the number of records
delivered to `f`.

Pacing is anchored to wall-clock time: the wait before record `i` is computed
so that record `i` fires at `wall_anchor + (ts_i - data_anchor) / speed`
seconds. Anchoring (rather than sleeping the raw inter-record gap each step)
means time spent inside `f` is absorbed instead of accumulating as drift — a
slow callback simply shortens the next wait rather than pushing every
subsequent record later.
"""
function _replay_loop(f::Function, produce::Function;
                      speed::Real,
                      timestamp::Symbol,
                      max_sleep::Union{Real,Nothing},
                      clock::Function,
                      sleep_fn::Function)
    speed > 0 || throw(ArgumentError("`speed` must be positive, got $(speed)"))
    max_sleep === nothing || max_sleep >= 0 ||
        throw(ArgumentError("`max_sleep` must be non-negative, got $(max_sleep)"))

    # `pace` is false when we should deliver records as fast as possible
    # (infinite speed compression) — pacing math is skipped entirely.
    pace = isfinite(speed)

    count = 0
    have_anchor = false
    data_anchor = Int64(0)      # ts (ns) of the anchor record
    wall_anchor = 0.0           # clock() reading at the anchor

    while true
        rec = produce()
        rec === nothing && break
        count += 1

        if pace
            ts = _replay_timestamp(rec, timestamp)

            if ts == UNDEF_TIMESTAMP
                # No usable timestamp — deliver immediately without disturbing
                # the anchor.
                f(rec)
                continue
            end

            if !have_anchor
                # First timed record establishes the anchor; it fires now.
                data_anchor = ts
                wall_anchor = clock()
                have_anchor = true
                f(rec)
                continue
            end

            elapsed = (ts - data_anchor) / 1.0e9 / speed   # target seconds since anchor
            sleep_s = wall_anchor + elapsed - clock()

            if sleep_s > 0
                if max_sleep !== nothing && sleep_s > max_sleep
                    # Cap the wait and re-anchor so we don't try to "catch up"
                    # the time we deliberately skipped over a large gap.
                    sleep_fn(float(max_sleep))
                    data_anchor = ts
                    wall_anchor = clock()
                else
                    sleep_fn(sleep_s)
                end
            end
        end

        f(rec)
    end

    return count
end

# Below this gap, `Base.sleep` (≈1 ms granularity on Unix, and as coarse as the
# system timer tick — often ~15 ms — on Windows) overshoots badly. `precise`
# mode busy-waits the residual on the real clock to recover sub-millisecond
# accuracy at the cost of pinning a CPU core.
const _SPIN_THRESHOLD = 2.0e-3

"""
    _precise_sleep(s::Real)

Sleep for `s` seconds with sub-millisecond accuracy. Coarse-sleeps everything
beyond `_SPIN_THRESHOLD`, then busy-waits the remainder. Used when
`replay_dbn`/`replay_records` are called with `precise = true`.

The deadline is measured against `Base.time_ns()` — a monotonic counter — rather
than wall-clock `time()`, so a system-clock adjustment (NTP, manual correction)
mid-spin can't make the busy-wait return early or pin a core indefinitely.
"""
function _precise_sleep(s::Real)
    s <= 0 && return nothing
    deadline = time_ns() + round(UInt64, s * 1.0e9)
    if s > _SPIN_THRESHOLD
        sleep(s - _SPIN_THRESHOLD)   # yield the bulk to the scheduler
    end
    while time_ns() < deadline       # spin the residual (≤ _SPIN_THRESHOLD)
    end
    return nothing
end

# Resolve the sleep function: an explicit `sleep_fn` always wins (tests inject
# one); otherwise `precise` selects the spin-accurate sleeper or plain `sleep`.
@inline function _resolve_sleep_fn(sleep_fn::Union{Function,Nothing}, precise::Bool)
    sleep_fn !== nothing && return sleep_fn
    return precise ? _precise_sleep : sleep
end

"""
    replay_dbn(f::Function, filename::AbstractString;
               speed::Real = 1.0,
               timestamp::Symbol = :ts_event,
               max_sleep::Union{Real,Nothing} = nothing,
               precise::Bool = false,
               clock::Function = time,
               sleep_fn::Union{Function,Nothing} = nothing) -> Int

Replay a DBN file, invoking `f(record)` for each record paced in real time
according to the records' timestamps. Returns the number of records replayed.

Transparently handles Zstd compression and skips unknown record types, exactly
like [`DBNStream`](@ref). Records are delivered in file order.

# Keyword arguments
- `speed`: time-compression multiplier. `1.0` replays at the original rate,
  `2.0` at twice the speed (half the waits), `10.0` ten times faster.
  `Inf` delivers every record as fast as possible (no waiting), equivalent to
  plain streaming.
- `timestamp`: which timestamp to pace by — `:ts_event` (default, present on
  every record) or `:ts_recv` (the receive timestamp, falling back to
  `ts_event` for record types that have none).
- `max_sleep`: optional cap (in seconds) on any single wait. Large gaps (e.g.
  an overnight session break) are clamped to this so replay doesn't stall.
  After a clamp, pacing re-anchors to the current record.
- `precise`: when `true`, busy-wait sub-millisecond gaps instead of using
  `Base.sleep`. See the timing-resolution note below.
- `clock` / `sleep_fn`: injection points for the wall clock and sleep function,
  primarily for testing. `clock` defaults to `Base.time`. An explicit `sleep_fn`
  overrides `precise`; when left as `nothing` the sleeper is `Base.sleep`
  (or the precise busy-wait sleeper when `precise = true`).

# Timing resolution
DBN timestamps are nanosecond precision, but pacing accuracy is bounded by the
sleep function, not the timestamps. `Base.sleep` resolves to roughly 1 ms on
Unix, and as coarse as the system timer tick (often ~15 ms) on Windows, so
records spaced more tightly than that cannot be reproduced as distinct waits —
they arrive clumped. Because pacing is anchored to absolute wall-clock targets,
this clumping is *local*: the stream re-synchronizes and the error does not
accumulate across the file, and records sharing a timestamp are delivered
back-to-back. For sub-millisecond fidelity (e.g. dense MBO bursts) pass
`precise = true`, which busy-waits small gaps at the cost of pinning a CPU core.

# Examples
```julia
# Replay trades in real time
replay_dbn("trades.dbn") do rec
    println(price_to_float(rec.price))
end

# Replay 100x faster, paced by receive time, with overnight gaps capped at 1s
replay_dbn("mbo.dbn.zst"; speed = 100, timestamp = :ts_recv, max_sleep = 1.0) do rec
    handle(rec)
end

# Microsecond-accurate replay of a dense MBO burst (busy-waits; uses a full core)
replay_dbn("mbo.dbn"; precise = true) do rec
    handle(rec)
end
```

See also [`replay_records`](@ref) to replay an already-loaded record collection,
and [`DBNStream`](@ref) / [`foreach_record`](@ref) for unpaced streaming.
"""
function replay_dbn(f::Function, filename::AbstractString;
                    speed::Real = 1.0,
                    timestamp::Symbol = :ts_event,
                    max_sleep::Union{Real,Nothing} = nothing,
                    precise::Bool = false,
                    clock::Function = time,
                    sleep_fn::Union{Function,Nothing} = nothing)
    sleeper = _resolve_sleep_fn(sleep_fn, precise)
    decoder = DBNDecoder(String(filename))
    produce = function ()
        while !eof(decoder.io)
            rec = read_record(decoder)
            rec === nothing && continue   # unknown rtype: skip, keep going
            return rec
        end
        return nothing
    end
    try
        return _replay_loop(f, produce;
                            speed = speed, timestamp = timestamp,
                            max_sleep = max_sleep, clock = clock, sleep_fn = sleeper)
    finally
        if decoder.io !== decoder.base_io
            close(decoder.io)
        end
        if isa(decoder.base_io, IOStream)
            close(decoder.base_io)
        end
    end
end

"""
    replay_records(f::Function, records;
                   speed::Real = 1.0,
                   timestamp::Symbol = :ts_event,
                   max_sleep::Union{Real,Nothing} = nothing,
                   precise::Bool = false,
                   clock::Function = time,
                   sleep_fn::Union{Function,Nothing} = nothing) -> Int

Replay an in-memory collection of records (e.g. the result of [`read_dbn`](@ref)),
invoking `f(record)` for each one paced in real time by its timestamp. Returns
the number of records replayed.

Accepts any iterable of DBN record types. All keyword arguments behave exactly
as in [`replay_dbn`](@ref), including the `precise` flag and the timing-resolution
caveats documented there.

# Example
```julia
records = read_dbn("trades.dbn")
replay_records(records; speed = 5) do rec
    handle(rec)
end
```
"""
function replay_records(f::Function, records;
                        speed::Real = 1.0,
                        timestamp::Symbol = :ts_event,
                        max_sleep::Union{Real,Nothing} = nothing,
                        precise::Bool = false,
                        clock::Function = time,
                        sleep_fn::Union{Function,Nothing} = nothing)
    sleeper = _resolve_sleep_fn(sleep_fn, precise)
    next = iterate(records)
    produce = function ()
        next === nothing && return nothing
        rec, state = next
        next = iterate(records, state)
        return rec
    end
    return _replay_loop(f, produce;
                        speed = speed, timestamp = timestamp,
                        max_sleep = max_sleep, clock = clock, sleep_fn = sleeper)
end
