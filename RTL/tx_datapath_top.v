
`timescale 1ns/1ps

module tx_datapath_top #(
    parameter NUM_SYMBOLS_WIDTH = 12,  // must match css_symbol_generator's parameter
    parameter ROM_WIDTH         = 5,
    parameter OUT_WIDTH         = 6
) (
    input  wire                          clk,
    input  wire                          reset,

    input  wire                          start,           // begin a new PPDU
    input  wire [1:0]                    chirp_index,     // CSK chirp sequence select (m=1-4)
    input  wire [NUM_SYMBOLS_WIDTH-1:0]  num_symbols,     // total symbols for the whole packet
                                                            // (preamble+SFD+payload), multiple of 4
    output wire                          tx_done,         // whole PPDU fully transmitted


    input  wire                          i_bit,           // 0 = +1, 1 = -1
    input  wire                          q_bit,           // 0 = +1, 1 = -1
    input  wire                          qpsk_valid,      // i_bit/q_bit valid this cycle
    output wire                          symbol_req,      // requests the next (i_bit, q_bit) pair


    output wire signed [OUT_WIDTH-1:0]   tx_real,
    output wire signed [OUT_WIDTH-1:0]   tx_imag,
    output wire                          tx_valid
);


    wire [1:0] qpsk_quadrant;

    qpsk_mapper u_qpsk_mapper (
        .i_bit         (i_bit),
        .q_bit         (q_bit),
        .qpsk_quadrant (qpsk_quadrant)
    );

    wire dqpsk_valid_w, dqpsk_sign_real_w, dqpsk_sign_imag_w;

    dqpsk_encoder u_dqpsk_encoder (
        .clk             (clk),
        .reset           (reset),
        .qpsk_valid      (qpsk_valid),
        .qpsk_quadrant   (qpsk_quadrant),
        .dqpsk_valid     (dqpsk_valid_w),
        .dqpsk_sign_real (dqpsk_sign_real_w),
        .dqpsk_sign_imag (dqpsk_sign_imag_w)
    );


    css_symbol_generator #(
        .NUM_SYMBOLS_WIDTH (NUM_SYMBOLS_WIDTH),
        .ROM_WIDTH         (ROM_WIDTH),
        .OUT_WIDTH         (OUT_WIDTH)
    ) u_css_symbol_generator (
        .clk             (clk),
        .reset           (reset),
        .start           (start),
        .chirp_index     (chirp_index),
        .num_symbols     (num_symbols),
        .dqpsk_valid     (dqpsk_valid_w),
        .dqpsk_sign_real (dqpsk_sign_real_w),
        .dqpsk_sign_imag (dqpsk_sign_imag_w),
        .next_symbol_req (symbol_req),
        .done            (tx_done),
        .tx_real         (tx_real),
        .tx_imag         (tx_imag),
        .tx_valid        (tx_valid)
    );

endmodule