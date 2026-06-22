# Regression for issue #40: records_to_dataframe threw FieldError on TBBO/MBP-1
# and MBP-10 because the converters read flat `bid_px_00…` fields that don't
# exist — the bid/ask data lives in the nested `levels::BidAskPair` (MBP-1 and
# the consolidated/BBO family) or `levels::NTuple{10,BidAskPair}` (MBP-10).

@testset "Issue #40: MBP/BBO records_to_dataframe" begin
    ts = Int64(1_700_000_000_000_000_000)
    hd(rt, id) = DBN.RecordHeader(UInt8(0), rt, UInt16(1), UInt32(id), ts)
    # Distinct values per level so a wrong index is caught.
    bap(o) = DBN.BidAskPair(Int64(1000 + o), Int64(2000 + o),
                            UInt32(10 + o), UInt32(20 + o), UInt32(o), UInt32(100 + o))

    @testset "MBP-1 reads through levels" begin
        recs = [DBN.MBP1Msg(hd(DBN.RType.MBP_1_MSG, 42), Int64(1000), UInt32(5),
                            DBN.Action.MODIFY, DBN.Side.BID, 0x00, 0x00,
                            ts, Int32(3), UInt32(7), bap(0))]
        df = records_to_dataframe(recs)   # must not throw
        @test df.bid_price == [price_to_float(Int64(1000))]
        @test df.ask_price == [price_to_float(Int64(2000))]
        @test df.bid_size == UInt32[10]
        @test df.ask_size == UInt32[20]
        @test df.bid_ct == UInt32[0]
        @test df.ask_ct == UInt32[100]
        @test df.action == ["MODIFY"]
        @test df.instrument_id == UInt32[42]
    end

    @testset "MBP-10 expands all 10 nested levels" begin
        levels = ntuple(i -> bap(i - 1), 10)
        recs = [DBN.MBP10Msg(hd(DBN.RType.MBP_10_MSG, 42), Int64(1000), UInt32(5),
                             DBN.Action.MODIFY, DBN.Side.BID, 0x00, 0x00,
                             ts, Int32(3), UInt32(7), levels)]
        df = records_to_dataframe(recs)   # must not throw
        @test nrow(df) == 10
        @test df.level == collect(0:9)
        @test df.bid_price == [price_to_float(Int64(1000 + o)) for o in 0:9]
        @test df.ask_price == [price_to_float(Int64(2000 + o)) for o in 0:9]
        @test df.bid_size == UInt32[10 + o for o in 0:9]
    end

    @testset "consolidated/BBO family route to the bid/ask converter" begin
        # Each shares the MBP-1 layout; previously these fell through to
        # mixed_records_to_dataframe and produced no bid_price column.
        for (T, rt) in ((DBN.TCBBOMsg, DBN.RType.TCBBO_MSG),
                        (DBN.CMBP1Msg, DBN.RType.CMBP_1_MSG),
                        (DBN.CBBO1sMsg, DBN.RType.CBBO_1S_MSG),
                        (DBN.CBBO1mMsg, DBN.RType.CBBO_1M_MSG),
                        (DBN.BBO1sMsg, DBN.RType.BBO_1S_MSG),
                        (DBN.BBO1mMsg, DBN.RType.BBO_1M_MSG))
            recs = [T(hd(rt, 42), Int64(1000), UInt32(5),
                      DBN.Action.NONE, DBN.Side.NONE, 0x00, 0x00,
                      ts, Int32(0), UInt32(7), bap(0))]
            df = records_to_dataframe(recs)
            @test hasproperty(df, :bid_price)
            @test df.bid_price == [price_to_float(Int64(1000))]
            @test df.ask_price == [price_to_float(Int64(2000))]
        end
    end
end
