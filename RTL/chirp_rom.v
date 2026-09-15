//=============================================================================
// chirp_rom.v
//
// Block 7 (CSK Generator / chirp-sequence ROM) of the CSS PHY transmitter.
//
// Stores ONE complete chirp sequence (4 subchirps of Tsub=38 samples each =
// SAMPLES=152 samples total) for a chosen chirpIndex m, already reduced to
// TxDACbitNumber = 6-bit signed fixed point by the MATLAB floating-to-
// fixed-point model (Section 12 of the deep-dive doc). Address 0..151 walks
// straight through the 4 concatenated subchirps -- subchirp k occupies
// addresses [38*k : 38*k+37].
//
// The default MEMFILE (chirp_m1.mem) is an exact copy of the project's own
// chirpSequence.txt: 152 lines of 6-bit two's-complement real samples
// followed by 152 lines of 6-bit two's-complement imaginary samples, for
// chirpIndex = 1 (the project default, simulationParameters.m).
//
// Purely combinational read (matches "ROM, which save chirp sequences as
// constants" in the reference architecture) -- same rationale as
// symbol_mapper.v and preamble_sfd_rom.v.
//=============================================================================
`timescale 1ns/1ps

module chirp_rom #(
    parameter SAMPLES = 152,                   // 4 subchirps x Tsub(38) samples
    parameter MEMFILE  = "vectors/chirp_m1.mem"
) (
    input  wire [7:0]        addr,             // 0 .. SAMPLES-1
    output wire signed [5:0] chirp_real,
    output wire signed [5:0] chirp_imag
);

    reg signed [5:0] rom_real [0:SAMPLES-1];
    reg signed [5:0] rom_imag [0:SAMPLES-1];

    initial begin : load
        reg signed [5:0] flat [0:2*SAMPLES-1];
        integer i;
        $readmemb(MEMFILE, flat);
        for (i = 0; i < SAMPLES; i = i + 1) begin
            rom_real[i] = flat[i];
            rom_imag[i] = flat[SAMPLES + i];
        end
    end

    assign chirp_real = rom_real[addr];
    assign chirp_imag = rom_imag[addr];

endmodule
