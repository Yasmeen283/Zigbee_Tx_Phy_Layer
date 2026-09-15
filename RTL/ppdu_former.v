//=============================================================================
// ppdu_former.v
//
// Block: "Form PPDU". Sequencing rule: walk the Preamble+SFD ROM first
// (same bit fed to both I and Q, bipolar convention), then switch to the
// I/Q codeword streams coming out of interleaver_stage (which are already
// either the real interleaved 250kbps data, or the straight-through
// 1Mbps codewords -- this module doesn't need to know which).
//
// Handshake with the upstream pipeline (zero_padding -> demux -> s2p ->
// symbol_mapper -> interleaver_stage): this module has no visibility into
// when the *next* I/Q codeword pair will be ready, so it asks for one via
// req_next_symbol and waits in S_PAYLOAD_WAIT until both i_codeword_valid
// and q_codeword_valid arrive (they are expected together, since the I/Q
// paths are driven in lockstep off the same bit_index). The Controller is
// responsible for pulsing `enable` on the upstream chain enough times to
// produce that next pair.
//
// last_codeword: driven by the Controller (forwarded from zero_padding's
// frame_done) high alongside the FINAL i/q_codeword_valid pulse, so this
// module knows to go to S_DONE instead of asking for another pair once
// the current M chips have finished shifting out.
//=============================================================================
`timescale 1ns/1ps

module ppdu_former #(
    parameter integer M                    = 4,   // codeword width post interleaver_stage: 4 (1Mbps) / 32 (250kbps)
    parameter integer PREAMBLE_TOTAL_BITS  = 48,   // 48 (1Mbps) / 96 (250kbps)
    parameter         PREAMBLE_MEMFILE     = "../vectors/preamble_sfd_1mbps.mem"
)(
    input  wire          clk,
    input  wire          reset,
    input  wire          start,             // pulse: begin a new PPDU (go read the preamble first)

    // interleaved/bypassed codeword streams from interleaver_stage
    input  wire [M-1:0]  i_codeword,
    input  wire          i_codeword_valid,
    input  wire [M-1:0]  q_codeword,
    input  wire          q_codeword_valid,
    input  wire          last_codeword,     // Controller asserts this alongside the final valid pulse

    output reg            req_next_symbol,  // pulse: ask Controller to advance the pipeline for the next codeword pair

    output wire           i_bit,
    output wire           q_bit,
    output wire           chip_valid,       // 1 while i_bit/q_bit carry a real chip this cycle
    output reg            frame_done       // 1-cycle pulse once the last payload chip has gone out
);

    // ---------------------------------------------------------------
    // Preamble + SFD ROM
    // ---------------------------------------------------------------
    reg  [7:0] preamble_addr;
    wire       preamble_bit;

    preamble_sfd_rom #(
        .TOTAL_BITS (PREAMBLE_TOTAL_BITS)
    ) u_preamble_sfd (
        .addr    (preamble_addr),
        .bit_out (preamble_bit)
    );

    // ---------------------------------------------------------------
    // Payload chip shifters (dual of serial_to_parallel, one per path)
    // ---------------------------------------------------------------
    wire payload_load ;

    wire i_payload_bit, q_payload_bit;
    wire i_payload_valid, q_payload_valid;
    wire i_done, q_done;

    parallel_to_serial #(.M(M)) u_p2s_i (
        .clk           (clk),
        .reset         (reset),
        .load          (payload_load),
        .data_in       (i_codeword),
        .data_in_valid (i_codeword_valid),
        .bit_out       (i_payload_bit),
        .bit_valid     (i_payload_valid),
        .done          (i_done)
    );

    parallel_to_serial #(.M(M)) u_p2s_q (
        .clk           (clk),
        .reset         (reset),
        .load          (payload_load),
        .data_in       (q_codeword),
        .data_in_valid (q_codeword_valid),
        .bit_out       (q_payload_bit),
        .bit_valid     (q_payload_valid),
        .done          (q_done)
    );

    // ---------------------------------------------------------------
    // Sequencer: PREAMBLE first, then PAYLOAD
    // ---------------------------------------------------------------
    localparam [1:0]  S_IDLE         = 2'd0,
                      S_PREAMBLE     = 2'd1,
                      S_PAYLOAD_WAIT = 2'd2,
                      S_PAYLOAD_SHIFT= 2'd3;

    reg [1:0] state;
    reg       pending_last;   // latches last_codeword for the pair currently shifting

    assign payload_load = (state == S_PAYLOAD_WAIT) && i_codeword_valid && q_codeword_valid;

    always @(posedge clk) begin
        if (reset) begin
            state           <= S_IDLE;
            preamble_addr   <= 8'd0;
            req_next_symbol <= 1'b0;
            frame_done      <= 1'b0;
            pending_last    <= 1'b0;
        end else begin
            req_next_symbol <= 1'b0;
            frame_done      <= 1'b0;

            case (state)
                // ---------------------------------------------------
                S_IDLE: begin
                    if (start) begin
                        preamble_addr <= 8'd0;
                        state         <= S_PREAMBLE;
                    end
                end

                // ---------------------------------------------------
                // Rule: drain the preamble/SFD ROM first, one chip/cycle
                // on both I and Q, before touching any payload data.
                S_PREAMBLE: begin
                    if (preamble_addr == PREAMBLE_TOTAL_BITS - 1) begin
                        req_next_symbol <= 1'b1;      // ask for the first codeword pair
                        state           <= S_PAYLOAD_WAIT;
                    end else begin
                        preamble_addr <= preamble_addr + 8'd1;
                    end
                end

                // ---------------------------------------------------
                // Then start with the interleaved (or bypassed) data.
                S_PAYLOAD_WAIT: begin
                    if (i_codeword_valid && q_codeword_valid) begin
                        pending_last <= last_codeword;
                        state        <= S_PAYLOAD_SHIFT;
                    end
                end

                S_PAYLOAD_SHIFT: begin
                    if (i_done && q_done) begin
                        if (pending_last) begin
                            frame_done <= 1'b1;
                            state      <= S_IDLE;
                        end else begin
                            req_next_symbol <= 1'b1;
                            state           <= S_PAYLOAD_WAIT;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // ---------------------------------------------------------------
    // Output chip mux: preamble bit while in S_PREAMBLE, payload chip
    // (post interleave/bypass) once in the payload phase.
    // ---------------------------------------------------------------
    wire in_preamble = (state == S_PREAMBLE);

    assign i_bit      = in_preamble ? preamble_bit : i_payload_bit;
    assign q_bit       = in_preamble ? preamble_bit : q_payload_bit;
    assign chip_valid = in_preamble || (i_payload_valid && q_payload_valid);

endmodule
