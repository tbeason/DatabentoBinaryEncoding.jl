# Regression: the v3 StatMsg "undefined quantity" sentinel on the wire is
# typemax(Int64) (0x7fff_ffff_ffff_ffff, i64::MAX in the dbn crate). Through
# 0.1.6 the encoder wrote 0xffff_ffff_ffff_ffff (-1) for an undefined quantity,
# so other readers (databento, duckdb-dbn) showed -1 instead of NULL/NaN and a
# Julia round trip of an undefined quantity came back as -1.

@testset "StatMsg undefined quantity is written as typemax(Int64)" begin
    ts0 = Int64(1_700_000_000_000_000_000)
    meta = Metadata(UInt8(3), "GLBX.MDP3", Schema.STATISTICS, ts0, ts0 + 1, nothing,
                    SType.RAW_SYMBOL, SType.INSTRUMENT_ID, false,
                    String[], String[], String[], Tuple{String,String,Int64,Int64}[])
    hd = RecordHeader(UInt8(20), RType.STAT_MSG, UInt16(1), UInt32(7), ts0)
    mk(qty, seq) = StatMsg(hd, UInt64(ts0 + 1), UInt64(ts0), Int64(5_100_000_000_000), qty,
                           UInt32(seq), Int32(0), UInt16(17), UInt16(0), UInt8(1), UInt8(0))
    undef_q = mk(typemax(Int64), 1)
    neg_one = mk(Int64(-1), 2)        # a real -1 must stay -1 (not be confused with UNDEF)
    normal  = mk(Int64(12345), 3)

    # Raw bytes: quantity is the i64 at offset 40 of the 80-byte v3 record.
    io = IOBuffer()
    enc = DBNEncoder(io, meta)
    write_record(enc, undef_q)
    bytes = take!(io)
    @test length(bytes) == 80
    @test reinterpret(Int64, bytes[41:48])[1] == typemax(Int64)
    @test bytes[41:48] == UInt8[0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f]

    # Round trip preserves the sentinel, a genuine -1, and a normal value.
    tmp = tempname() * ".dbn"
    try
        write_dbn(tmp, meta, [undef_q, neg_one, normal])
        recs = read_dbn(tmp)
        @test length(recs) == 3
        @test recs[1].quantity == typemax(Int64)
        @test recs[2].quantity == -1
        @test recs[3].quantity == 12345
        # DataFrame export: the sentinel is the only one that is not a real quantity
        df = records_to_dataframe(StatMsg[r for r in recs])
        @test df.quantity[2] == -1 && df.quantity[3] == 12345
    finally
        safe_rm(tmp)
    end
end
