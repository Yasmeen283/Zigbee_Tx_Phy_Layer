// ============================================================================
// Module Name:   chirp_rom
// Description:   CSS Symbols ROM storing 4 pre-computed chirp sequences (m = 1..4)
//                using two separate ROM arrays (Real and Imaginary) sharing
//                a single 10-bit address bus.
//
// Precision:     R = 5 bits (Signed 2's Complement: -16 to +15)
// Word Size:     5 bits for rom_real, 5 bits for rom_imag
//
// Address Map:   10 bits total
//                [9:8] = chirp_index  (0 to 3  <-> m = 1 to 4)
//                [7:6] = subchirp_sel (0 to 3  <-> k = 0 to 3)
//                [5:0] = sample_addr  (0 to 37 valid; 38 to 63 unused)
// ============================================================================

module chirp_rom (
    input  wire       clk,          // System Clock
    input  wire [1:0] chirp_index,  // Selects Chirp Sequence (0..3)
    input  wire [1:0] subchirp_sel, // Selects Sub-Chirp k (0..3)
    input  wire [5:0] sample_addr,  // Sample counter within sub-chirp (0..37)
    output reg  [4:0] rom_real,     // 5-bit signed real part output
    output reg  [4:0] rom_imag      // 5-bit signed imaginary part output
);

    // ------------------------------------------------------------------------
    // Memory Array Definitions
    // Depth: 2^10 = 1024 locations (608 active locations used)
    // Width: 5 bits per component (R = 5)
    // ------------------------------------------------------------------------
    reg [4:0] rom_real_mem [0:1023];
    reg [4:0] rom_imag_mem [0:1023];

    // ------------------------------------------------------------------------
    // 10-Bit Address Concatenation
    // ------------------------------------------------------------------------
    wire [9:0] addr;
    assign addr = {chirp_index, subchirp_sel, sample_addr};

    // ------------------------------------------------------------------------
    // Initialize Memory Contents from External MATLAB Files
    // ------------------------------------------------------------------------
    initial begin
        // Replace with the relative or absolute path to your exported memory files
        $readmemb("chirp_rom_real.mem", rom_real_mem);
        $readmemb("chirp_rom_imag.mem", rom_imag_mem);
    end

    // ------------------------------------------------------------------------
    // Synchronous Registered Read Logic
    // Drives rom_real and rom_imag on the rising edge of clk
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        // Unused address behavior: Addresses 38..63 output 0 to keep outputs predictable
        if (sample_addr > 6'd37) begin
            rom_real <= 5'sd0;
            rom_imag <= 5'sd0;
        end else begin
            rom_real <= rom_real_mem[addr];
            rom_imag <= rom_imag_mem[addr];
        end
    end

endmodule