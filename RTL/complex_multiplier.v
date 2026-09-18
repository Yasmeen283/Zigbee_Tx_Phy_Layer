module complex_multiplier #(
    parameter ROM_WIDTH = 5,   
    parameter OUT_WIDTH = 6    // ROM_WIDTH + 1 
) (
    input  wire                        clk,
    input  wire                        reset,      
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
