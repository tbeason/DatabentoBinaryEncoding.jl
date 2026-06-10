# Regression tests for issues #32-#35, all found in one STATISTICS debugging
# session:
#   #32: read_stat_msg assumed the 80-byte v3 StatMsg layout and ignored
#        hd.length, so 64-byte v1/v2 records desynced the whole stream.
#   #33: stat_to_dataframe referenced nonexistent StatMsg fields
#        (stat_value, flags) and threw on any STATISTICS records.
#   #34: the metadata decoder kept only the first symbol-mapping interval,
#        silently dropping continuous-contract roll history.
#   #35: invalid Side/Action bytes threw and killed the decode stream while
#        InstrumentClass warned and defaulted.

@testset "issues #32-#35 regressions" begin

    data_path(f) = joinpath(@__DIR__, "data", f)

    function stat_metadata()
        return Metadata(
            UInt8(DBN_VERSION),      # version
            "TEST.DATA",             # dataset
            Schema.STATISTICS,       # schema
            1640995200000000000,     # start_ts
            1640995260000000000,     # end_ts
            UInt64(1000),            # limit
            SType.RAW_SYMBOL,        # stype_in
            SType.RAW_SYMBOL,        # stype_out
            false,                   # ts_out
            ["ES.n.0"],              # symbols
            String[],                # partial
            String[],                # not_found
            Tuple{String,String,Int64,Int64}[]  # mappings
        )
    end

    @testset "issue #32: pre-v3 64-byte StatMsg records decode without desync" begin
        # The shipped v1/v2/v3 statistics captures hold the same two records;
        # pre-fix the v1/v2 files desynced after the first record.
        recs_v1 = read_dbn(data_path("test_data.statistics.v1.dbn.zst"))
        recs_v2 = read_dbn(data_path("test_data.statistics.v2.dbn.zst"))
        recs_v3 = read_dbn(data_path("test_data.statistics.v3.dbn.zst"))

        @test length(recs_v1) == length(recs_v3)
        @test length(recs_v2) == length(recs_v3)
        @test all(r -> r isa StatMsg, recs_v1)
        @test all(r -> r isa StatMsg, recs_v2)

        for (old, new) in ((recs_v1, recs_v3), (recs_v2, recs_v3))
            for (a, b) in zip(old, new)
                @test a.ts_recv == b.ts_recv
                @test a.ts_ref == b.ts_ref
                @test a.price == b.price
                @test a.quantity == b.quantity
                @test a.sequence == b.sequence
                @test a.stat_type == b.stat_type
                @test a.update_action == b.update_action
                # Pre-v3 records are upgraded to the 80-byte v3 size
                @test a.hd.length == UInt8(20)
            end
        end

        # Synthetic stream: two hand-encoded 64-byte v1-layout StatMsg records.
        # Pre-fix the first read overran by 16 bytes, so the second record
        # decoded from garbage (the original desync symptom).
        ts0 = Int64(1_700_000_000_000_000_000)
        io = IOBuffer()
        encoder = DBNEncoder(io, stat_metadata())
        write_header(encoder)
        for (iid, qty, seq) in ((UInt32(42), Int32(12345), UInt32(7)),
                                (UInt32(43), typemax(Int32), UInt32(8)))
            write(io, UInt8(16))                      # length: 64 bytes / 4
            write(io, UInt8(RType.STAT_MSG))
            write(io, UInt16(1))                      # publisher_id
            write(io, iid)                            # instrument_id
            write(io, ts0)                            # ts_event
            write(io, UInt64(ts0 + 1))                # ts_recv
            write(io, UInt64(ts0 + 2))                # ts_ref
            write(io, Int64(100_000_000_000))         # price
            write(io, qty)                            # quantity (Int32 in v1/v2)
            write(io, seq)                            # sequence
            write(io, Int32(100))                     # ts_in_delta
            write(io, UInt16(9))                      # stat_type
            write(io, UInt16(0))                      # channel_id
            write(io, UInt8(1))                       # update_action
            write(io, UInt8(0))                       # stat_flags
            write(io, zeros(UInt8, 6))                # reserved (v1/v2 tail)
        end

        tmp = tempname() * ".dbn"
        try
            write(tmp, take!(io))
            recs = read_dbn(tmp)
            @test length(recs) == 2
            @test recs[1] isa StatMsg && recs[2] isa StatMsg
            @test recs[1].hd.instrument_id == 42
            @test recs[1].quantity == 12345
            @test recs[1].hd.length == UInt8(20)
            # The record after the v1 StatMsg is intact, not misaligned garbage
            @test recs[2].hd.instrument_id == 43
            @test recs[2].sequence == 8
            # v1 UNDEF_STAT_QUANTITY (typemax(Int32)) maps to the v3 sentinel
            @test recs[2].quantity == typemax(Int64)
        finally
            safe_rm(tmp)
        end

        # A malformed StatMsg (body size that matches no known layout) is
        # skipped — including on the typed read_dbn path — and an extended
        # record (v3 body + vendor tail) decodes with its header normalized
        # to the v3 size so re-encoding cannot misalign downstream readers.
        io = IOBuffer()
        encoder = DBNEncoder(io, stat_metadata())
        write_header(encoder)
        # Malformed: claims 72 bytes total = 56-byte body (not 48, not >=64)
        write(io, UInt8(18))
        write(io, UInt8(RType.STAT_MSG))
        write(io, UInt16(1)); write(io, UInt32(40)); write(io, ts0)
        write(io, zeros(UInt8, 56))
        # Extended v3: 88 bytes total = 72-byte body (64 v3 + 8 vendor tail)
        write(io, UInt8(22))
        write(io, UInt8(RType.STAT_MSG))
        write(io, UInt16(1)); write(io, UInt32(41)); write(io, ts0)
        write(io, UInt64(ts0 + 1))                # ts_recv
        write(io, UInt64(ts0 + 2))                # ts_ref
        write(io, Int64(100_000_000_000))         # price
        write(io, Int64(777))                     # quantity (Int64 in v3)
        write(io, UInt32(9))                      # sequence
        write(io, Int32(100))                     # ts_in_delta
        write(io, UInt16(9))                      # stat_type
        write(io, UInt16(0))                      # channel_id
        write(io, UInt8(1))                       # update_action
        write(io, UInt8(0))                       # stat_flags
        write(io, zeros(UInt8, 18 + 8))           # reserved + vendor tail
        # Trailing plain v3 record proves neither of the above desynced
        write(io, UInt8(20))
        write(io, UInt8(RType.STAT_MSG))
        write(io, UInt16(1)); write(io, UInt32(42)); write(io, ts0)
        write(io, UInt64(ts0 + 1)); write(io, UInt64(ts0 + 2))
        write(io, Int64(100_000_000_000)); write(io, Int64(888))
        write(io, UInt32(10)); write(io, Int32(100))
        write(io, UInt16(9)); write(io, UInt16(0))
        write(io, UInt8(1)); write(io, UInt8(0))
        write(io, zeros(UInt8, 18))

        tmp = tempname() * ".dbn"
        try
            write(tmp, take!(io))
            recs = read_dbn(tmp)   # STATISTICS schema -> typed StatMsg path
            @test length(recs) == 2          # malformed record skipped
            @test recs[1].hd.instrument_id == 41
            @test recs[1].quantity == 777
            @test recs[1].hd.length == UInt8(20)   # extended header normalized
            @test recs[2].hd.instrument_id == 42
            @test recs[2].quantity == 888
        finally
            safe_rm(tmp)
        end
    end

    @testset "issue #33: stat_to_dataframe uses real StatMsg fields" begin
        hd = RecordHeader(20, RType.STAT_MSG, 1, 66666, 1640995200000000700)
        msgs = [
            StatMsg(hd, 1640995200000000701, 1640995200000000000,
                    10055000000, 500, 54321, 5500, 8, 3, 1, 0x20),
            StatMsg(hd, 1640995200000000801, 1640995200000000100,
                    DBN.UNDEF_PRICE, typemax(Int64), 54322, 5600, 9, 3, 2, 0x00),
        ]
        df = DBN.records_to_dataframe(msgs)
        @test size(df, 1) == 2
        for col in ["ts_event", "ts_recv", "ts_ref", "stat_type", "channel_id",
                    "update_action", "price", "quantity", "flags",
                    "ts_in_delta", "sequence"]
            @test col in names(df)
        end
        @test df.price[1] == DBN.price_to_float(10055000000)
        @test isnan(df.price[2])    # UNDEF_PRICE -> NaN
        @test df.quantity == [500, typemax(Int64)]
        @test df.flags == [0x20, 0x00]
        @test df.stat_type == [8, 9]
    end

    @testset "issue #34: all symbol-mapping intervals survive a round-trip" begin
        # A continuous contract's roll history: one tuple per interval, plus a
        # second symbol to check grouping boundaries.
        roll_history = [
            ("ES.n.0", "ESH4", Int64(20240101), Int64(20240315)),
            ("ES.n.0", "ESM4", Int64(20240315), Int64(20240621)),
            ("ES.n.0", "ESU4", Int64(20240621), Int64(20240920)),
            ("NQ.n.0", "NQH4", Int64(20240101), Int64(20240315)),
        ]
        metadata = Metadata(
            UInt8(DBN_VERSION), "TEST.DATA", Schema.TRADES,
            1640995200000000000, 1640995260000000000, UInt64(1000),
            SType.CONTINUOUS, SType.RAW_SYMBOL, false,
            ["ES.n.0", "NQ.n.0"], String[], String[],
            roll_history,
        )
        hd = RecordHeader(12, RType.MBP_0_MSG, 1, 12345, 1640995200000000000)
        trade = TradeMsg(hd, 10055000000, 250, Action.TRADE, Side.ASK,
                         0x00, 1, 1640995200000000100, 2000, 87654)

        tmp = tempname() * ".dbn"
        try
            write_dbn(tmp, metadata, [trade])
            decoder = DBNDecoder(tmp)
            try
                @test decoder.metadata.mappings == roll_history
            finally
                close(decoder.io)
                decoder.io === decoder.base_io || close(decoder.base_io)
            end
        finally
            safe_rm(tmp)
        end
    end

    @testset "issue #35: invalid enum bytes warn and default instead of throwing" begin
        # Uniform policy across enums: never throw on a bad byte
        @test DBN.safe_action(0x00) == Action.NONE
        @test DBN.safe_action(UInt8('A')) == Action.ADD
        @test DBN.safe_action(0x88) == Action.NONE
        @test DBN.safe_side(0x00) == Side.NONE
        @test DBN.safe_side(UInt8('B')) == Side.BID
        @test DBN.safe_side(0x88) == Side.NONE
        @test DBN.safe_instrument_class(UInt8('F')) == InstrumentClass.FUTURE
        @test DBN.safe_instrument_class(0x74) == InstrumentClass.OTHER

        # A corrupted action/side byte must not kill the stream: corrupt the
        # first of two trade records on disk and decode both.
        metadata = stat_metadata()
        hd = RecordHeader(12, RType.MBP_0_MSG, 1, 12345, 1640995200000000000)
        trades = [
            TradeMsg(hd, 10055000000, 250, Action.TRADE, Side.ASK,
                     0x00, 1, 1640995200000000100, 2000, 87654),
            TradeMsg(hd, 10056000000, 300, Action.TRADE, Side.BID,
                     0x00, 1, 1640995200000000200, 2000, 87655),
        ]
        tmp = tempname() * ".dbn"
        try
            write_dbn(tmp, metadata, trades)
            bytes = read(tmp)
            # TradeMsg = 48 bytes: header(16) + price(8) + size(4) + action(1)
            # + side(1) + ... Records sit at the end of the file.
            rec1 = length(bytes) - 96
            @test bytes[rec1+29] == UInt8('T')   # action of record 1
            @test bytes[rec1+30] == UInt8('A')   # side of record 1
            bytes[rec1+29] = 0x88
            bytes[rec1+30] = 0x88
            write(tmp, bytes)

            recs = read_dbn(tmp)
            @test length(recs) == 2
            @test recs[1].action == Action.NONE
            @test recs[1].side == Side.NONE
            # The following record still decodes correctly
            @test recs[2].side == Side.BID
            @test recs[2].sequence == 87655
        finally
            safe_rm(tmp)
        end
    end
end
