//=============================================================================
// symbol_mapper.v
//
// Block 3 (Symbol Mapper) of the CSS PHY transmitter.
// Looks up an n-bit input group in the bi-orthogonal Walsh-Hadamard codeword
// table and outputs the corresponding m-bit codeword ("chips").
//
//   1 Mb/s  : n=3, m=4   ( 8 codewords, rate 3/4  block code)
//   250 kb/s: n=6, m=32  (64 codewords, rate 3/16 block code)
//
// The table itself is purely combinational (asynchronous ROM read) -- the
// codeword for a given n-bit address is available the same cycle. This
// mirrors "ROM, which save conversion tables" in the reference hardware
// architecture (Section 3.1 Architecture of the reference document).
//
// ROM contents are the exact tables handed over from MATLAB
// (codeword_1Mbs.txt / codeword_250kbs.txt), reformatted as one bit-string
// per line so $readmemb can load them directly (see vectors/*.mem).
//=============================================================================
`timescale 1ns/1ps

module symbol_mapper #(
    parameter DATA_RATE   = 1'b0,          // 0 = 1Mbps, 1 = 250kbps
    parameter N_IN        = 3,             // input group width  (3 or 6)
    parameter M_OUT       = 4,             // output codeword width (4 or 32)
    parameter NUM_WORDS   = (1 << N_IN),   // 8 or 64
    parameter MEMFILE     = "vectors/symbol_mapper_1mbps.mem"
) (
    input  wire [N_IN-1:0]       group_in,  // n-bit input group (binary index)
    output wire [M_OUT-1:0]      codeword_out
);

    // Combinational (asynchronous) ROM read. At 8x4 or 64x32 this table is
    // tiny and synthesizes as LUT logic; keeping it combinational removes
    // any pipeline-latency bookkeeping from the top-level controller (same
    // rationale as chirp_rom.v).
    reg [M_OUT-1:0] rom [0:NUM_WORDS-1];

    initial begin
        $readmemb(MEMFILE, rom);
    end

    assign codeword_out = rom[group_in];

endmodule
