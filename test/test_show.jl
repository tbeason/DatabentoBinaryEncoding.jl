# Tests for the compact one-line `Base.show` methods on DBN record types.
# These assert the human-facing rendering: correct labels/fields, full-precision
# timestamps, fixed-point price decoding, and — critically — that the various
# "unset" sentinels (UNDEF_PRICE, UNDEF_TIMESTAMP, UNDEF_ORDER_SIZE, the unset
# stat quantity, and the UInt64-max ts_recv) render as "-" instead of leaking
# NaN / huge integers / throwing on conversion.

# `show` of a record returns its compact one-liner (no MIME specialization, so
# this is exactly what `println(rec)` and Vector display produce).
pp(x) = sprint(show, x)

@testset "Record pretty-printing (show)" begin
    # A fixed event timestamp: 2026-06-05T00:23:05.040049165 UTC. `datetime_to_ts`
    # rounds to whole seconds, so add the full sub-second component as nanoseconds.
    ts = DBN.datetime_to_ts(DateTime(2026, 6, 5, 0, 23, 5)) + 40_049_165
    ts_str = "2026-06-05T00:23:05.040049165"
    hd = DBN.RecordHeader(0x0c, DBN.RType.MBP_0_MSG, 0x0001, UInt32(42), ts)

    @testset "TradeMsg" begin
        r = DBN.TradeMsg(hd, 185_420_000_000, UInt32(100), DBN.Action.TRADE,
            DBN.Side.ASK, 0x00, 0x00, ts, Int32(0), UInt32(88213))
        s = pp(r)
        @test startswith(s, "Trade ")
        @test occursin(ts_str, s)            # full nanosecond precision
        @test occursin("iid=42", s)
        @test occursin("side=ASK", s)        # bare enum name, not Mod.Side.ASK
        @test occursin("px=185.42", s)       # fixed-point decoded
        @test occursin("sz=100", s)
        @test occursin("seq=88213", s)
        @test !occursin("DatabentoBinaryEncoding", s)  # no qualified type noise
    end

    @testset "MBOMsg with UNDEF sentinels" begin
        # A CANCEL legitimately carries UNDEF_PRICE and UNDEF_ORDER_SIZE.
        r = DBN.MBOMsg(hd, UInt64(99), DBN.UNDEF_PRICE, DBN.UNDEF_ORDER_SIZE,
            0x00, 0x00, DBN.Action.CANCEL, DBN.Side.BID, ts, Int32(0), UInt32(7))
        s = pp(r)
        @test startswith(s, "MBO ")
        @test occursin("act=CANCEL", s)
        @test occursin("px=-", s)            # UNDEF_PRICE -> dash, not NaN
        @test occursin("sz=-", s)            # UNDEF_ORDER_SIZE -> dash
        @test !occursin("NaN", s)
        @test occursin("oid=99", s)
    end

    @testset "Book families show the BBO" begin
        lv = DBN.BidAskPair(212_340_000_000, 212_350_000_000, UInt32(300), UInt32(150),
            UInt32(3), UInt32(2))
        mbp1 = DBN.MBP1Msg(hd, 212_340_000_000, UInt32(100), DBN.Action.MODIFY,
            DBN.Side.BID, 0x00, 0x01, ts, Int32(0), UInt32(1), lv)
        s = pp(mbp1)
        @test startswith(s, "MBP1 ")
        @test occursin("bid=212.34 bsz=300 ask=212.35 asz=150", s)
        @test occursin("act=MODIFY", s)
        @test occursin("side=BID", s)       # Side labeled `side=` consistently, not `sd=`
        @test !occursin("sd=", s)

        # MBP10: top-of-book from levels[1] plus the depth hint.
        levels = ntuple(_ -> lv, 10)
        mbp10 = DBN.MBP10Msg(hd, 212_350_000_000, UInt32(50), DBN.Action.MODIFY,
            DBN.Side.ASK, 0x00, 0x0a, ts, Int32(0), UInt32(2), levels)
        s10 = pp(mbp10)
        @test startswith(s10, "MBP10 ")
        @test occursin("bid=212.34 bsz=300 ask=212.35 asz=150", s10)
        @test occursin("(+9 lvls)", s10)
    end

    @testset "OHLCVMsg" begin
        r = DBN.OHLCVMsg(hd, 412_500_000_000, 413_100_000_000, 412_050_000_000,
            412_880_000_000, UInt64(18250))
        s = pp(r)
        @test startswith(s, "OHLCV ")
        @test occursin("O=412.5 H=413.1 L=412.05 C=412.88 V=18250", s)
    end

    @testset "StatMsg sentinel safety (UInt64 ts_recv, unset quantity)" begin
        # ts_recv left as the UInt64-max sentinel must NOT throw on the Int64 cast,
        # and an unset quantity (typemax Int64) must render as a dash.
        r = DBN.StatMsg(hd, typemax(UInt64), UInt64(0), 412_750_000_000,
            typemax(Int64), UInt32(0), Int32(0), UInt16(3), UInt16(0), 0x00, 0x00)
        local s
        @test_nowarn (s = pp(r))             # no InexactError from Int64(typemax(UInt64))
        @test occursin("type=3", s)
        @test occursin("px=412.75", s)
        @test occursin("qty=-", s)           # unset quantity -> dash
        @test occursin("recv=-", s)          # unset ts_recv -> dash
        @test !occursin("9223372036854775807", s)

        # A populated stat renders the real values.
        r2 = DBN.StatMsg(hd, UInt64(ts), UInt64(0), 412_750_000_000, Int64(500),
            UInt32(0), Int32(0), UInt16(3), UInt16(0), 0x00, 0x00)
        s2 = pp(r2)
        @test occursin("qty=500", s2)
        @test occursin("recv=$(ts_str)", s2)
    end

    @testset "StatusMsg boolean flags" begin
        r = DBN.StatusMsg(hd, UInt64(ts), UInt16(1), UInt16(0), UInt16(0),
            0x01, 0x01, 0x00)
        s = pp(r)
        @test startswith(s, "Status ")
        @test occursin("action=1", s)
        @test occursin("trading=true", s)
        @test occursin("quoting=true", s)
        @test occursin("ssr=false", s)
    end

    @testset "Control records lead with their payload" begin
        err = DBN.ErrorMsg(hd, "symbology resolution failed")
        se = pp(err)
        @test startswith(se, "Error ")
        @test occursin("symbology resolution failed", se)

        sym = DBN.SymbolMappingMsg(hd, DBN.SType.RAW_SYMBOL, "ESM6",
            DBN.SType.INSTRUMENT_ID, "42", Int64(0), DBN.UNDEF_TIMESTAMP)
        ss = pp(sym)
        @test startswith(ss, "SymMap ")
        @test occursin("ESM6 [RAW_SYMBOL] -> 42 [INSTRUMENT_ID]", ss)

        sysm = DBN.SystemMsg(hd, "Heartbeat", "0")
        sy = pp(sysm)
        @test startswith(sy, "System ")
        @test occursin("Heartbeat", sy)
    end

    @testset "Substructures print compactly" begin
        @test occursin("RecordHeader(", pp(hd))
        @test occursin("ts_event=$(ts_str)", pp(hd))
        lv = DBN.BidAskPair(212_340_000_000, 212_350_000_000, UInt32(300), UInt32(150),
            UInt32(3), UInt32(2))
        @test occursin("BidAskPair(bid=212.34 bsz=300 ask=212.35 asz=150 bc=3 ac=2", pp(lv))
    end

    @testset "UNDEF_TIMESTAMP renders as dash" begin
        hd_undef = DBN.RecordHeader(0x0c, DBN.RType.MBP_0_MSG, 0x0001, UInt32(1),
            DBN.UNDEF_TIMESTAMP)
        r = DBN.TradeMsg(hd_undef, 100_000_000_000, UInt32(1), DBN.Action.TRADE,
            DBN.Side.ASK, 0x00, 0x00, DBN.UNDEF_TIMESTAMP, Int32(0), UInt32(1))
        s = pp(r)
        @test occursin("Trade -", s)         # leading ts is a dash
    end
end
