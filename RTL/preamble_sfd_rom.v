//=============================================================================
// preamble_sfd_rom.v
//
// Synchronization header generator. Stores the fixed Preamble+SFD bit
// pattern (Section 2.1 of the deep-dive doc) and serves it out one bit per
// address, MSB-first, for a chosen data rate.
//
//   1 Mbps  : 32 preamble ('1') + 16 SFD bits  = 48 bits total
//   250 kbps: 80 preamble ('1') + 16 SFD bits  = 96 bits total
//
// '1' = bipolar +1, '0' = bipolar -1 -- same chip convention used
// everywhere else in this design (matches how preambleSFD.txt was
// exported from the MATLAB model).
//=============================================================================
`timescale 1ns/1ps

module preamble_sfd_rom #(
    parameter TOTAL_BITS = 48,     // 48 for 1Mbps, 96 for 250kbps
    parameter MEMFILE    = "vectors/preamble_sfd_1mbps.mem"
    // MEMFILE layout: line 0 = preamble bits (as one long binary string),
    // line 1 = SFD bits (as one long binary string). Concatenated logically
    // into a single TOTAL_BITS-wide constant at elaboration time.
) (
    input  wire [7:0] addr,   // 0 .. TOTAL_BITS-1
    output wire        bit_out
);

    reg [TOTAL_BITS-1:0] bits; // bits[TOTAL_BITS-1] = first bit transmitted

    initial begin : load
        reg [1023:0] preamble_line, sfd_line;
        integer fd, code;
        fd = $fopen(MEMFILE, "r");
        code = $fscanf(fd, "%b\n%b\n", preamble_line, sfd_line);
        $fclose(fd);
        // Reconstruct the fixed-width vector from the two variable-width
        // lines read as arbitrary-width binary literals.
        bits = {preamble_line[TOTAL_BITS-17:0], sfd_line[15:0]};
    end

    assign bit_out = bits[TOTAL_BITS-1-addr];

endmodule
