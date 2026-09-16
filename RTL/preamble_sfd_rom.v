`timescale 1ns/1ps

module preamble_sfd_rom #(
    parameter TOTAL_BITS = 48,                        // 48 for 1Mbps, 96 for 250kbps
    parameter [15:0] SFD = 16'h749C                  // 16'h749C for 1Mbps | 16'h7A23 for 250kbps
) (
    input  wire [7:0] addr,                           // 0 to TOTAL_BITS-1
    output wire       bit_out
);

    localparam PREAMBLE_LEN = TOTAL_BITS - 16;

    // Concatenate preamble (all 1s) and SFD into a single constant vector
    localparam [TOTAL_BITS-1:0] BITS = { {PREAMBLE_LEN{1'b1}}, SFD };

    // Index from MSB to LSB based on input address
    assign bit_out = BITS[TOTAL_BITS - 1 - addr] ; //!

endmodule