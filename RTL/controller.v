//=============================================================================
// controller.v
//
// Top-level Controller for the CSS PHY transmitter. Its job is purely
// to bridge three sub-systems that each run at a different natural rate
// and each own a different flow-control style:
//
//   A) css_tx_frontend      -- advances one PADDED-STREAM BIT per `enable`
//                              pulse. Free-running if enable is held high.
//   B) interleaver_ppdu_top -- produces one CHIP PER CYCLE once it has a
//                              codeword pair. Has no enable input, so it
//                              cannot be stalled mid-codeword; it can only
//                              be throttled by withholding codewords in
//                              its S_PAYLOAD_WAIT state.
//   C) tx_datapath_top      -- consumes one SYMBOL PER 38 CYCLES (one
//                              subchirp). By far the slowest stage.
//
// Two rate mismatches follow from this, and this module exists to solve
// both:
//
//   MISMATCH 1 (chips vs. symbols).
//   ppdu_former emits the entire preamble+SFD as a free-running burst of
//   PREAMBLE_TOTAL_BITS chips, one per cycle, with no way to pause it.
//   tx_datapath_top consumes those same chips one per 38 cycles. The
//   burst therefore has to be absorbed. This module contains a chip FIFO
//   sized to hold the whole preamble burst plus one payload codeword,
//   and serves tx_datapath_top's symbol_req out of that FIFO.
//
//   MISMATCH 2 (bits vs. codewords).
//   ppdu_former asks for a codeword pair via req_next_symbol, but the
//   frontend produces codewords only after 2*N_IN bit-advances plus
//   pipeline latency. Rather than counting those cycles exactly (which
//   would hard-code the frontend's internal latency into this module and
//   break if that pipeline ever changes), this module runs the frontend
//   ELASTICALLY: enable is asserted whenever the codeword buffer has
//   room, and de-asserted when it is full. Codewords are then handed to
//   ppdu_former on demand. This is latency-insensitive by construction.
//
// Payload flow is additionally throttled against the chip FIFO: a
// codeword pair is only released to ppdu_former when the FIFO has room
// for a whole codeword's worth of chips, which is what prevents the
// free-running p2s shift-out from overrunning the FIFO.
//
// ---------------------------------------------------------------------
// ASSUMPTIONS AND DESIGN DECISIONS
// ---------------------------------------------------------------------
//  1. I and Q codewords are NOT produced on the same cycle. demux_iq
//     routes even padded-stream bits to I and odd bits to Q, so the Q
//     path's serial_to_parallel always completes its group exactly one
//     cycle after the I path's. Confirmed by simulation:
//     i_codeword_valid asserts one cycle ahead of q_codeword_valid, every
//     time. This module therefore collects the two codewords
//     independently into holding registers and only pushes a PAIR into
//     the codeword buffer once both halves have arrived. Downstream,
//     ppdu_former requires i_codeword_valid and q_codeword_valid
//     together, which this pairing provides.
//
//  2. symbol count. num_symbols is computed combinationally as
//        PREAMBLE_TOTAL_BITS + (padded_total_bits / (2*N_IN)) * M
//     Verified against the reference document: 25-byte payload at 1 Mbps
//     gives 216/6 = 36 codeword pairs, 36*4 = 144 payload chips, plus 48
//     preamble chips = 192 symbols, which is exactly the figure the
//     reference derives. The division is by an elaboration-time constant.
//
//  3. num_symbols must be a multiple of 4 (csk_generator maps four DQPSK
//     symbols onto one chirp sequence). Preamble+SFD is 48 or 96, both
//     multiples of 4. The payload contributes (pairs * M) chips, and M is
//     4 or 32, so that term is always a multiple of 4 as well. The
//     constraint is therefore satisfied for every payload length by
//     construction, at both data rates.
//
//  4. start is a single-cycle pulse. It is forwarded to the frontend as
//     `load`, to ppdu_former as `start`, and to tx_datapath_top as
//     `start`, all on the same cycle, so all three begin the packet
//     together.
//
//  5. last_codeword is derived from the frontend's frame_done, latched
//     and presented alongside the final codeword pair handed to
//     ppdu_former, which is the contract ppdu_former documents.
//
//  6. Chip FIFO depth is a parameter defaulting to 256, comfortably above
//     the worst case (96 preamble chips at 250 kbps plus one 32-chip
//     codeword). It is 2 bits wide (one I chip, one Q chip), so this is
//     inexpensive. Overflow is not expected; an assertion-style overflow
//     flag is exposed for verification rather than silently wrapping.
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
//  7. KNOWN LIMITATION, 250 kbps only. At DATA_RATE=1 interleaver_stage
//     emits two codewords back-to-back for every two it consumes, while
//     ppdu_former captures only one per request. The codeword buffer in
//     this module sits UPSTREAM of interleaver_stage and therefore does
//     not absorb that burst. At 1 Mbps interleaver_stage is a plain
//     one-in/one-out register, so this does not arise and the design is
//     correct as it stands. Supporting 250 kbps requires moving the
//     buffer downstream of interleaver_stage; this is called out rather
//     than silently assumed to work.
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
//=============================================================================
`timescale 1ns/1ps

module controller #(
    parameter integer N_IN                = 3,    // 3 (1Mbps) / 6 (250kbps)
    parameter integer M                   = 4,    // 4 (1Mbps) / 32 (250kbps)
    parameter integer GROUP_SIZE          = 6,    // 6 (1Mbps) / 24 (250kbps)
    parameter integer PREAMBLE_TOTAL_BITS = 48,   // 48 (1Mbps) / 96 (250kbps)
    parameter integer NUM_SYMBOLS_WIDTH   = 12,
    parameter integer FIFO_DEPTH          = 256,
    parameter integer FIFO_AW             = 8     // $clog2(FIFO_DEPTH)
)(
    input  wire                          clk,
    input  wire                          reset,

    // ---- packet-level control ------------------------------------------
    input  wire                          start_tx,              // 1-cycle pulse: begin a PPDU
    input  wire [6:0]                    payload_length, // payload length in bytes
    output wire [NUM_SYMBOLS_WIDTH-1:0]  num_symbols,        // total symbols for this packet
    output reg [6:0]                     payload_length_reg,
    // ---- to / from css_tx_frontend --------------------------------------
    output wire                          fe_load,
    output wire                          fe_enable,
    input  wire [M-1:0]                  fe_i_codeword,
    input  wire                          fe_i_codeword_valid,
    input  wire [M-1:0]                  fe_q_codeword,
    input  wire                          fe_q_codeword_valid,
    input  wire                          fe_frame_done,
    input  wire [15:0]                   padded_total_bits,

    // ---- to / from interleaver_ppdu_top ---------------------------------
    output wire                          pf_start,
    output reg  [M-1:0]                  pf_i_codeword,
    output reg                           pf_i_codeword_valid,
    output reg  [M-1:0]                  pf_q_codeword,
    output reg                           pf_q_codeword_valid,
    output reg                           pf_last_codeword,
    input  wire                          pf_req_next_symbol,
    input  wire                          pf_i_bit,
    input  wire                          pf_q_bit,
    input  wire                          pf_chip_valid,

    // ---- to / from tx_datapath_top --------------------------------------
    output wire                          dp_start,
    input  wire                          dp_symbol_req,
    output reg                           dp_i_bit,
    output reg                           dp_q_bit,
    output reg                           dp_qpsk_valid,

    // ---- status ----------------------------------------------------------
    output reg                           fifo_overflow   // verification aid; should never assert
);

    // ------------------------------------------------------------------
    // Symbol-count arithmetic (Assumption 2). Mirrors zero_padding's own
    // padding computation so num_symbols is available immediately at
    // start, without waiting for the frontend to run.
    // ------------------------------------------------------------------

    //Raghad trial 1 fix
    /*wire [15:0] codeword_pairs  = padded_total_bits / (2*N_IN);
    wire [15:0] payload_chips   = codeword_pairs * M;
    wire [15:0] total_symbols   = PREAMBLE_TOTAL_BITS + payload_chips;

    assign num_symbols = total_symbols[NUM_SYMBOLS_WIDTH-1:0];*/

    // Computed directly from the RAW payload_length input (not
    // payload_length_reg / padded_total_bits from the frontend), so
    // num_symbols is valid on the SAME cycle as start_tx/dp_start.
    // Mirrors zero_padding.v's own padding arithmetic exactly.
    localparam integer PHR_BITS = 12;

    wire [15:0] total_bits_now        = PHR_BITS + ({9'd0, payload_length} << 3);
    wire [15:0] remainder_now         = total_bits_now % GROUP_SIZE;
    wire [15:0] pad_bits_now          = GROUP_SIZE - remainder_now;
    wire [15:0] padded_total_bits_now = total_bits_now + pad_bits_now;

    wire [15:0] codeword_pairs  = padded_total_bits_now / (2*N_IN);
    wire [15:0] payload_chips   = codeword_pairs * M;
    wire [15:0] total_symbols   = PREAMBLE_TOTAL_BITS + payload_chips;

    assign num_symbols = total_symbols[NUM_SYMBOLS_WIDTH-1:0];
    // ------------------------------------------------------------------
    // Start distribution (Assumption 4)
    // ------------------------------------------------------------------
    assign fe_load  = start_tx;
    assign pf_start = start_tx;
    assign dp_start = start_tx;


    // ==================================================================
    // Codeword buffer (MISMATCH 2). 4-deep, holds I+Q codeword pairs.
    // Frontend runs elastically against this buffer's fullness.
    // ==================================================================
    localparam integer CW_DEPTH = 4;

    reg [M-1:0] cw_i   [0:CW_DEPTH-1];
    reg [M-1:0] cw_q   [0:CW_DEPTH-1];
    reg         cw_last[0:CW_DEPTH-1];
    reg [2:0]   cw_wptr, cw_rptr, cw_count;

    wire cw_full  = (cw_count == CW_DEPTH);
    wire cw_empty = (cw_count == 3'd0);

    // Frontend advances only while there is room to accept what it makes,
    // and only while the packet is live and the frontend has not finished.
    reg fe_done_latched;
    assign fe_enable = !cw_full ;

    always @(posedge clk) begin
        if (reset)          fe_done_latched <= 1'b0;
        else if (start_tx)     fe_done_latched <= 1'b0;
        else if (fe_frame_done && fe_enable) fe_done_latched <= 1'b1;
    end

    // ==================================================================
    // Chip FIFO (MISMATCH 1). Absorbs ppdu_former's free-running chip
    // burst so tx_datapath_top can drain it at its own much slower rate.
    // ==================================================================
    reg [1:0]          chip_mem [0:FIFO_DEPTH-1];
    reg [FIFO_AW-1:0]  chip_wptr, chip_rptr;
    reg [FIFO_AW:0]    chip_count;

    wire chip_fifo_empty = (chip_count == 0);
    wire [FIFO_AW:0] chip_space = FIFO_DEPTH[FIFO_AW:0] - chip_count;

    // Release a codeword pair only when the FIFO can absorb the whole
    // codeword the p2s shifters will then emit back-to-back.
    wire chip_room_for_codeword = (chip_space > M);

    // ------------------------------------------------------------------
    // Codeword buffer write (from frontend) / read (to ppdu_former)
    //
    // ppdu_former's req_next_symbol is a 1-cycle pulse, but the codeword
    // it asks for may not be buffered yet, and the chip FIFO may not have
    // room for the burst that shifting it out will produce. The request
    // is therefore latched until it can actually be served.
    // ------------------------------------------------------------------
    reg  pf_req_pending;

    // I/Q pairing (Assumption 1): collect each path's codeword as it
    // arrives, push the pair only once both halves are present.
    reg [M-1:0] hold_i, hold_q;
    reg         have_i, have_q;
    reg         hold_last;

    wire i_avail = have_i || fe_i_codeword_valid;
    wire q_avail = have_q || fe_q_codeword_valid;

    wire [M-1:0] push_i = have_i ? hold_i : fe_i_codeword;
    wire [M-1:0] push_q = have_q ? hold_q : fe_q_codeword;
    wire         push_last = hold_last || fe_frame_done || fe_done_latched;

    wire cw_push = i_avail && q_avail && !cw_full;
    wire cw_pop  = pf_req_pending && !cw_empty && chip_room_for_codeword;

    always @(posedge clk) begin
        if (reset) begin
            have_i <= 1'b0; have_q <= 1'b0; hold_last <= 1'b0;
            hold_i <= {M{1'b0}}; hold_q <= {M{1'b0}};
            payload_length_reg <= 7'd0;
        end else if (start_tx) begin 
            have_i <= 1'b0; have_q <= 1'b0; hold_last <= 1'b0;
            hold_i <= {M{1'b0}}; hold_q <= {M{1'b0}};
            payload_length_reg <= payload_length;
        end else if (cw_push) begin
            have_i <= 1'b0; have_q <= 1'b0; hold_last <= 1'b0;
        end else begin
            if (fe_i_codeword_valid) begin hold_i <= fe_i_codeword; have_i <= 1'b1; end
            if (fe_q_codeword_valid) begin hold_q <= fe_q_codeword; have_q <= 1'b1; end
            if (fe_frame_done || fe_done_latched) hold_last <= 1'b1;
        end
    end

    always @(posedge clk) begin
        if (reset )         pf_req_pending <= 1'b0;
        else if (start_tx)  pf_req_pending <= 1'b0;
        else if (pf_req_next_symbol) pf_req_pending <= 1'b1;
        else if (cw_pop)             pf_req_pending <= 1'b0;
    end

    integer idx ;
    always @(posedge clk) begin
        if (reset) begin
            cw_wptr <= 3'd0;  cw_rptr <= 3'd0;  cw_count <= 3'd0;
            pf_i_codeword       <= {M{1'b0}};
            pf_q_codeword       <= {M{1'b0}};
            pf_i_codeword_valid <= 1'b0;
            pf_q_codeword_valid <= 1'b0;
            pf_last_codeword    <= 1'b0;
            for (idx = 0; idx < CW_DEPTH; idx = idx + 1) begin
                cw_i[idx]    <= {M{1'b0}};
                cw_q[idx]    <= {M{1'b0}};
                cw_last[idx] <= 1'b0;
            end
        end else if (start_tx) begin
            cw_wptr <= 3'd0;  cw_rptr <= 3'd0;  cw_count <= 3'd0;
            pf_i_codeword       <= {M{1'b0}};
            pf_q_codeword       <= {M{1'b0}};
            pf_i_codeword_valid <= 1'b0;
            pf_q_codeword_valid <= 1'b0;
            pf_last_codeword    <= 1'b0;
        end else begin
            pf_i_codeword_valid <= 1'b0;
            pf_q_codeword_valid <= 1'b0;

            if (cw_push) begin
                cw_i   [cw_wptr[1:0]] <= push_i;
                cw_q   [cw_wptr[1:0]] <= push_q;
                cw_last[cw_wptr[1:0]] <= push_last;
                cw_wptr <= cw_wptr + 3'd1;
            end

            if (cw_pop) begin
                pf_i_codeword       <= cw_i   [cw_rptr[1:0]];
                pf_q_codeword       <= cw_q   [cw_rptr[1:0]];
                pf_last_codeword    <= cw_last[cw_rptr[1:0]];
                pf_i_codeword_valid <= 1'b1;
                pf_q_codeword_valid <= 1'b1;
                cw_rptr <= cw_rptr + 3'd1;
            end

            case ({cw_push, cw_pop})
                2'b10:   cw_count <= cw_count + 3'd1;
                2'b01:   cw_count <= cw_count - 3'd1;
                default: cw_count <= cw_count;  // 00 and 11 leave it unchanged
            endcase
        end
    end

    // ------------------------------------------------------------------
    // Chip FIFO write (from ppdu_former) / read (to tx_datapath_top)
    // ------------------------------------------------------------------
    wire chip_push = pf_chip_valid;
    wire chip_pop  = dp_symbol_req && !chip_fifo_empty;

    always @(posedge clk) begin
        if (reset) begin
            chip_wptr     <= {FIFO_AW{1'b0}};
            chip_rptr     <= {FIFO_AW{1'b0}};
            chip_count    <= {(FIFO_AW+1){1'b0}};
            dp_i_bit      <= 1'b0;
            dp_q_bit      <= 1'b0;
            dp_qpsk_valid <= 1'b0;
            fifo_overflow <= 1'b0;
        end else if (start_tx) begin
            chip_wptr     <= {FIFO_AW{1'b0}};
            chip_rptr     <= {FIFO_AW{1'b0}};
            chip_count    <= {(FIFO_AW+1){1'b0}};
            dp_i_bit      <= 1'b0;
            dp_q_bit      <= 1'b0;
            dp_qpsk_valid <= 1'b0;
            fifo_overflow <= 1'b0;
        end else begin
            dp_qpsk_valid <= 1'b0;

            if (chip_push && (chip_count == FIFO_DEPTH))
                fifo_overflow <= 1'b1;   // sticky; verification aid only

            if (chip_push && !chip_pop) begin
                chip_mem[chip_wptr] <= {pf_i_bit, pf_q_bit};
                chip_wptr  <= chip_wptr + 1'b1;
                chip_count <= chip_count + 1'b1;
            end else if (!chip_push && chip_pop) begin
                {dp_i_bit, dp_q_bit} <= chip_mem[chip_rptr];
                dp_qpsk_valid <= 1'b1;
                chip_rptr  <= chip_rptr + 1'b1;
                chip_count <= chip_count - 1'b1;
            end else if (chip_push && chip_pop) begin
                chip_mem[chip_wptr] <= {pf_i_bit, pf_q_bit};
                chip_wptr <= chip_wptr + 1'b1;
                {dp_i_bit, dp_q_bit} <= chip_mem[chip_rptr];
                dp_qpsk_valid <= 1'b1;
                chip_rptr <= chip_rptr + 1'b1;
                // count unchanged
            end
        end
    end

endmodule