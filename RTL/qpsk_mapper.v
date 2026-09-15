//=============================================================================
// qpsk_mapper.v
//
// "MUX" block of Figure 3-3 / Step 6 of the PPDU processing chain.
//
// Converts one (I,Q) bit pair into the QPSK rotation value the DQPSK
// differential encoder needs. This is drawn as a MUX in the architecture
// diagram (not an arithmetic block) because it really is just a 4-entry
// lookup, not a computation -- confirmed against the deep-dive reference
// formula QPSK_symbol = ((I+Q) - j(I-Q))/2, which always lands on one of
// the four axis points {+1, +j, -1, -j}, never a general complex value:
//
//   I  Q  | QPSK_symbol | quadrant code
//   0  0  |     +1      |      00
//   1  0  |     +j      |      01
//   1  1  |     -1      |      10
//   0  1  |     -j      |      11
//
// (I=1,Q=0 bit convention matches the project-wide "0 = +1, 1 = -1" sign
// convention used everywhere else -- I here is being read as a bipolar
// +1/-1 value the same way dqpsk_sign_real/imag are, NOT as a magnitude.)
//
// qpsk_quadrant is a rotation count in units of 90 degrees (how many
// times to rotate by +j), consumed directly by dqpsk_encoder.v.
//
// Purely combinational -- one (I,Q) pair in, one quadrant code out, same
// cycle. No clock needed.
//=============================================================================
`timescale 1ns/1ps

module qpsk_mapper (
    input  wire       i_bit,          // 0 = +1, 1 = -1 (project-wide sign convention)
    input  wire       q_bit,          // 0 = +1, 1 = -1
    output reg  [1:0] qpsk_quadrant   // 00=+1, 01=+j, 10=-1, 11=-j (rotation count x90 deg)
);

    always @(*) begin
        case ({i_bit, q_bit})
            2'b00:   qpsk_quadrant = 2'd0; // +1
            2'b10:   qpsk_quadrant = 2'd1; // +j
            2'b11:   qpsk_quadrant = 2'd2; // -1
            2'b01:   qpsk_quadrant = 2'd3; // -j
            default: qpsk_quadrant = 2'd0;
        endcase
    end

endmodule
