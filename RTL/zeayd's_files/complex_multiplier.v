// =========================================================================
// complex_multiplier.v
// Task 3, Module 3 -- CSK / DQCSK Complex Multiplier (Modulator)
//
// Purpose:
//   Combines one chirp_rom sample (rom_real + j*rom_imag) with one DQPSK
//   symbol -- represented here purely as two sign bits, per csk_generator's
//   sign_real_out / sign_imag_out -- to produce the final modulated
//   transmit sample:
//
//       (a + bj)(c + dj) = (ac - bd) + (ad + bc)j
//
//   where a = dqpsk real sign (+1/-1), b = dqpsk imag sign (+1/-1),
//         c = rom_real,               d = rom_imag.
//
//   Because a and b are always exactly +1 or -1 (never fractional), ac,
//   bd, ad and bc are each just a sign flip of c or d -- NOT a true
//   multiply. This module is therefore four conditional negations and
//   two adders. Zero multiplier hardware is used.
//
// Word length (derived, not assumed):
//   rom_real/rom_imag are ROM_WIDTH-bit signed (R = 5 in this project,
//   range -16..15, empirically bounded to +-15 in practice). The output
//   is a sum/difference of two such values, so the worst case magnitude
//   is 15 + 15 = 30. Representing +-30 in two's complement needs
//   OUT_WIDTH = ROM_WIDTH + 1 = 6 bits (range -32..31, comfortably
//   covers +-30) -- 5 bits would only reach +-16, which is NOT enough.
//
// Timing:
//   Registered, one cycle of latency from (rom_real, rom_imag, sign_real,
//   sign_imag, valid_in) to (tx_real, tx_imag, valid_out). This is a
//   deliberate pipeline stage, not a side effect -- see the top-level
//   wrapper (css_symbol_generator.v) for why this lines up correctly
//   with chirp_rom's own one-cycle read latency.
//
// Assumptions:
//   - sign_real/sign_imag encode +1 as 0 and -1 as 1, matching
//     csk_generator's sign_real_out/sign_imag_out convention exactly.
//   - valid_in is already correctly aligned with rom_real/rom_imag by
//     the caller (i.e. it is NOT simply csk_generator's sample_valid --
//     see the top-level wrapper). This module does no alignment of its
//     own; it only registers and passes valid_in through as valid_out.
//   - reset is synchronous, active-high, matching csk_generator's style.
// =========================================================================

module complex_multiplier #(
    parameter ROM_WIDTH = 5,   // matches chirp_rom's rom_real/rom_imag width (R)
    parameter OUT_WIDTH = 6    // ROM_WIDTH + 1 -- see word-length derivation above
) (
    input  wire                        clk,
    input  wire                        reset,      // synchronous, active-high

    input  wire signed [ROM_WIDTH-1:0] rom_real,   // c, from chirp_rom
    input  wire signed [ROM_WIDTH-1:0] rom_imag,   // d, from chirp_rom
    input  wire                        sign_real,  // a: 0 = +1, 1 = -1 (DQPSK real sign)
    input  wire                        sign_imag,  // b: 0 = +1, 1 = -1 (DQPSK imag sign)
    input  wire                        valid_in,   // rom_real/rom_imag/signs are aligned and valid this cycle

    output reg  signed [OUT_WIDTH-1:0] tx_real,    // (ac - bd)
    output reg  signed [OUT_WIDTH-1:0] tx_imag,    // (ad + bc)
    output reg                         valid_out
);

    // Sign-extend the ROM samples to the output width BEFORE the
    // conditional negate, so the negation itself can never overflow
    // (negating the most-negative ROM_WIDTH-bit value would overflow at
    // ROM_WIDTH bits, but not once extended to OUT_WIDTH bits).
    wire signed [OUT_WIDTH-1:0] c_ext = {{(OUT_WIDTH-ROM_WIDTH){rom_real[ROM_WIDTH-1]}}, rom_real};
    wire signed [OUT_WIDTH-1:0] d_ext = {{(OUT_WIDTH-ROM_WIDTH){rom_imag[ROM_WIDTH-1]}}, rom_imag};

    // Four conditional negations, no actual multiplier hardware.
    wire signed [OUT_WIDTH-1:0] ac = sign_real ? -c_ext : c_ext;
    wire signed [OUT_WIDTH-1:0] bd = sign_imag ? -d_ext : d_ext;
    wire signed [OUT_WIDTH-1:0] ad = sign_real ? -d_ext : d_ext;
    wire signed [OUT_WIDTH-1:0] bc = sign_imag ? -c_ext : c_ext;

    always @(posedge clk) begin
        if (reset) begin
            tx_real   <= {OUT_WIDTH{1'b0}};
            tx_imag   <= {OUT_WIDTH{1'b0}};
            valid_out <= 1'b0;
        end else begin
            tx_real   <= ac - bd;
            tx_imag   <= ad + bc;
            valid_out <= valid_in;
        end
    end

endmodule
