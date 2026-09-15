//=============================================================================
// dqpsk_encoder.v
//
// Block 6 (Differential QPSK Coding) of the CSS PHY transmitter.
//
// Implements  S(n) = X(n) * S(n-4)  (Section 9 of the deep-dive doc), a
// complex multiply of the current QPSK symbol by the DQPSK symbol four
// positions earlier. Realized with a 4-deep circular memory of complex
// values (the "4 flip-flops" of the reference architecture) plus a complex
// multiplier.
//
// Initial condition: S(-4)..S(-1) = 1 + j1 (exp(j*pi/4) with the /sqrt(2)
// normalization deliberately skipped, matching the reference MATLAB code --
// only phase matters downstream, not magnitude).
//
// Key hardware simplification used here: since X(n) always has exactly one
// of {real,imag} equal to 0 and the other equal to +-1 (see qpsk_mapper.v),
// and the initial S components are +-1, every S(n) produced by this
// recursion *also* always has both components equal to +-1 (never 0) --
// the complex multiply is really just a sign flip / swap (a rotation by a
// multiple of 90 degrees). The multiply is left explicit below (X is tiny,
// so it's cheap either way) but S is therefore only ever +-1 per
// component, so 2-bit signed storage is exact and no growth/rounding logic
// is ever needed.
//=============================================================================
`timescale 1ns/1ps

module dqpsk_encoder (
    input  wire              clk,
    input  wire              reset,        // synchronous reset: reloads S(-4)..S(-1) = 1+j1
    input  wire              symbol_valid, // pulse: consume X(n) this cycle, S(n) appears next cycle
    input  wire signed [1:0] x_real,       // QPSK symbol from qpsk_mapper: in {-1,0,+1}
    input  wire signed [1:0] x_imag,
    output reg  signed [1:0] s_real,       // DQPSK output S(n): always -1 or +1
    output reg  signed [1:0] s_imag        // DQPSK output S(n): always -1 or +1
);

    // 4-deep circular memory holding S(n-4)..S(n-1)
    reg signed [1:0] mem_real [0:3];
    reg signed [1:0] mem_imag [0:3];
    reg [1:0]        wptr;   // points at the oldest entry, i.e. S(n-4)

    integer k;

    always @(posedge clk) begin
        if (reset) begin
            for (k = 0; k < 4; k = k + 1) begin
                mem_real[k] <= 2'sd1;
                mem_imag[k] <= 2'sd1;
            end
            wptr   <= 2'd0;
            s_real <= 2'sd1;
            s_imag <= 2'sd1;
        end else if (symbol_valid) begin : do_complex_mult
            // (Xr + jXi) * (Sr + jSi) ; Sr,Si = mem_{real,imag}[wptr] = S(n-4)
            reg signed [3:0] new_real, new_imag;
            new_real = x_real * mem_real[wptr] - x_imag * mem_imag[wptr];
            new_imag = x_real * mem_imag[wptr] + x_imag * mem_real[wptr];

            // Invariant (see header comment): new_real,new_imag are always
            // exactly +-1, so the low 2 bits are an exact signed result.
            s_real <= new_real[1:0];
            s_imag <= new_imag[1:0];

            mem_real[wptr] <= new_real[1:0];
            mem_imag[wptr] <= new_imag[1:0];
            wptr <= wptr + 2'd1;
        end
    end

endmodule
