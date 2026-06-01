# Regression tests for issue #23:
#   "Generic read_record crashes on DBN v3 captures: invalid value for Enum
#    SType: 255."
#
# A DBN v3 live gateway can emit a SymbolMappingMsg (or other control record)
# whose stype byte is 0xFF, the documented "unset" sentinel. The generic decode
# path did an unguarded `SType.T(0xFF)`, which threw
# `ArgumentError: invalid value for Enum SType: 255`, making real v3 captures
# undecodable through `read_record`.
#
# Why this slipped through: every prior SymbolMappingMsg test constructed the
# record via the typed Julia constructor with *valid* enum values, then wrote
# and read it back. A construct -> encode -> decode round-trip can never produce
# a 0xFF stype byte if the type system can't represent one, so the round-trip
# suite was structurally blind to this sentinel. These tests exercise the
# sentinel explicitly.

@testset "issue #23: unset (0xFF) stype in SymbolMappingMsg" begin

    @testset "SType models the 0xFF unset sentinel" begin
        # The fix adds an explicit UNDEF member so the enum constructor is total
        # on the sentinel instead of throwing.
        @test DBN.SType.T(0xFF) == DBN.SType.UNDEF
        @test UInt8(DBN.SType.UNDEF) == 0xFF          # round-trips on the wire
    end

    # Build a v3 (MIX schema) file with a SymbolMappingMsg whose stype_in and
    # stype_out are both unset (0xFF), interleaved with a data record, mirroring
    # the interleaving in a real live capture.
    function build_v3_file_with_unset_stype()
        metadata = DBN.Metadata(
            UInt8(3), "TEST.MOCK", DBN.Schema.MIX,
            Int64(0), nothing, nothing, nothing,
            DBN.SType.INSTRUMENT_ID, false,
            String[], String[], String[],
            Tuple{String,String,Int64,Int64}[],
        )
        ts0 = Int64(1_700_000_000_000_000_000)

        # v2+ SymbolMappingMsg layout written by the encoder:
        #   header(16) + stype_in(1) + sym_in[71] + stype_out(1) + sym_out[71]
        #   + start_ts(8) + end_ts(8) = 176 bytes / 4 = 44 units.
        smap_hd = DBN.RecordHeader(UInt8(44), DBN.RType.SYMBOL_MAPPING_MSG,
                                   UInt16(1), UInt32(100), ts0)
        smap = DBN.SymbolMappingMsg(
            smap_hd,
            DBN.SType.UNDEF, "",        # stype_in unset -> 0xFF on the wire
            DBN.SType.UNDEF, "100",     # stype_out unset -> 0xFF on the wire
            ts0, ts0 + 1_000_000)

        trade_hd = DBN.RecordHeader(UInt8(0), DBN.RType.MBP_0_MSG,
                                    UInt16(1), UInt32(101), ts0 + 2_000_000)
        trade = DBN.TradeMsg(
            trade_hd, Int64(150_000_000_000), UInt32(100),
            DBN.Action.TRADE, DBN.Side.ASK, UInt8(0), UInt8(1),
            ts0 + 2_000_000, Int32(0), UInt32(1))

        tmp, io = mktemp(); close(io)
        DBN.write_dbn(tmp, metadata, DBN.DBNRecord[smap, trade])
        return tmp
    end

    # Drain every record from a freshly-opened decoder, returning the vector.
    # Pre-fix, this threw `ArgumentError: invalid value for Enum SType: 255` on
    # the first SymbolMappingMsg.
    function decode_all(path)
        dec = DBN.DBNDecoder(path)   # constructor reads the header/metadata
        @test dec.metadata.version == 3
        recs = DBN.DBNRecord[]
        try
            while true
                r = DBN.read_record(dec)
                r === nothing && break
                push!(recs, r)
            end
        finally
            close(dec.io)
            dec.io === dec.base_io || close(dec.base_io)
        end
        return recs
    end

    @testset "generic read_record decodes the stream without throwing" begin
        path = build_v3_file_with_unset_stype()
        try
            recs = decode_all(path)

            smaps = filter(r -> r isa DBN.SymbolMappingMsg, recs)
            @test length(smaps) == 1
            @test smaps[1].stype_in == DBN.SType.UNDEF
            @test smaps[1].stype_out == DBN.SType.UNDEF
            @test smaps[1].stype_out_symbol == "100"
            # The interleaved data record still decodes after the control record.
            @test count(r -> r isa DBN.TradeMsg, recs) == 1
        finally
            safe_rm(path)
        end
    end
end
