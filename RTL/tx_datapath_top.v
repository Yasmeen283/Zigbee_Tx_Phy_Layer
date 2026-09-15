//=============================================================================
// tx_datapath_top.v
//
// Symbol-modulation datapath wrapper: qpsk_mapper + dqpsk_encoder +
// css_symbol_generator (chirp_rom + csk_generator + complex_multiplier).
// css_symbol_generator itself is reused unchanged.
//
// The top-level Controller (Preamble -> SFD -> Payload -> Done sequencing,
// and the associated Preamble/SFD ROM and payload I/Q addressing) is
// intentionally NOT part of this module. It is a separate unit, and its
// output -- one (I,Q) bit pair per requested symbol -- is this module's
// direct input. This keeps the modulation datapath independent of how the
// Controller is implemented.
//
// Request/valid flow:
//   css_symbol_generator.next_symbol_req
//     -> symbol_req (this module's output) -> the Controller
//   the Controller, in response, drives i_bit / q_bit / qpsk_valid
//     -> qpsk_mapper                       (combinational, same cycle)
//   qpsk_mapper.qpsk_quadrant + qpsk_valid
//     -> dqpsk_encoder                     (registered, 1 cycle later:
//                                           dqpsk_valid pulses with the
//                                           new sign pair)
//   dqpsk_encoder.{dqpsk_valid,dqpsk_sign_real,dqpsk_sign_imag}
//     -> css_symbol_generator's dqpsk_valid / dqpsk_sign_real / imag inputs
//
// num_symbols is the total symbol count for the whole packet (preamble +
// SFD + payload combined) and is supplied by the Controller. It must be an
// exact multiple of 4 -- css_symbol_generator's own requirement, since
// four DQPSK symbols map onto one chirp sequence.
//=============================================================================
`timescale 1ns/1ps

module tx_datapath_top #(
    parameter NUM_SYMBOLS_WIDTH = 12,  // must match css_symbol_generator's parameter
    parameter ROM_WIDTH         = 5,
    parameter OUT_WIDTH         = 6
) (
    input  wire                          clk,
    input  wire                          reset,

    // ---- packet-level control ----------------------------------------------
    input  wire                          start,           // begin a new PPDU
    input  wire [1:0]                    chirp_index,     // CSK chirp sequence select (m=1-4)
    input  wire [NUM_SYMBOLS_WIDTH-1:0]  num_symbols,     // total symbols for the whole packet
                                                            // (preamble+SFD+payload), multiple of 4
    output wire                          tx_done,         // whole PPDU fully transmitted

    // ---- symbol source (driven by the Controller) --------------------------
    input  wire                          i_bit,           // 0 = +1, 1 = -1
    input  wire                          q_bit,           // 0 = +1, 1 = -1
    input  wire                          qpsk_valid,      // i_bit/q_bit valid this cycle
    output wire                          symbol_req,      // requests the next (i_bit, q_bit) pair

    // ---- final transmitted output ------------------------------------------
    output wire signed [OUT_WIDTH-1:0]   tx_real,
    output wire signed [OUT_WIDTH-1:0]   tx_imag,
    output wire                          tx_valid
);

    // ------------------------------------------------------------------
    // qpsk_mapper -> dqpsk_encoder
    // ------------------------------------------------------------------
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

    // ------------------------------------------------------------------
    // css_symbol_generator -- reused exactly as already built and
    // verified; no modifications made here.
    // ------------------------------------------------------------------
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