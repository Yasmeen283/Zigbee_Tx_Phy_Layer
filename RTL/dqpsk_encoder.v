//=============================================================================
// dqpsk_encoder.v
//
// Step 7 of the PPDU processing chain / the "4 FF DELAY" + first "X" block
// of Figure 3-3.
//
// Implements S(n) = X(n) * S(n-4), per the reference equation, where X(n)
// is this cycle's QPSK rotation (from qpsk_mapper.v) and S(n-4) is the
// DQPSK symbol from 4 symbols ago.
//
// *** Why this is a rotate, not a real complex multiplier ***
// The initial condition is S(0)=S(1)=S(2)=S(3)=exp(j*pi/4) -- a UNIT
// MAGNITUDE point at 45 degrees, i.e. real=imag (both "+1" in the sign
// convention below, the 1/sqrt(2) scale factor is deliberately dropped
// here exactly as the reference project's own MATLAB code does -- only
// the phase matters for the chirp modulation stage, see complex_multiplier
// .v). X(n) is always one of the 4 axis rotations {+1,+j,-1,-j} (see
// qpsk_mapper.v). Rotating a 45/135/225/315-degree point by a multiple of
// 90 degrees lands on another 45/135/225/315-degree point -- so S(n)
// NEVER leaves the "both components +-1" representation, and the multiply
// reduces to a swap-and-conditional-negate (see the table in the module
// header comment below), exactly like complex_multiplier.v's own
// simplification. No real multiplier hardware is used here either.
//
// Handshake: mirrors the same style already used between csk_generator and
// its caller (single-cycle valid pulses). qpsk_valid indicates i_bit/q_bit
// (by way of qpsk_mapper's qpsk_quadrant) are valid THIS cycle; one cycle
// later, dqpsk_valid pulses with the new S(n) on dqpsk_sign_real/imag.
//
// Assumptions:
//   - qpsk_valid is a single-cycle pulse; qpsk_quadrant must be valid the
//     same cycle.
//   - reset re-initializes all 4 delay slots to the S(0..3) reference
//     value (sign_real=0, sign_imag=0, i.e. both "+1" in the 0=+1,1=-1
//     convention), per the standard's stated initial condition.
//   - There is no back-pressure: a new qpsk_valid pulse is assumed not to
//     arrive before the previous one's dqpsk_valid has been consumed
//     downstream (this module produces one output per input, one cycle
//     later, unconditionally).
//=============================================================================
`timescale 1ns/1ps

module dqpsk_encoder (
    input  wire       clk,
    input  wire       reset,          // synchronous, active-high -- reloads the
                                       // S(0..3) initial condition into the delay line

    input  wire        qpsk_valid,     // qpsk_quadrant is valid this cycle
    input  wire [1:0]  qpsk_quadrant,  // rotation to apply, from qpsk_mapper.v

    output reg         dqpsk_valid,    // new S(n) is valid this cycle (1-cycle pulse)
    output reg         dqpsk_sign_real,// S(n) real sign: 0 = +1, 1 = -1
    output reg         dqpsk_sign_imag // S(n) imag sign: 0 = +1, 1 = -1
);

    // ------------------------------------------------------------------
    // 4-deep delay line of previously-produced (sign_real, sign_imag)
    // pairs -- slot 0 is the OLDEST (this is S(n-4)); slot 3 is the most
    // recently produced symbol.
    // ------------------------------------------------------------------
    reg sr_q [0:3];
    reg si_q [0:3];
    integer k;

    // ------------------------------------------------------------------
    // Rotate S(n-4) = (sr_q[0], si_q[0]) by qpsk_quadrant -- see header
    // comment for the derivation:
    //   quadrant 0 (x  1): (sr,  si )
    //   quadrant 1 (x +j): (-si, sr )
    //   quadrant 2 (x -1): (-sr, -si)
    //   quadrant 3 (x -j): (si, -sr )
    // Sign bits use 0=+1,1=-1, so "negate" is just a bit flip (XOR 1).
    // ------------------------------------------------------------------
    reg new_sr, new_si;
    always @(*) begin
        case (qpsk_quadrant)
            2'd0: begin new_sr = sr_q[0];        new_si = si_q[0];        end
            2'd1: begin new_sr = ~si_q[0];       new_si = sr_q[0];        end
            2'd2: begin new_sr = ~sr_q[0];       new_si = ~si_q[0];       end
            2'd3: begin new_sr = si_q[0];        new_si = ~sr_q[0];       end
            default: begin new_sr = sr_q[0];     new_si = si_q[0];        end
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            for (k = 0; k < 4; k = k + 1) begin
                sr_q[k] <= 1'b0; // both +1 -> the exp(j*pi/4) reference point
                si_q[k] <= 1'b0;
            end
            dqpsk_valid     <= 1'b0;
            dqpsk_sign_real <= 1'b0;
            dqpsk_sign_imag <= 1'b0;
        end else begin
            dqpsk_valid <= 1'b0; // default; overridden below
            if (qpsk_valid) begin
                // shift the delay line: drop slot0 (just consumed),
                // push the new symbol in at slot3
                sr_q[0] <= sr_q[1]; si_q[0] <= si_q[1];
                sr_q[1] <= sr_q[2]; si_q[1] <= si_q[2];
                sr_q[2] <= sr_q[3]; si_q[2] <= si_q[3];
                sr_q[3] <= new_sr;  si_q[3] <= new_si;

                dqpsk_valid     <= 1'b1;
                dqpsk_sign_real <= new_sr;
                dqpsk_sign_imag <= new_si;
            end
        end
    end

endmodule
