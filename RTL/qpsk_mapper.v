//=============================================================================
// qpsk_mapper.v
//
// Block 5.2 (QPSK Mapper) of the CSS PHY transmitter.
//
// Combines one I chip and one Q chip (bipolar: 1 = +1, 0 = -1) into a single
// complex QPSK symbol, per the formula given in Section 8.2 of the deep-dive
// doc (straight from the MATLAB reference code):
//
//     QPSK_symbol = ((I + Q) - j*(I - Q)) / 2
//
// With I,Q in {+1,-1} this always lands on one of the 4 constellation
// points, each with exactly one of {real, imag} equal to 0 and the other
// equal to +-1:
//     I=+1,Q=+1 -> ( +1 ,  0 )
//     I=+1,Q=-1 -> (  0 , -1 )
//     I=-1,Q=+1 -> (  0 , +1 )
//     I=-1,Q=-1 -> ( -1 ,  0 )
//
// Purely combinational -- one QPSK symbol per (i_bit,q_bit) pair, no clock
// needed (matches "QPSK modulation is performed using multiplexers" in the
// reference architecture).
//=============================================================================
`timescale 1ns/1ps

module qpsk_mapper (
    input  wire              i_bit,       // bipolar I chip: 1 = +1, 0 = -1
    input  wire              q_bit,       // bipolar Q chip: 1 = +1, 0 = -1
    output wire signed [1:0] qpsk_real,   // in {-1, 0, +1}
    output wire signed [1:0] qpsk_imag    // in {-1, 0, +1}
);

    wire signed [1:0] i_val = i_bit ? 2'sd1 : -2'sd1;
    wire signed [1:0] q_val = q_bit ? 2'sd1 : -2'sd1;

    // Widen before adding/subtracting so -2..+2 never truncates.
    wire signed [2:0] i_sum  = i_val + q_val;
    wire signed [2:0] i_diff = i_val - q_val;

    // (I+Q)/2 and -(I-Q)/2 ; sums/differences of +-1 are always even (-2,0,+2)
    // so the arithmetic right shift is an exact divide-by-2, no rounding.
    assign qpsk_real =  (i_sum  >>> 1);
    assign qpsk_imag = -(i_diff >>> 1);

endmodule
