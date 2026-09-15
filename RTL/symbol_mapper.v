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
    parameter DATA_RATE   = 1'b0,           // 0 = 1Mbps, 1 = 250kbps
    parameter N_IN        = 3,              // input group width  (3 or 6)
    parameter M_OUT       = 4,             // output codeword width (4 or 32)
    parameter NUM_WORDS   = (1 << N_IN)   // 8 or 64
) (
    input                        clk ,
    input  wire [N_IN-1:0]       group_in,  // n-bit input group (binary index)
    input  wire                  group_valid , //input from serilizer                   
    output reg  [M_OUT-1:0]      codeword_out ,
    output reg                   codeword_valid // output to interleaver
);

    // Combinational (asynchronous) ROM read. At 8x4 or 64x32 this table is
    // tiny and synthesizes as LUT logic; keeping it combinational removes
    // any pipeline-latency bookkeeping from the top-level controller (same
    // rationale as chirp_rom.v).
    reg [M_OUT-1:0] rom [0:NUM_WORDS-1];

    generate
        if (DATA_RATE == 1'b0) begin : gen_rom_1mbps
            reg [3:0] rom [0:7];
            initial begin
                rom[0] = 4'b1010; 
                rom[1] = 4'b1011; 
                rom[2] = 4'b1000; 
                rom[3] = 4'b1001; 
                rom[4] = 4'b1110; 
                rom[5] = 4'b1111; 
                rom[6] = 4'b1100; 
                rom[7] = 4'b1101; 
            end
        end else begin : gen_rom_250kbps
            reg [31:0] rom [0:63];
            initial begin
                rom[ 0] = 32'b00000000000000000000000000000000; 
                rom[ 1] = 32'b00000100000100000100000100000101; 
                rom[ 2] = 32'b00001000001000001000001000001010; 
                rom[ 3] = 32'b00001100001100001100001100001111; 
                rom[ 4] = 32'b00010000010000010000010000010000; 
                rom[ 5] = 32'b00010100010100010100010100010101; 
                rom[ 6] = 32'b00011000011000011000011000011010; 
                rom[ 7] = 32'b00011100011100011100011100011111; 
                rom[ 8] = 32'b00100000100000100000100000100000; 
                rom[ 9] = 32'b00100100100100100100100100100101; 
                rom[10] = 32'b00101000101000101000101000101010; 
                rom[11] = 32'b00101100101100101100101100101111; 
                rom[12] = 32'b00110000110000110000110000110000; 
                rom[13] = 32'b00110100110100110100110100110101; 
                rom[14] = 32'b00111000111000111000111000111010; 
                rom[15] = 32'b00111100111100111100111100111111; 
                rom[16] = 32'b01000001000001000001000001000000; 
                rom[17] = 32'b01000101000101000101000101000101; 
                rom[18] = 32'b01001001001001001001001001001010; 
                rom[19] = 32'b01001101001101001101001101001111; 
                rom[20] = 32'b01010001010001010001010001010000; 
                rom[21] = 32'b01010101010101010101010101010101; 
                rom[22] = 32'b01011001011001011001011001011010; 
                rom[23] = 32'b01011101011101011101011101011111; 
                rom[24] = 32'b01100001100001100001100001100000; 
                rom[25] = 32'b01100101100101100101100101100101; 
                rom[26] = 32'b01101001101001101001101001101010; 
                rom[27] = 32'b01101101101101101101101101101111; 
                rom[28] = 32'b01110001110001110001110001110000; 
                rom[29] = 32'b01110101110101110101110101110101; 
                rom[30] = 32'b01111001111001111001111001111010; 
                rom[31] = 32'b01111101111101111101111101111111; 
                rom[32] = 32'b10000010000010000010000010000000; 
                rom[33] = 32'b10000110000110000110000110000101; 
                rom[34] = 32'b10001010001010001010001010001010; 
                rom[35] = 32'b10001110001110001110001110001111; 
                rom[36] = 32'b10010010010010010010010010010000; 
                rom[37] = 32'b10010110010110010110010110010101; 
                rom[38] = 32'b10011010011010011010011010011010; 
                rom[39] = 32'b10011110011110011110011110011111; 
                rom[40] = 32'b10100010100010100010100010100000; 
                rom[41] = 32'b10100110100110100110100110100101; 
                rom[42] = 32'b10101010101010101010101010101010; 
                rom[43] = 32'b10101110101110101110101110101111; 
                rom[44] = 32'b10110010110010110010110010110000; 
                rom[45] = 32'b10110110110110110110110110110101; 
                rom[46] = 32'b10111010111010111010111010111010; 
                rom[47] = 32'b10111110111110111110111110111111; 
                rom[48] = 32'b11000011000011000011000011000000; 
                rom[49] = 32'b11000111000111000111000111000101; 
                rom[50] = 32'b11001011001011001011001011001010; 
                rom[51] = 32'b11001111001111001111001111001111; 
                rom[52] = 32'b11010011010011010011010011010000; 
                rom[53] = 32'b11010111010111010111010111010101; 
                rom[54] = 32'b11011011011011011011011011011010; 
                rom[55] = 32'b11011111011111011111011111011111; 
                rom[56] = 32'b11100011100011100011100011100000; 
                rom[57] = 32'b11100111100111100111100111100101; 
                rom[58] = 32'b11101011101011101011101011101010; 
                rom[59] = 32'b11101111101111101111101111101111; 
                rom[60] = 32'b11110011110011110011110011110000; 
                rom[61] = 32'b11110111110111110111110111110101; 
                rom[62] = 32'b11111011111011111011111011111010; 
                rom[63] = 32'b11111111111111111111111111111111; 
            end
        end
    endgenerate

    always @(posedge clk) begin
        if(group_valid) begin
            codeword_out <= rom[group_in];
            codeword_valid <= 1'b1 ;
        end
        else begin
            codeword_valid <= 1'b0 ;
        end
    end


endmodule
