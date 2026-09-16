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
    // reg [M_OUT-1:0] rom [0:NUM_WORDS-1];
    reg [M_OUT-1:0] rom ;

    generate
        if (DATA_RATE == 1'b0) begin : gen_rom_1mbps
            always @(*) begin
                    case (group_in)
                        3'd0: rom = 4'b1010;
                        3'd1: rom = 4'b1011;
                        3'd2: rom = 4'b1000;
                        3'd3: rom = 4'b1001;
                        3'd4: rom = 4'b1110;
                        3'd5: rom = 4'b1111;
                        3'd6: rom = 4'b1100;
                        3'd7: rom = 4'b1101;
                        default: rom = 4'b0000;
                    endcase
            end
        end
        else begin : gen_rom_250kbps
            always @(*) begin
                case (group_in)
                    6'd0: rom = 32'b00000000000000000000000000000000;
                    6'd1: rom = 32'b00000100000100000100000100000101;
                    6'd2: rom = 32'b00001000001000001000001000001010;
                    6'd3: rom = 32'b00001100001100001100001100001111;
                    6'd4: rom = 32'b00010000010000010000010000010000;
                    6'd5: rom = 32'b00010100010100010100010100010101;
                    6'd6: rom = 32'b00011000011000011000011000011010;
                    6'd7: rom = 32'b00011100011100011100011100011111;
                    6'd8: rom = 32'b00100000100000100000100000100000;
                    6'd9: rom = 32'b00100100100100100100100100100101;
                    6'd10: rom = 32'b00101000101000101000101000101010;
                    6'd11: rom = 32'b00101100101100101100101100101111;
                    6'd12: rom = 32'b00110000110000110000110000110000;
                    6'd13: rom = 32'b00110100110100110100110100110101;
                    6'd14: rom = 32'b00111000111000111000111000111010;
                    6'd15: rom = 32'b00111100111100111100111100111111;
                    6'd16: rom = 32'b01000001000001000001000001000000;
                    6'd17: rom = 32'b01000101000101000101000101000101;
                    6'd18: rom = 32'b01001001001001001001001001001010;
                    6'd19: rom = 32'b01001101001101001101001101001111;
                    6'd20: rom = 32'b01010001010001010001010001010000;
                    6'd21: rom = 32'b01010101010101010101010101010101;
                    6'd22: rom = 32'b01011001011001011001011001011010;
                    6'd23: rom = 32'b01011101011101011101011101011111;
                    6'd24: rom = 32'b01100001100001100001100001100000;
                    6'd25: rom = 32'b01100101100101100101100101100101;
                    6'd26: rom = 32'b01101001101001101001101001101010;
                    6'd27: rom = 32'b01101101101101101101101101101111;
                    6'd28: rom = 32'b01110001110001110001110001110000;
                    6'd29: rom = 32'b01110101110101110101110101110101;
                    6'd30: rom = 32'b01111001111001111001111001111010;
                    6'd31: rom = 32'b01111101111101111101111101111111;
                    6'd32: rom = 32'b10000010000010000010000010000000;
                    6'd33: rom = 32'b10000110000110000110000110000101;
                    6'd34: rom = 32'b10001010001010001010001010001010;
                    6'd35: rom = 32'b10001110001110001110001110001111;
                    6'd36: rom = 32'b10010010010010010010010010010000;
                    6'd37: rom = 32'b10010110010110010110010110010101;
                    6'd38: rom = 32'b10011010011010011010011010011010;
                    6'd39: rom = 32'b10011110011110011110011110011111;
                    6'd40: rom = 32'b10100010100010100010100010100000;
                    6'd41: rom = 32'b10100110100110100110100110100101;
                    6'd42: rom = 32'b10101010101010101010101010101010;
                    6'd43: rom = 32'b10101110101110101110101110101111;
                    6'd44: rom = 32'b10110010110010110010110010110000;
                    6'd45: rom = 32'b10110110110110110110110110110101;
                    6'd46: rom = 32'b10111010111010111010111010111010;
                    6'd47: rom = 32'b10111110111110111110111110111111;
                    6'd48: rom = 32'b11000011000011000011000011000000;
                    6'd49: rom = 32'b11000111000111000111000111000101;
                    6'd50: rom = 32'b11001011001011001011001011001010;
                    6'd51: rom = 32'b11001111001111001111001111001111;
                    6'd52: rom = 32'b11010011010011010011010011010000;
                    6'd53: rom = 32'b11010111010111010111010111010101;
                    6'd54: rom = 32'b11011011011011011011011011011010;
                    6'd55: rom = 32'b11011111011111011111011111011111;
                    6'd56: rom = 32'b11100011100011100011100011100000;
                    6'd57: rom = 32'b11100111100111100111100111100101;
                    6'd58: rom = 32'b11101011101011101011101011101010;
                    6'd59: rom = 32'b11101111101111101111101111101111;
                    6'd60: rom = 32'b11110011110011110011110011110000;
                    6'd61: rom = 32'b11110111110111110111110111110101;
                    6'd62: rom = 32'b11111011111011111011111011111010;
                    6'd63: rom = 32'b11111111111111111111111111111111;
                    default: rom = 32'b0;
                endcase
            end
        end
    endgenerate

    always @(posedge clk) begin
        if(group_valid) begin
            // codeword_out <= rom[group_in];
            codeword_out <= rom;
            codeword_valid <= 1'b1 ;
        end
        else begin
            codeword_valid <= 1'b0 ;
        end
    end


endmodule
