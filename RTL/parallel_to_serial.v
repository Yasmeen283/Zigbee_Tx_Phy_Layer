//=============================================================================
// parallel_to_serial.v
//
// Dual of serial_to_parallel.v: takes one M-bit codeword (M = 4 for
// 1Mbps, M = 32 for 250kbps -- output width of interleaver_stage) and
// shifts it out one chip per clock, MSB first (matching the bit ordering
// symbol_mapper/interleaver already use). This is the core of "Form PPDU":
// instantiate one per I/Q path, feed its bit_out into qpsk_mapper's
// i_bit/q_bit (muxed with the preamble/SFD ROM bit while in_preamble is
// asserted), and pulse `load` whenever interleaver_stage's data_valid
// fires for a new codeword.
//=============================================================================
`timescale 1ns/1ps

module parallel_to_serial #(
    parameter integer M = 4                 // codeword width: 4 (1Mbps) or 32 (250kbps)
)(
    input  wire          clk,
    input  wire          reset,

    input  wire          load,              // pulse: capture data_in this cycle (must coincide with data_in_valid)
    input  wire [M-1:0]  data_in,
    input  wire          data_in_valid,

    output reg            bit_out,          // one chip per cycle while busy
    output reg            bit_valid,        // high while a captured codeword is being shifted out
    output reg            done              // 1-cycle pulse on the last chip of this codeword
);

    reg [M-1:0]       shift_reg;
    reg [$clog2(M+1)-1:0] cnt;              // counts remaining chips after the first
    reg               busy;

    always @(posedge clk) begin
        if (reset) begin
            shift_reg <= {M{1'b0}};
            cnt       <= '0;
            busy      <= 1'b0;
            bit_out   <= 1'b0;
            bit_valid <= 1'b0;
            done      <= 1'b0;
        end else begin
            done <= 1'b0;

            if (load && data_in_valid) begin
                // First chip is available immediately (MSB), remaining M-1
                // chips shift out over the next M-1 cycles.
                shift_reg <= data_in;
                cnt       <= M[$clog2(M+1)-1:0] - 1'b1;
                busy      <= 1'b1;
                bit_out   <= data_in[M-1];
                bit_valid <= 1'b1;
            end else if (busy) begin
                if (cnt == 0) begin
                    busy      <= 1'b0;
                    bit_valid <= 1'b0;
                    done      <= 1'b1;
                end else begin
                    shift_reg <= shift_reg << 1;
                    cnt       <= cnt - 1'b1;
                    bit_out   <= shift_reg[M-2];
                    bit_valid <= 1'b1;
                end
            end else begin
                bit_valid <= 1'b0;
            end
        end
    end

endmodule
