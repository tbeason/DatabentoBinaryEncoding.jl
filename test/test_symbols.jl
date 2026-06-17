# Symbol resolution: symbol_map / symbol_for / add_symbol_column! /
# records_to_dataframe(records, metadata).

@testset "Symbol resolution" begin
    ts(d::Date) = DBN.datetime_to_ts(DateTime(d))

    # AAPL rolls instrument id mid-range (101 -> 111); MSFT is stable (102).
    mappings = [
        ("AAPL", "101", 20240102, 20240104),
        ("AAPL", "111", 20240104, 20240106),
        ("MSFT", "102", 20240102, 20240106),
    ]
    md = DBN.Metadata(3, "XNAS.ITCH", DBN.Schema.TRADES, 0, nothing, nothing,
                      DBN.SType.RAW_SYMBOL, DBN.SType.INSTRUMENT_ID, false,
                      ["AAPL", "MSFT"], String[], String[], mappings)

    @testset "symbol_map" begin
        smap = symbol_map(md)
        @test length(smap) == 3
        @test smap[UInt32(101)] == [(20240102, 20240104, "AAPL")]
        @test smap[UInt32(111)] == [(20240104, 20240106, "AAPL")]
        @test smap[UInt32(102)] == [(20240102, 20240106, "MSFT")]
    end

    @testset "symbol_for (map and metadata forms)" begin
        smap = symbol_map(md)
        @test symbol_for(smap, 101, ts(Date(2024, 1, 3))) == "AAPL"
        @test symbol_for(smap, 111, ts(Date(2024, 1, 5))) == "AAPL"   # rolled id
        @test symbol_for(smap, 102, ts(Date(2024, 1, 2))) == "MSFT"   # inclusive start
        @test symbol_for(smap, 101, ts(Date(2024, 1, 4))) === nothing # exclusive end
        @test symbol_for(smap, 101, ts(Date(2024, 1, 5))) === nothing # out of interval
        @test symbol_for(smap, 999, ts(Date(2024, 1, 3))) === nothing # unknown id
        # metadata convenience form rebuilds the map internally
        @test symbol_for(md, 102, ts(Date(2024, 1, 3))) == "MSFT"
    end

    @testset "degenerate single-day interval (sd == ed)" begin
        md_pt = DBN.Metadata(3, "X", DBN.Schema.TRADES, 0, nothing, nothing,
                             DBN.SType.RAW_SYMBOL, DBN.SType.INSTRUMENT_ID, false,
                             ["ZZ"], String[], String[],
                             [("ZZ", "7", 20240103, 20240103)])
        @test symbol_for(md_pt, 7, ts(Date(2024, 1, 3))) == "ZZ"
        @test symbol_for(md_pt, 7, ts(Date(2024, 1, 4))) === nothing
    end

    hdr(id, d) = DBN.RecordHeader(0, DBN.RType.MBP_0_MSG, 1, UInt32(id), ts(d))
    recs = [
        DBN.TradeMsg(hdr(101, Date(2024, 1, 3)), 100, 5, DBN.Action.TRADE, DBN.Side.BID, 0x00, 0, ts(Date(2024, 1, 3)), 0, 1),
        DBN.TradeMsg(hdr(102, Date(2024, 1, 5)), 200, 7, DBN.Action.TRADE, DBN.Side.ASK, 0x00, 0, ts(Date(2024, 1, 5)), 0, 2),
        DBN.TradeMsg(hdr(999, Date(2024, 1, 3)), 300, 9, DBN.Action.TRADE, DBN.Side.BID, 0x00, 0, ts(Date(2024, 1, 3)), 0, 3),
    ]

    @testset "records_to_dataframe with symbols" begin
        df = records_to_dataframe(recs, md)
        @test isequal(df.symbol, ["AAPL", "MSFT", missing])
        # symbols=false matches the one-argument frame exactly (no :symbol col)
        @test !hasproperty(records_to_dataframe(recs, md; symbols = false), :symbol)
    end

    @testset "add_symbol_column! custom column name" begin
        df = records_to_dataframe(recs)
        add_symbol_column!(df, md; column = :ticker)
        @test isequal(df.ticker, ["AAPL", "MSFT", missing])
    end

    @testset "non-INSTRUMENT_ID stype_out fills missing + warns" begin
        md_raw = DBN.Metadata(3, "X", DBN.Schema.TRADES, 0, nothing, nothing,
                              DBN.SType.RAW_SYMBOL, DBN.SType.RAW_SYMBOL, false,
                              ["AAPL"], String[], String[], mappings)
        @test isempty(symbol_map(md_raw))
        local df
        @test_logs (:warn,) (df = records_to_dataframe(recs, md_raw))
        @test all(ismissing, df.symbol)
    end

    @testset "empty frame is a no-op" begin
        df = records_to_dataframe(DBN.TradeMsg[], md)
        @test !hasproperty(df, :symbol)
    end
end
