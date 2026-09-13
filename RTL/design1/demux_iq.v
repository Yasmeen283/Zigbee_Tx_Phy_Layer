//=============================================================================
// demux_iq.v
//
// Block 2 (Demux / I-Q split) of the CSS PHY transmitter.
//
// Splits the (zero-padded) serial bit stream into two independent streams,
// alternating starting with I (Section 5 of the deep-dive doc):
//   bit_index 0 -> I     bit_index 1 -> Q     bit_index 2 -> I   ...
// i.e. even positions go to I, odd positions go to Q.
//
// This is purely combinational routing (matches "demux_iq" / "demux_1_2" in
// the original architecture): the actual accumulation into 3-bit (or 6-bit)
// groups for the Symbol Mapper happens in the top-level controller, which
// walks bit_index and uses i_valid/q_valid as write-enables into the I/Q
// shift registers.
//=============================================================================
`timescale 1ns/1ps

module demux_iq (
    input  wire        bit_in,     // padded-stream bit value at bit_index (from zero_padding)
    input  wire [15:0] bit_index,  // 0-based position within the padded stream
    output wire        i_bit,      // = bit_in, present only when i_valid
    output wire        q_bit,      // = bit_in, present only when q_valid
    output wire        i_valid,    // 1 when bit_index is even (this bit belongs to I path)
    output wire        q_valid     // 1 when bit_index is odd  (this bit belongs to Q path)
);

    assign i_valid = ~bit_index[0];
    assign q_valid =  bit_index[0];

    assign i_bit = bit_in;
    assign q_bit = bit_in;

endmodule
