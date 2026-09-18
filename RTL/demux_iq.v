
`timescale 1ns/1ps

module demux_iq (
    input  wire bit_in,           
    input  wire sel,             //bit index [0]
    output wire i_bit,          // = bit_in, present only when i_valid
    output wire q_bit,         // = bit_in, present only when q_valid
    output wire i_valid,      // 1 when bit_index is even (this bit belongs to I path)
    output wire q_valid      // 1 when bit_index is odd  (this bit belongs to Q path)
);

    assign i_valid = ~sel;
    assign q_valid =  sel;

    assign i_bit = bit_in;
    assign q_bit = bit_in;

endmodule
