# Replay: timestamp-paced re-emission of records.
#
# Pacing is verified deterministically with an injected fake clock + sleep
# function so the tests never actually wait. The fake clock advances by exactly
# the amount each (zero-time) sleep requests, so captured sleep durations equal
# the inter-record gaps that real-time replay would produce.

using Test
using DatabentoBinaryEncoding
import DatabentoBinaryEncoding as DBN

@testset "replay" begin

    # A fake clock whose time only advances when sleep_fn is called. Records
    # every requested sleep so pacing can be asserted exactly.
    function fake_clock()
        now = Ref(0.0)
        sleeps = Float64[]
        clock = () -> now[]
        sleep_fn = s -> (push!(sleeps, s); now[] += s; nothing)
        return clock, sleep_fn, sleeps
    end

    # Build a TradeMsg with a given ts_event (and optional ts_recv).
    function trade(ts_event::Int64; ts_recv::Int64 = ts_event, seq::Integer = 0)
        hd = DBN.RecordHeader(UInt8(0), DBN.RType.MBP_0_MSG,
                              UInt16(1), UInt32(100), ts_event)
        return DBN.TradeMsg(hd, Int64(150_000_000_000), UInt32(100),
                            DBN.Action.TRADE, DBN.Side.ASK, UInt8(0), UInt8(1),
                            ts_recv, Int32(0), UInt32(seq))
    end

    S = 1_000_000_000  # one second in nanoseconds

    @testset "paces by inter-record gaps at speed 1" begin
        recs = [trade(Int64(0)), trade(Int64(1S)), trade(Int64(3S)), trade(Int64(6S))]
        clock, sleep_fn, sleeps = fake_clock()
        seen = DBN.TradeMsg[]
        n = replay_records(r -> push!(seen, r), recs;
                           clock = clock, sleep_fn = sleep_fn)
        @test n == 4
        @test length(seen) == 4
        # Gaps: 1s, 2s, 3s. First record fires immediately (no sleep).
        @test sleeps == [1.0, 2.0, 3.0]
    end

    @testset "speed multiplier compresses waits" begin
        recs = [trade(Int64(0)), trade(Int64(2S)), trade(Int64(4S))]
        clock, sleep_fn, sleeps = fake_clock()
        n = replay_records(_ -> nothing, recs;
                           speed = 2.0, clock = clock, sleep_fn = sleep_fn)
        @test n == 3
        @test sleeps == [1.0, 1.0]   # 2s gaps at 2x → 1s waits
    end

    @testset "speed = Inf delivers with no waiting" begin
        recs = [trade(Int64(0)), trade(Int64(5S)), trade(Int64(99S))]
        clock, sleep_fn, sleeps = fake_clock()
        seen = Int[]
        n = replay_records(r -> push!(seen, length(seen) + 1), recs;
                           speed = Inf, clock = clock, sleep_fn = sleep_fn)
        @test n == 3
        @test isempty(sleeps)
    end

    @testset "out-of-order timestamps do not produce negative waits" begin
        recs = [trade(Int64(5S)), trade(Int64(2S)), trade(Int64(7S))]
        clock, sleep_fn, sleeps = fake_clock()
        n = replay_records(_ -> nothing, recs;
                           clock = clock, sleep_fn = sleep_fn)
        @test n == 3
        # Backwards gap → no sleep; then 7s is 2s after the 5s anchor → 2s wait.
        @test sleeps == [2.0]
        @test all(>=(0.0), sleeps)
    end

    @testset "max_sleep caps large gaps and re-anchors" begin
        # 0s, then a 100s gap (capped to 1s), then a 1s gap after.
        recs = [trade(Int64(0)), trade(Int64(100S)), trade(Int64(101S))]
        clock, sleep_fn, sleeps = fake_clock()
        n = replay_records(_ -> nothing, recs;
                           max_sleep = 1.0, clock = clock, sleep_fn = sleep_fn)
        @test n == 3
        # First gap clamped to 1.0; re-anchored, so the following 1s gap waits 1.0.
        @test sleeps == [1.0, 1.0]
    end

    @testset "timestamp = :ts_recv paces by receive time" begin
        # ts_event identical; ts_recv carries the real spacing.
        recs = [trade(Int64(0); ts_recv = Int64(0)),
                trade(Int64(0); ts_recv = Int64(4S))]
        clock, sleep_fn, sleeps = fake_clock()
        n = replay_records(_ -> nothing, recs;
                           timestamp = :ts_recv, clock = clock, sleep_fn = sleep_fn)
        @test n == 2
        @test sleeps == [4.0]
    end

    @testset "empty collection is a no-op" begin
        clock, sleep_fn, sleeps = fake_clock()
        n = replay_records(_ -> error("should not be called"), DBN.TradeMsg[];
                           clock = clock, sleep_fn = sleep_fn)
        @test n == 0
        @test isempty(sleeps)
    end

    @testset "invalid arguments throw" begin
        recs = [trade(Int64(0)), trade(Int64(1S))]
        @test_throws ArgumentError replay_records(_ -> nothing, recs; speed = 0)
        @test_throws ArgumentError replay_records(_ -> nothing, recs; speed = -1)
        @test_throws ArgumentError replay_records(_ -> nothing, recs; max_sleep = -1.0)
        @test_throws ArgumentError replay_records(_ -> nothing, recs; timestamp = :bogus)
    end

    @testset "sleep_fn resolution honors precise / explicit override" begin
        # Default: plain Base.sleep.
        @test DBN._resolve_sleep_fn(nothing, false) === sleep
        # precise = true selects the spin-accurate sleeper.
        @test DBN._resolve_sleep_fn(nothing, true) === DBN._precise_sleep
        # An explicit sleep_fn always wins, even with precise = true.
        custom = s -> nothing
        @test DBN._resolve_sleep_fn(custom, true) === custom
    end

    @testset "_precise_sleep does not return early" begin
        # Zero / negative is a no-op.
        @test DBN._precise_sleep(0) === nothing
        @test DBN._precise_sleep(-1.0) === nothing
        # A sub-millisecond request must actually wait at least that long
        # (the spin path must not under-sleep). Upper bound left loose to
        # avoid flakiness under load.
        req = 0.0008  # 0.8 ms, below the sleep() resolution floor
        t = @elapsed DBN._precise_sleep(req)
        @test t >= req * 0.9
        @test t < req + 0.05
    end

    @testset "precise = true replays sub-millisecond gaps (real clock)" begin
        # Five records 300 µs apart — total span 1.2 ms, well below what
        # Base.sleep can resolve. Exercises the real _precise_sleep path.
        gap = 300_000  # 0.3 ms in ns
        recs = [trade(Int64(i * gap); seq = i) for i in 0:4]
        seen = DBN.TradeMsg[]
        t = @elapsed (n = replay_records(r -> push!(seen, r), recs; precise = true))
        @test n == 5
        @test [Int(r.sequence) for r in seen] == [0, 1, 2, 3, 4]
        # Should take at least the real span and not balloon.
        @test t >= 4 * gap / 1e9 * 0.9
        @test t < 0.1
    end

    @testset "replay_dbn over a file" begin
        metadata = DBN.Metadata(
            DBN.DBN_VERSION, "TEST.MOCK", DBN.Schema.TRADES,
            Int64(0), nothing, nothing, nothing,
            DBN.SType.INSTRUMENT_ID, false,
            ["AAPL"], String[], String[],
            Tuple{String,String,Int64,Int64}[],
        )
        ts0 = Int64(1_700_000_000_000_000_000)
        recs = DBN.DBNRecord[trade(ts0 + i * S; seq = i) for i in 0:3]

        tmp, io = mktemp(); close(io)
        try
            DBN.write_dbn(tmp, metadata, recs)

            clock, sleep_fn, sleeps = fake_clock()
            seen = DBN.TradeMsg[]
            n = replay_dbn(r -> push!(seen, r), tmp;
                           clock = clock, sleep_fn = sleep_fn)
            @test n == 4
            @test length(seen) == 4
            @test [Int(r.sequence) for r in seen] == [0, 1, 2, 3]
            @test sleeps == [1.0, 1.0, 1.0]   # 1s spacing
        finally
            rm(tmp; force = true)
        end
    end
end
