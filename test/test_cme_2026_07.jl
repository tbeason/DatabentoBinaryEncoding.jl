# Coverage for Databento's CME (GLBX.MDP3) normalization changes of 2026-07-07
# (https://databento.com/blog/cme-normalization-changes-2026-07) and the DBN
# enum/flag additions that go with them:
#   1. per-leg definition records: one InstrumentDefMsg per strategy leg
#   2. standalone F_LAST MBO record: action='N', flags=F_LAST, price UNDEF, size 0
#   3. StatType UPPER_PRICE_LIMIT (17) / LOWER_PRICE_LIMIT (18)
#   4. TradingEvent IMPLIED_MATCHING_ON (3) / IMPLIED_MATCHING_OFF (4)
#   5. InstrumentClass FX_SPOT ('X') for FX spot, and INDEX ('I') from the spec
#
# Everything is round-tripped through the real encoder/decoder so the tests
# exercise the wire layout, not just the Julia constructors.

@testset "CME 2026-07 normalization / enum coverage" begin
    ts0 = Int64(1_783_411_200_000_000_000)  # 2026-07-07T00:00:00Z

    mk_meta(schema) = Metadata(UInt8(3), "GLBX.MDP3", schema, ts0,
                               ts0 + 3_600_000_000_000, nothing,
                               SType.RAW_SYMBOL, SType.INSTRUMENT_ID, false,
                               String[], String[], String[],
                               Tuple{String,String,Int64,Int64}[])

    function roundtrip(schema, records)
        tmp = tempname() * ".dbn"
        try
            write_dbn(tmp, mk_meta(schema), records)
            return read_dbn(tmp)
        finally
            safe_rm(tmp)
        end
    end

    @testset "enum and flag values match the DBN spec" begin
        # StatType (UInt16)
        @test UInt16(StatType.OPENING_PRICE) == 1
        @test UInt16(StatType.SETTLEMENT_PRICE) == 3
        @test UInt16(StatType.OPEN_INTEREST) == 9
        @test UInt16(StatType.UPPER_PRICE_LIMIT) == 17
        @test UInt16(StatType.LOWER_PRICE_LIMIT) == 18
        @test UInt16(StatType.AUCTION_COLLAR_LOWER_PRICE) == 26
        @test UInt16(StatType.VENUE_SPECIFIC_VOLUME_1) == 10001
        @test UInt16(StatType.VENUE_SPECIFIC_PRICE_1) == 10002
        @test safe_stat_type(17) == StatType.UPPER_PRICE_LIMIT
        @test safe_stat_type(UInt16(18)) == StatType.LOWER_PRICE_LIMIT
        @test safe_stat_type(0x7FFF) == StatType.UNKNOWN
        @test safe_stat_type(0) == StatType.UNKNOWN

        # TradingEvent (UInt16)
        @test UInt16(TradingEvent.NONE) == 0
        @test UInt16(TradingEvent.NO_CANCEL) == 1
        @test UInt16(TradingEvent.CHANGE_TRADING_SESSION) == 2
        @test UInt16(TradingEvent.IMPLIED_MATCHING_ON) == 3
        @test UInt16(TradingEvent.IMPLIED_MATCHING_OFF) == 4
        @test safe_trading_event(3) == TradingEvent.IMPLIED_MATCHING_ON
        @test safe_trading_event(UInt16(4)) == TradingEvent.IMPLIED_MATCHING_OFF
        @test safe_trading_event(999) == TradingEvent.NONE

        # InstrumentClass single-char codes
        @test InstrumentClass.FX_SPOT == InstrumentClass.T(UInt8('X'))
        @test InstrumentClass.INDEX == InstrumentClass.T(UInt8('I'))
        @test DBN.safe_instrument_class(UInt8('X')) == InstrumentClass.FX_SPOT
        @test DBN.safe_instrument_class(UInt8('I')) == InstrumentClass.INDEX

        # Record flags bit field
        @test F_LAST == 0x80
        @test F_TOB == 0x40
        @test F_SNAPSHOT == 0x20
        @test F_MBP == 0x10
        @test F_BAD_TS_RECV == 0x08
        @test F_MAYBE_BAD_BOOK == 0x04
        @test F_PUBLISHER_SPECIFIC == 0x02
        @test has_flag(0x80, F_LAST)
        @test has_flag(F_LAST | F_TOB, F_TOB)
        @test has_flag(UInt8(0xA0), F_SNAPSHOT)
        @test !has_flag(0x00, F_LAST)
        @test !has_flag(F_TOB, F_LAST)
    end

    @testset "standalone F_LAST MBO record round-trips" begin
        # MBOMsg is 56 bytes -> hd.length 14
        hd(iid) = RecordHeader(UInt8(14), RType.MBO_MSG, UInt16(1), UInt32(iid), ts0)
        add = MBOMsg(hd(42), UInt64(1001), Int64(5_000_000_000_000), UInt32(3),
                     0x00, 0x00, Action.ADD, Side.BID, ts0 + 10, Int32(100), UInt32(1))
        # Event terminator as CME now publishes it: no book effect, only the
        # F_LAST flag (and its own ts_recv) carry information.
        last = MBOMsg(hd(42), UInt64(0), UNDEF_PRICE, UInt32(0),
                      F_LAST, 0x00, Action.NONE, Side.NONE, ts0 + 20, Int32(100), UInt32(2))

        recs = roundtrip(Schema.MBO, [add, last])
        @test length(recs) == 2
        @test all(r -> r isa MBOMsg, recs)

        # The book update itself no longer carries F_LAST
        @test !has_flag(recs[1].flags, F_LAST)
        @test recs[1].action == Action.ADD

        r = recs[2]
        @test r.action == Action.NONE
        @test r.flags == F_LAST
        @test has_flag(r.flags, F_LAST)
        @test r.price == UNDEF_PRICE
        @test r.size == 0
        @test r.side == Side.NONE
        @test r.ts_recv == ts0 + 20
        @test r.hd.instrument_id == 42

        # Export renders the undefined price as NaN, and keeps the flag byte
        mbos = MBOMsg[x for x in recs]
        df = records_to_dataframe(mbos)
        @test size(df, 1) == 2
        @test isnan(df.price[2])
        @test df.flags[2] == F_LAST
        @test df.size[2] == 0
        @test !isnan(df.price[1])

        # Compact printing must not choke on the UNDEF_PRICE sentinel
        s = sprint(show, r)
        @test !isempty(s)
    end

    @testset "price-limit statistics (stat_type 17/18) round-trip" begin
        # v3 StatMsg is 80 bytes -> hd.length 20
        hd = RecordHeader(UInt8(20), RType.STAT_MSG, UInt16(1), UInt32(7), ts0)
        mk_stat(stype, px, seq) = StatMsg(hd, UInt64(ts0 + 1), UInt64(ts0), Int64(px),
                                          typemax(Int64), UInt32(seq), Int32(0),
                                          UInt16(stype), UInt16(0), UInt8(1), UInt8(0))
        upper = mk_stat(StatType.UPPER_PRICE_LIMIT, 5_100_000_000_000, 1)
        lower = mk_stat(StatType.LOWER_PRICE_LIMIT, 4_900_000_000_000, 2)

        recs = roundtrip(Schema.STATISTICS, [upper, lower])
        @test length(recs) == 2
        @test all(r -> r isa StatMsg, recs)
        @test recs[1].stat_type == 17
        @test recs[2].stat_type == 18
        @test safe_stat_type(recs[1].stat_type) == StatType.UPPER_PRICE_LIMIT
        @test safe_stat_type(recs[2].stat_type) == StatType.LOWER_PRICE_LIMIT
        @test recs[1].stat_type == UInt16(StatType.UPPER_PRICE_LIMIT)
        @test recs[1].price == 5_100_000_000_000
        @test recs[2].price == 4_900_000_000_000
        # quantity is unset for price statistics
        @test recs[1].quantity == typemax(Int64)

        df = records_to_dataframe(StatMsg[x for x in recs])
        @test df.stat_type == [17, 18]
    end

    @testset "implied-matching status events round-trip" begin
        # StatusMsg is 40 bytes -> hd.length 10
        hd = RecordHeader(UInt8(10), RType.STATUS_MSG, UInt16(1), UInt32(7), ts0)
        mk_status(ev) = StatusMsg(hd, UInt64(ts0 + 1), UInt16(1), UInt16(0), UInt16(ev),
                                  UInt8('Y'), UInt8('Y'), UInt8('~'))
        on  = mk_status(TradingEvent.IMPLIED_MATCHING_ON)
        off = mk_status(TradingEvent.IMPLIED_MATCHING_OFF)

        recs = roundtrip(Schema.STATUS, [on, off])
        @test length(recs) == 2
        @test all(r -> r isa StatusMsg, recs)
        @test recs[1].trading_event == 3
        @test recs[2].trading_event == 4
        @test safe_trading_event(recs[1].trading_event) == TradingEvent.IMPLIED_MATCHING_ON
        @test safe_trading_event(recs[2].trading_event) == TradingEvent.IMPLIED_MATCHING_OFF
        @test recs[1].is_trading == UInt8('Y')

        df = records_to_dataframe(StatusMsg[x for x in recs])
        @test df.trading_event == [3, 4]
    end

    @testset "per-leg definition records and FX-spot / index classes" begin
        # v3 InstrumentDefMsg is 520 bytes -> hd.length 130
        function mk_def(iid, sym, cls; leg_count = 0, leg_index = 0, leg_iid = 0,
                        leg_sym = "", leg_side = Side.NONE, leg_cls = InstrumentClass.OTHER)
            hd = RecordHeader(UInt8(130), RType.INSTRUMENT_DEF_MSG, UInt16(1), UInt32(iid), ts0)
            InstrumentDefMsg(hd, ts0 + 1,
                # prices / qty
                25_000_000, 1_000_000_000,
                ts0 + 86_400_000_000_000, ts0 - 86_400_000_000_000,
                UNDEF_PRICE, UNDEF_PRICE, UNDEF_PRICE, 0, 0, 0, 0,
                # ints
                0, 0, UInt64(iid), 0, 10, 1, 1000, 1, 1, 1, 1, 1, 0, 1, 0, 1, 2026, 0, 1,
                # strings
                "USD", "USD", "", sym, "ES", "XCME", "ES", "FFICSX", "FUT", "Index", "", "",
                # class / misc
                cls, UNDEF_PRICE, 'F', 0, 0, 0, 0, 0, 0, 'A', 12, 0, 0, false, 0, 0, 0,
                # legs
                leg_count, leg_index, leg_iid, leg_sym, leg_side, 0, leg_cls,
                0, 0, 0, 0, 0, 0)
        end

        # A straddle now produces one definition record per leg, sharing the
        # strategy's instrument_id.
        leg1 = mk_def(100, "UD:1V: VT 0625K5000", InstrumentClass.OPTION_SPREAD;
                      leg_count = 2, leg_index = 0, leg_iid = 201, leg_sym = "ESM6 C5000",
                      leg_side = Side.BID, leg_cls = InstrumentClass.CALL)
        leg2 = mk_def(100, "UD:1V: VT 0625K5000", InstrumentClass.OPTION_SPREAD;
                      leg_count = 2, leg_index = 1, leg_iid = 202, leg_sym = "ESM6 P5000",
                      leg_side = Side.ASK, leg_cls = InstrumentClass.PUT)
        # FX spot now reports instrument_class = 'X' instead of 'F'
        fx  = mk_def(300, "EURUSD", InstrumentClass.FX_SPOT)
        # 'I' is in the DBN spec; make sure it survives instead of falling to OTHER
        idx = mk_def(400, "SPX", InstrumentClass.INDEX)

        recs = roundtrip(Schema.DEFINITION, [leg1, leg2, fx, idx])
        @test length(recs) == 4
        @test all(r -> r isa InstrumentDefMsg, recs)

        legs = [r for r in recs if r.hd.instrument_id == 100]
        @test length(legs) == 2                       # one record per leg, not per strategy
        @test all(r -> r.leg_count == 2, legs)
        @test [r.leg_index for r in legs] == [0, 1]
        @test [r.leg_instrument_id for r in legs] == [201, 202]
        @test [r.leg_raw_symbol for r in legs] == ["ESM6 C5000", "ESM6 P5000"]
        @test [r.leg_side for r in legs] == [Side.BID, Side.ASK]
        @test [r.leg_instrument_class for r in legs] == [InstrumentClass.CALL, InstrumentClass.PUT]
        @test all(r -> r.instrument_class == InstrumentClass.OPTION_SPREAD, legs)
        @test all(r -> r.raw_symbol == "UD:1V: VT 0625K5000", legs)

        @test recs[3].instrument_class == InstrumentClass.FX_SPOT
        @test recs[3].raw_symbol == "EURUSD"
        @test recs[3].leg_count == 0

        @test recs[4].instrument_class == InstrumentClass.INDEX

        # DataFrame export keeps one row per leg and the class names
        df = records_to_dataframe(InstrumentDefMsg[x for x in recs])
        @test size(df, 1) == 4
        @test count(==(100), df.instrument_id) == 2
        @test occursin("FX_SPOT", df.instrument_class[3])
        @test occursin("INDEX", df.instrument_class[4])
    end
end
