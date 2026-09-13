//=============================================================================
// zero_padding.v
//
// Block 1 (Zero Padding / payload framer) of the CSS PHY transmitter.
//
// The blocks downstream (Serial-to-Parallel + Symbol Mapper, Interleaver)
// consume the PHR+PSDU bit stream in fixed-size groups 
//   1 Mbps  : groups of GROUP_SIZE = 6  bits (I,Q take 3 bits each per symbol)
//   250 kbps: groups of GROUP_SIZE = 24 bits
// so this block does two jobs:
//   1) pad_calc  -- given the true (PHR+PSDU) bit count, compute how many
//                   zero bits must be appended so the total is a multiple
//                   of GROUP_SIZE, and the resulting padded length.
//   2) bit gate  -- given a serial bit position in the PADDED stream, return
//                   the real PHR/PSDU bit for positions inside total_bits,
//                   or a hard-wired 0 for positions in the padding region.
//                   This lets the rest of the pipeline simply walk the
//                   padded stream by index without special-casing the tail.
//
// Both parts are purely combinational -- there's no physical "padding"
// happening in hardware, only address-range gating, exactly as described
// in the reference architecture (no extra ROM/RAM needed for this block).
//=============================================================================
`timescale 1ns/1ps

module zero_padding #(
    parameter GROUP_SIZE = 6     // 6 for 1 Mbps, 24 for 250 kbps
) (
    // ---- length / padding arithmetic --------------------------------------
    input  wire [15:0] total_bits,           // PHR(12) + PSDU(8*payloadLength) bit count
    // output wire [4:0]  pad_bits,            // 0 .. GROUP_SIZE-1 zero bits appended
    output wire [15:0] padded_total_bits,  // total_bits + pad_bits (multiple of GROUP_SIZE)

    // ---- serial bit gate ----------------------------------------------------
    input  wire [15:0] bit_index,           // 0-based position within the padded stream
    input  wire        payload_bit_in,     // value of PHR/PSDU bit `bit_index` (only meaningful
                                          // when bit_index < total_bits; framer/RAM supplies it)
    output wire         bit_out          // payload bit, or 0 inside the padding region
);

    // wire [15:0] remainder = total_bits % GROUP_SIZE; //! unsynsythable 

    wire [4:0]  pad_bits,            // 0 .. GROUP_SIZE-1 zero bits appended
    wire [15:0] remainder ;
    assign remainder = total_bits - (GROUP_SIZE * (total_bits / GROUP_SIZE )) ; 

    assign pad_bits           = (remainder == 0) ? 5'd0 : (GROUP_SIZE - remainder);
    assign padded_total_bits  = total_bits + pad_bits;

    assign bit_out = (bit_index < total_bits) ? payload_bit_in : 1'b0;

endmodule
