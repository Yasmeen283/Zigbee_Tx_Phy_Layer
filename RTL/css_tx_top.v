//=============================================================================
// css_tx_top.v
//
// Project top level: complete IEEE 802.15.4 CSS PHY transmitter.
//
//   payload_ram
//        |  payload_rd_data / payload_rd_addr
//        v
//   css_tx_frontend   (zero_padding -> demux_iq -> serial_to_parallel x2
//                      -> symbol_mapper x2)
//        |  i_codeword / q_codeword (+ valids)
//        v
//   controller        (codeword buffer, elastic frontend pacing,
//                      chip FIFO, symbol-count arithmetic)
//        |  codeword pair on demand            ^ chips in
//        v                                      |
//   interleaver_ppdu_top  (interleaver_stage x2 -> ppdu_former, which owns
//                          preamble_sfd_rom + parallel_to_serial x2)
//        |  i_bit / q_bit / chip_valid ---------'
//        v
//   tx_datapath_top   (qpsk_mapper -> dqpsk_encoder -> css_symbol_generator,
//                      which contains chirp_rom + csk_generator +
//                      complex_multiplier)
//        |
//        v
//   tx_real / tx_imag / tx_valid
//
// The controller sits between the frontend and interleaver_ppdu_top in the
// codeword path, and between interleaver_ppdu_top and tx_datapath_top in
// the chip path. Both placements are deliberate: see controller.v's header
// for the two rate mismatches this arrangement resolves.
//
// Default parameterisation is 1 Mbps. For 250 kbps, set DATA_RATE=1,
// N_IN=6, M=32, GROUP_SIZE=24, PREAMBLE_TOTAL_BITS=96, SFD=16'h7A23, and
// point MEMFILE_I/Q at the 250 kbps symbol-mapper tables -- but note the
// 250 kbps limitation documented as Assumption 7 in controller.v before
// doing so.
//=============================================================================
`timescale 1ns/1ps

module css_tx_top #(
    parameter         DATA_RATE           = 1'b0,
    parameter integer N_IN                = 3,
    parameter integer M                   = 4,
    parameter integer GROUP_SIZE          = 6,
    parameter integer PREAMBLE_TOTAL_BITS = 48,
    parameter [15:0]  SFD                 = 16'h749C,
    parameter integer DATA_WIDTH          = 8,
    parameter integer ADDR_WIDTH          = 7,
    parameter integer NUM_SYMBOLS_WIDTH   = 12,
    parameter integer ROM_WIDTH           = 5,
    parameter integer OUT_WIDTH           = 6
)(
    input  wire                        clk,
    input  wire                        reset,

    // ---- payload load interface (MAC writes the PSDU before start) ------
    input  wire                        payload_we,
    input  wire [ADDR_WIDTH-1:0]       payload_waddr,
    input  wire [DATA_WIDTH-1:0]       payload_wdata,

    // ---- packet control --------------------------------------------------
    input  wire                        start_tx,               // 1-cycle pulse
    input  wire [6:0]                  payload_length,  // PSDU length in bytes
    input  wire [1:0]                  chirp_index,         // CSK sequence select (m=1-4 as 0-3)
    output wire                        tx_done,

    // ---- transmitted baseband output --------------------------------------
    output wire signed [OUT_WIDTH-1:0] tx_real,
    output wire signed [OUT_WIDTH-1:0] tx_imag,
    output wire                        tx_valid,

    // ---- status ------------------------------------------------------------
    output wire                        fifo_overflow
);

    // ------------------------------------------------------------------
    // Payload RAM
    // ------------------------------------------------------------------
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

    // ------------------------------------------------------------------
    // Frontend: padding, demux, serial-to-parallel, symbol mapping
    // ------------------------------------------------------------------
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

    // ------------------------------------------------------------------
    // Controller
    // ------------------------------------------------------------------
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

    // ------------------------------------------------------------------
    // Interleaver stages + PPDU former
    // ------------------------------------------------------------------
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

    // ------------------------------------------------------------------
    // Modulation datapath
    // ------------------------------------------------------------------
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
