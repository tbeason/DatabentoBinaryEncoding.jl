# Regression: MBOMsg wire layout must match the official DBN `MboMsg` struct.
#
# Before 0.1.7, read_mbo_msg / write_record(::MBOMsg) used a swapped layout
# (ts_recv read from bytes 16-23, order_id from 24-31, price from 40-47). The
# encoder mirrored the decoder, so files written by this package round-tripped
# and every self-consistency test passed — but any file produced by Databento
# (historical downloads, live captures written by other tools, the official
# test fixtures) decoded with order_id / price / ts_recv rotated:
#   order_id <- price bytes, price <- ts_recv bytes, ts_recv <- order_id bytes.
# Official layout (identical for DBN v1/v2/v3, 56 bytes):
#   hd(16) order_id u64 @16, price i64 @24, size u32 @32, flags u8 @36,
#   channel_id u8 @37, action @38, side @39, ts_recv u64 @40, ts_in_delta i32 @48,
#   sequence u32 @52.

@testset "MBOMsg wire layout matches the official DBN struct" begin
    data_dir = joinpath(@__DIR__, "data")

    # Databento's own MBO fixture (same two records in every DBN version).
    # Reference values from the official decoder:
    #   order_id 647784973705, price 3722.75, ts_recv 2020-12-28T13:00:00.000704060Z
    expected = (
        order_id    = UInt64(647784973705),
        price       = Int64(3_722_750_000_000),
        size        = UInt32(1),
        flags       = 0x80,
        channel_id  = 0x00,
        action      = Action.CANCEL,
        side        = Side.ASK,
        ts_event    = Int64(1609160400000429831),
        ts_recv     = Int64(1609160400000704060),
        ts_in_delta = Int32(22993),
        sequence    = UInt32(1170352),
    )

    fixtures = filter(f -> occursin(r"^test_data\.mbo(\.v[123])?\.dbn(\.zst)?$", f), readdir(data_dir))
    @test !isempty(fixtures)

    for f in fixtures
        @testset "$f" begin
            recs = read_dbn(joinpath(data_dir, f))
            @test length(recs) == 2
            r = recs[1]
            @test r isa MBOMsg
            @test r.hd.instrument_id == 5482
            @test r.hd.ts_event == expected.ts_event
            @test r.order_id == expected.order_id
            @test r.price == expected.price
            @test price_to_float(r.price) == 3722.75
            @test r.size == expected.size
            @test r.flags == expected.flags
            @test r.channel_id == expected.channel_id
            @test r.action == expected.action
            @test r.side == expected.side
            @test r.ts_recv == expected.ts_recv
            @test r.ts_in_delta == expected.ts_in_delta
            @test r.sequence == expected.sequence
            # Sanity invariants that the swapped layout violated: ts_recv is a
            # nanosecond timestamp at or after ts_event; price is a sane fixed-point value.
            for x in recs
                @test x.ts_recv >= x.hd.ts_event
                @test 0 < price_to_float(x.price) < 1_000_000
            end
        end
    end

    # Byte-exact re-encode of the official (uncompressed) fixtures: decoding then
    # re-encoding must reproduce the original record bytes, which pins the writer
    # to the wire layout independently of the reader.
    for f in filter(f -> endswith(f, ".dbn"), fixtures)
        @testset "re-encode $f" begin
            path = joinpath(data_dir, f)
            bytes = read(path)
            meta, recs = read_dbn_with_metadata(path)
            io = IOBuffer()
            enc = DBNEncoder(io, meta)
            for r in recs
                write_record(enc, r)
            end
            out = take!(io)
            @test length(out) == 2 * sizeof(MBOMsg)
            @test bytes[end-length(out)+1:end] == out
        end
    end

    # Hand-encoded record at the official offsets decodes to the right fields.
    @testset "hand-encoded official layout" begin
        ts0 = Int64(1_700_000_000_000_000_000)
        meta = Metadata(UInt8(3), "GLBX.MDP3", Schema.MBO, ts0, ts0 + 1, nothing,
                        SType.RAW_SYMBOL, SType.INSTRUMENT_ID, false,
                        String[], String[], String[], Tuple{String,String,Int64,Int64}[])
        io = IOBuffer()
        enc = DBNEncoder(io, meta)
        write_header(enc)
        write(io, UInt8(14)); write(io, UInt8(RType.MBO_MSG)); write(io, UInt16(1)); write(io, UInt32(42)); write(io, ts0)
        write(io, UInt64(777))                 # order_id @16
        write(io, Int64(1_234_000_000_000))    # price    @24  (1234.0)
        write(io, UInt32(5))                   # size     @32
        write(io, UInt8(0x80))                 # flags    @36
        write(io, UInt8(3))                    # channel  @37
        write(io, UInt8('A'))                  # action   @38
        write(io, UInt8('B'))                  # side     @39
        write(io, Int64(ts0 + 99))             # ts_recv  @40
        write(io, Int32(-7))                   # ts_in_delta @48
        write(io, UInt32(9))                   # sequence @52
        tmp = tempname() * ".dbn"
        try
            write(tmp, take!(io))
            r = only(read_dbn(tmp))
            @test r.order_id == 777
            @test r.price == 1_234_000_000_000
            @test r.size == 5
            @test r.flags == 0x80
            @test r.channel_id == 3
            @test r.action == Action.ADD
            @test r.side == Side.BID
            @test r.ts_recv == ts0 + 99
            @test r.ts_in_delta == -7
            @test r.sequence == 9
        finally
            safe_rm(tmp)
        end
    end
end
