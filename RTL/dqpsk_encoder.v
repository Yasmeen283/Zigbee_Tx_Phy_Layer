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


    // 4-deep delay line of previously-produced (sign_real, sign_imag)
    // pairs -- slot 0 is the OLDEST (this is S(n-4)); slot 3 is the most
    // recently produced symbol.

    reg sr_q [0:3];
    reg si_q [0:3];
    integer k;


    // Rotate S(n-4) = (sr_q[0], si_q[0]) by qpsk_quadrant -- see header
    // comment for the derivation:
    //   quadrant 0 (x  1): (sr,  si )
    //   quadrant 1 (x +j): (-si, sr )
    //   quadrant 2 (x -1): (-sr, -si)
    //   quadrant 3 (x -j): (si, -sr )
    // Sign bits use 0=+1,1=-1, so "negate" is just a bit flip (XOR 1).

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
