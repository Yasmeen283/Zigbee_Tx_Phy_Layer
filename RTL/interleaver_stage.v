//=============================================================================
// interleaver_stage.v
//
// Reconciles the Bit Interleaver (interleaver.v, 250 kbps only) with the
// dual data-rate requirement, using the SAME pattern already used for
// symbol_mapper's N_IN/M_OUT/MEMFILE: an elaboration-time parameter picked
// via `generate`, not a runtime mux.
//
// External interface is identical for both rates:
//   codeword_in [M_OUT-1:0] / codeword_valid   <- from symbol_mapper
//   data_out    [M_OUT-1:0] / data_valid       -> to Form PPDU / serializer
//
// DATA_RATE = 0 (1 Mbps, M_OUT = 4):
//   The interleaver plays no part at this rate. Codewords are registered
//   straight through (the 1-cycle delay just keeps the pipeline shape
//   consistent with the 250k branch below; nothing downstream depends on
//   cycle-exact latency matching between rates, since only one rate is
//   ever elaborated into a given instance of the design).
//
// DATA_RATE = 1 (250 kbps, M_OUT = 32):
//   The interleaver permutes 64 bits = 2 consecutive 32-bit codewords at
//   once. This stage buffers codeword N, and when codeword N+1 arrives it
//   concatenates {cw_N, cw_N+1} into the 64-bit interleaver input, then
//   streams the two 32-bit permuted halves back out one per cycle -- so
//   from the outside it still looks like "one M_OUT-bit codeword in ->
//   one M_OUT-bit codeword out", exactly like the bypass branch.
//=============================================================================
`timescale 1ns/1ps

module interleaver_stage #(
    parameter integer M_OUT     = 4,     // must match the symbol_mapper instance feeding this: 4 (1Mbps) or 32 (250kbps)
    parameter         DATA_RATE = 1'b0   // 0 = 1Mbps (interleaver elaborated out entirely), 1 = 250kbps (interleaver active)
)(
    input  wire               clk,
    input  wire               reset,

    input  wire [M_OUT-1:0]   codeword_in,
    input  wire               codeword_valid,   // from symbol_mapper

    output reg  [M_OUT-1:0]   data_out,
    output reg                data_valid        // to Form PPDU / parallel_to_serial
);

generate
if (DATA_RATE == 1'b0) begin : g_1mbps_bypass

    always @(posedge clk) begin
        if (reset) begin
            data_out   <= {M_OUT{1'b0}};
            data_valid <= 1'b0;
        end else begin
            data_out   <= codeword_in;
            data_valid <= codeword_valid;
        end
    end

end else begin : g_250k_interleave

    reg              have_first;
    reg [M_OUT-1:0]  cw0;
    reg              pending_second;
    reg [M_OUT-1:0]  second_half;

    wire [2*M_OUT-1:0] pair_in  = {cw0, codeword_in};   // {older codeword, newer codeword}
    wire [2*M_OUT-1:0] pair_out;
    wire               do_pair  = codeword_valid && have_first;

    interleaver u_interleaver (
        .data_in        (pair_in),
        .codeword_valid (do_pair),
        .data_out       (pair_out),
        .data_valid     ()            // combinational; gated explicitly by do_pair below instead
    );

    always @(posedge clk) begin
        if (reset) begin
            have_first     <= 1'b0;
            cw0            <= {M_OUT{1'b0}};
            pending_second <= 1'b0;
            data_valid     <= 1'b0;
        end else begin
            data_valid <= 1'b0;

            if (pending_second) begin
                // second half of the pair, already computed last cycle
                data_out       <= second_half;
                data_valid     <= 1'b1;
                pending_second <= 1'b0;
            end else if (codeword_valid) begin
                if (!have_first) begin
                    // first codeword of the pair: just buffer it, no output yet
                    cw0        <= codeword_in;
                    have_first <= 1'b1;
                end else begin
                    // second codeword just arrived: pair_in/pair_out are valid
                    // combinationally *this* cycle -- capture both halves now.
                    have_first     <= 1'b0;
                    data_out       <= pair_out[2*M_OUT-1 -: M_OUT];
                    second_half    <= pair_out[M_OUT-1:0];
                    data_valid     <= 1'b1;
                    pending_second <= 1'b1;
                end
            end
        end
    end

end
endgenerate

endmodule
