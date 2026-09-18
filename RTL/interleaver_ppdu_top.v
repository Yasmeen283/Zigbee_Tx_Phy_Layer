`timescale 1ns/1ps

module interleaver_ppdu_top #(
    parameter integer M                   = 4,     // Codeword width: 4 (1Mbps) or 32 (250kbps)
    parameter         DATA_RATE           = 1'b0,  // 0 = 1Mbps (bypass), 1 = 250kbps (interleave)
    parameter integer PREAMBLE_TOTAL_BITS = 48,    // Preamble+SFD bit count: 48 (1Mbps) or 96 (250kbps)
    parameter [15:0]  SFD                 = 16'h749C
)(
    input  wire          clk,
    input  wire          reset,
    input  wire          start,

    // Upstream Codeword Inputs (I and Q paths)
    input  wire [M-1:0]  i_codeword_in,
    input  wire          i_codeword_valid,
    input  wire [M-1:0]  q_codeword_in,
    input  wire          q_codeword_valid,
    input  wire          last_codeword,

    // Pipeline Handshake & Serial Output
    output wire          req_next_symbol,  // Handshake pulse to upstream controller
    output wire          i_bit,            // Serial output chip (I)
    output wire          q_bit,            // Serial output chip (Q)
    output wire          chip_valid       // Active during preamble and valid payload chips
);

    // Signals between interleaver stages and PPDU former
    wire [M-1:0] i_stage_out;
    wire         i_stage_valid;
    wire [M-1:0] q_stage_out;
    wire         q_stage_valid;


    // I-Channel Interleaver Stage

    interleaver_stage #(
        .M_OUT    (M),
        .DATA_RATE(DATA_RATE)
    ) u_interleaver_stage_i (
        .clk            (clk),
        .reset          (reset),
        .codeword_in    (i_codeword_in),
        .codeword_valid (i_codeword_valid),
        .data_out       (i_stage_out),
        .data_valid     (i_stage_valid)
    );


    // Q-Channel Interleaver Stage

    interleaver_stage #(
        .M_OUT    (M),
        .DATA_RATE(DATA_RATE)
    ) u_interleaver_stage_q (
        .clk            (clk),
        .reset          (reset),
        .codeword_in    (q_codeword_in),
        .codeword_valid (q_codeword_valid),
        .data_out       (q_stage_out),
        .data_valid     (q_stage_valid)
    );


    // PPDU Former (Preamble ROM + Parallel-to-Serial Muxing)

    ppdu_former #(
        .M                  (M),
        .PREAMBLE_TOTAL_BITS(PREAMBLE_TOTAL_BITS)
    ) u_ppdu_former (
        .clk              (clk),
        .reset            (reset),
        .start            (start),
        .i_codeword       (i_stage_out),
        .i_codeword_valid (i_stage_valid),
        .q_codeword       (q_stage_out),
        .q_codeword_valid (q_stage_valid),
        .last_codeword    (last_codeword),
        .req_next_symbol  (req_next_symbol),
        .i_bit            (i_bit),
        .q_bit            (q_bit),
        .chip_valid       (chip_valid)
    );

endmodule