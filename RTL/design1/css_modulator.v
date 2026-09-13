//=============================================================================
// css_modulator.v
//
// Block 8 (Chirp Modulation / DQCSK) of the CSS PHY transmitter.
//
// Combines the DQPSK symbol S(n) (Block 6, |Sr|=|Si|=1) with the chirp ROM
// sample (Block 7) via a complex multiply, per Section 11 of the deep-dive
// doc:  one group of 4 successive DQPSK symbols multiplies, subchirp for
// subchirp, the 4 subchirps of the one stored chirp sequence. The caller
// (top-level controller) is responsible for presenting the right one of
// the 4 buffered S(n) symbols alongside each chirp ROM address.
//
// Output width matches Table 3-1 of the reference document (Tx_real /
// Tx_imag = 8 bits signed): with |Sr|,|Si| = 1 and chirp samples bounded to
// 6-bit signed (-32..31), the product is comfortably within 8-bit signed
// range, so no saturation logic is required.
//=============================================================================
`timescale 1ns/1ps

module css_modulator (
    input  wire signed [1:0] s_real,      // DQPSK symbol component, always -1 or +1
    input  wire signed [1:0] s_imag,      // DQPSK symbol component, always -1 or +1
    input  wire signed [5:0] chirp_real,  // chirp ROM sample, 6-bit signed fixed point
    input  wire signed [5:0] chirp_imag,
    output wire signed [7:0] tx_real,     // modulated I sample
    output wire signed [7:0] tx_imag      // modulated Q sample
);

    // (Sr + jSi) * (Cr + jCi) = (Sr*Cr - Si*Ci) + j(Sr*Ci + Si*Cr)
    assign tx_real = (s_real * chirp_real) - (s_imag * chirp_imag);
    assign tx_imag = (s_real * chirp_imag) + (s_imag * chirp_real);

endmodule
