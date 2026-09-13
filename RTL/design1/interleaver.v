//=============================================================================
// interleaver.v
//
// Block 4 (Bit Interleaver) -- 250 kbps ONLY, bypassed entirely at 1 Mbps
// (the top-level controller simply never instantiates/uses this block on
// that path -- ENABLE here is provided anyway for standalone testability).
//
// Operates on 64 bits = two consecutive 32-bit codewords, viewed as 16
// groups of 4 bits (G0..G15). Output group i = input group G[PERM[i]],
// i.e. a pure re-ordering of 4-bit groups -- no bits are changed, only
// their position, matching the reference document description ("no ROM
// necessarily needed, a simple wired permutation").
//
// PERM = [0,13,2,15,4,9,6,11,8,5,10,7,12,1,14,3] (reference doc table).
//=============================================================================
`timescale 1ns/1ps

module interleaver (
    input  wire [63:0] data_in,   // group i occupies bits [63-4*i -: 4], i=0..15 (G0 = MSB group)
    output wire [63:0] data_out
);

    // PERM[i] = which input group feeds output position i
    function [3:0] perm_of; input [3:0] i; begin
        case (i)
            4'd0:  perm_of = 4'd0;
            4'd1:  perm_of = 4'd13;
            4'd2:  perm_of = 4'd2;
            4'd3:  perm_of = 4'd15;
            4'd4:  perm_of = 4'd4;
            4'd5:  perm_of = 4'd9;
            4'd6:  perm_of = 4'd6;
            4'd7:  perm_of = 4'd11;
            4'd8:  perm_of = 4'd8;
            4'd9:  perm_of = 4'd5;
            4'd10: perm_of = 4'd10;
            4'd11: perm_of = 4'd7;
            4'd12: perm_of = 4'd12;
            4'd13: perm_of = 4'd1;
            4'd14: perm_of = 4'd14;
            default: perm_of = 4'd3;
        endcase
    end endfunction

    genvar gi;
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : g_perm
            // group gi of data_out (bits [63-4*gi -: 4]) = group perm_of(gi) of data_in
            wire [3:0] src_idx = perm_of(gi[3:0]);
            assign data_out[63-4*gi -: 4] = data_in[63-4*src_idx -: 4];
        end
    endgenerate

endmodule
