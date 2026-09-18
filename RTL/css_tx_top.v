`timescale 1ns/1ps

module css_tx_top #(
    parameter         DATA_RATE           = 0, //0 --> 1M | 1--> 250 kbps
    parameter integer N_IN                = 3, //3 --> 1M | 6 --> 250 kbps
    parameter integer M                   = 4, //4 --> 1M | 32 --> 250 kbps
    parameter integer GROUP_SIZE          = 6, //6 --> 1M | 24 --> 250 kbps
    parameter integer PREAMBLE_TOTAL_BITS = 48, //48 --> 1M | 96 --> 250 kbps
    parameter [15:0]  SFD                 = 16'h749C, //16'h749C --> 1M | 16'h7A23 --> 250 kbps
    parameter integer DATA_WIDTH          = 8,
    parameter integer ADDR_WIDTH          = 7,
    parameter integer NUM_SYMBOLS_WIDTH   = 12,
    parameter integer ROM_WIDTH           = 5,
    parameter integer OUT_WIDTH           = 6
)(
    input  wire                        clk,
    input  wire                        reset,

    input  wire                        payload_we,
    input  wire [ADDR_WIDTH-1:0]       payload_waddr,
    input  wire [DATA_WIDTH-1:0]       payload_wdata,

    input  wire                        start_tx,               // 1-cycle pulse
    input  wire [6:0]                  payload_length,  // PSDU length in bytes
    input  wire [1:0]                  chirp_index,         // CSK sequence select (m=1-4 as 0-3)
    output wire                        tx_done,

    output wire signed [OUT_WIDTH-1:0] tx_real,
    output wire signed [OUT_WIDTH-1:0] tx_imag,
    output wire                        tx_valid,

    output wire                        fifo_overflow
);


    wire [ADDR_WIDTH-1:0] payload_rd_addr;
    wire [DATA_WIDTH-1:0] payload_rd_data;
    wire [6:0] payload_length_reg ;

    payload_ram #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_payload_ram (
        .clk   (clk),
        .we    (payload_we),
        .waddr (payload_waddr),
        .din   (payload_wdata),
        .raddr (payload_rd_addr),
        .dout  (payload_rd_data)
    );


    wire               fe_load, fe_enable, fe_frame_done;
    wire [M-1:0]       fe_i_codeword, fe_q_codeword;
    wire               fe_i_codeword_valid, fe_q_codeword_valid;
    wire [15:0]        padded_total_bits;
    css_tx_frontend #(
        .GROUP_SIZE (GROUP_SIZE),
        .N_IN       (N_IN),
        .M_OUT      (M),
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_RATE  (DATA_RATE)
    ) u_frontend (
        .clk                (clk),
        .reset              (reset),
        .load               (fe_load),
        .enable             (fe_enable),
        .payload_length_reg (payload_length_reg),
        .payload_rd_data    (payload_rd_data),
        .payload_rd_addr    (payload_rd_addr),
        .frame_done         (fe_frame_done),
        .i_codeword         (fe_i_codeword),
        .i_codeword_valid   (fe_i_codeword_valid),
        .q_codeword         (fe_q_codeword),
        .q_codeword_valid   (fe_q_codeword_valid),
        .padded_total_bits  (padded_total_bits)
    );

    wire                         pf_start, pf_last_codeword;
    wire [M-1:0]                 pf_i_codeword, pf_q_codeword;
    wire                         pf_i_codeword_valid, pf_q_codeword_valid;
    wire                         pf_req_next_symbol, pf_chip_valid;
    wire                         pf_i_bit, pf_q_bit;
    wire                         dp_start, dp_symbol_req, dp_qpsk_valid;
    wire                         dp_i_bit, dp_q_bit;
    wire [NUM_SYMBOLS_WIDTH-1:0] num_symbols;

    controller #(
        .N_IN                (N_IN),
        .M                   (M),
        .GROUP_SIZE          (GROUP_SIZE),
        .PREAMBLE_TOTAL_BITS (PREAMBLE_TOTAL_BITS),
        .NUM_SYMBOLS_WIDTH   (NUM_SYMBOLS_WIDTH)
    ) u_controller (
        .clk                 (clk),
        .reset               (reset),
        .start_tx            (start_tx),
        .payload_length      (payload_length),
        .payload_length_reg  (payload_length_reg),
        .num_symbols         (num_symbols),

        .fe_load             (fe_load),
        .fe_enable           (fe_enable),
        .fe_i_codeword       (fe_i_codeword),
        .fe_i_codeword_valid (fe_i_codeword_valid),
        .fe_q_codeword       (fe_q_codeword),
        .fe_q_codeword_valid (fe_q_codeword_valid),
        .fe_frame_done       (fe_frame_done),

        .pf_start            (pf_start),
        .pf_i_codeword       (pf_i_codeword),
        .pf_i_codeword_valid (pf_i_codeword_valid),
        .pf_q_codeword       (pf_q_codeword),
        .pf_q_codeword_valid (pf_q_codeword_valid),
        .pf_last_codeword    (pf_last_codeword),
        .pf_req_next_symbol  (pf_req_next_symbol),
        .pf_i_bit            (pf_i_bit),
        .pf_q_bit            (pf_q_bit),
        .pf_chip_valid       (pf_chip_valid),

        .dp_start            (dp_start),
        .dp_symbol_req       (dp_symbol_req),
        .dp_i_bit            (dp_i_bit),
        .dp_q_bit            (dp_q_bit),
        .dp_qpsk_valid       (dp_qpsk_valid),
        .padded_total_bits   (padded_total_bits),
        .fifo_overflow       (fifo_overflow)
    );


    interleaver_ppdu_top #(
        .M                   (M),
        .DATA_RATE           (DATA_RATE),
        .PREAMBLE_TOTAL_BITS (PREAMBLE_TOTAL_BITS),
        .SFD                 (SFD)
    ) u_interleaver_ppdu (
        .clk              (clk),
        .reset            (reset),
        .start            (pf_start),
        .i_codeword_in    (pf_i_codeword),
        .i_codeword_valid (pf_i_codeword_valid),
        .q_codeword_in    (pf_q_codeword),
        .q_codeword_valid (pf_q_codeword_valid),
        .last_codeword    (pf_last_codeword),
        .req_next_symbol  (pf_req_next_symbol),
        .i_bit            (pf_i_bit),
        .q_bit            (pf_q_bit),
        .chip_valid       (pf_chip_valid)
    );


    tx_datapath_top #(
        .NUM_SYMBOLS_WIDTH (NUM_SYMBOLS_WIDTH),
        .ROM_WIDTH         (ROM_WIDTH),
        .OUT_WIDTH         (OUT_WIDTH)
    ) u_tx_datapath (
        .clk         (clk),
        .reset       (reset),
        .start       (dp_start),
        .chirp_index (chirp_index),
        .num_symbols (num_symbols),
        .tx_done     (tx_done),
        .i_bit       (dp_i_bit),
        .q_bit       (dp_q_bit),
        .qpsk_valid  (dp_qpsk_valid),
        .symbol_req  (dp_symbol_req),
        .tx_real     (tx_real),
        .tx_imag     (tx_imag),
        .tx_valid    (tx_valid)
    );

endmodule