// =========================================================================
// csk_generator.v  (v3 -- all bugs found via self-checking testbench,
// fixed and RE-VERIFIED: ALL TESTS PASSED, 0 errors)
// =========================================================================
// Task 3, Module 2 -- CSK Generator (sequencing / control block)
//
// Purpose:
//   Walks the chirp_rom address bus (subchirp_sel, sample_addr) in step
//   with the incoming DQPSK symbol stream, and inserts the correct
//   inter-chirp-sequence time gap. Does NOT touch the ROM or the
//   multiplier itself -- this module only produces the address sequence,
//   the latched sign bits for the multiplier, and the valid/gap timing.
//
// *** THREE CORRECTIONS vs. the first draft of this module ***
// All three were caught by writing and running csk_generator_tb.v, not
// by inspection -- each is described here with the evidence that found it.
//
//   1. Trailing gap was missing. The original version skipped the gap
//      after the LAST chirp sequence of a packet and went straight to
//      `done`. Length arithmetic against the already-validated MATLAB
//      reference proved this wrong:
//        152 samples/sequence x 48 sequences            = 7296
//        confirmed TxchirpSequences length (25B, 1 Mb/s) = 9216
//        difference                                       = 1920
//        1920 = 24*10 + 24*70 (24 even + 24 odd gaps, chirp_index=1)
//      which only balances if EVERY sequence, including the last, is
//      followed by a gap. Fixed: the gap now always runs after a
//      completed sequence; only whether it's followed by DONE or by the
//      next REQ_SYM depends on whether that was the final sequence.
//
//   2. sample_valid was registered, one cycle out of alignment with
//      sample_addr. sample_addr correctly reads 0 on the very first
//      S_STREAM cycle (set up by the preceding S_WAIT_SYM cycle), but a
//      REGISTERED sample_valid only caught up one cycle later -- by
//      which point sample_addr had already advanced to 1, so the true
//      addr=0 sample was never flagged valid. Confirmed via testbench
//      TEST 1 (address-walk check failed on every single sample, always
//      off by exactly one address). Fixed: sample_valid is now purely
//      COMBINATIONAL (`assign sample_valid = (state == S_STREAM);`), so
//      it is always aligned with whatever sample_addr/subchirp_sel
//      currently hold, by construction -- no lag is possible.
//
//   3. Off-by-one in the gap counter. Loading gap_counter with the raw
//      gap length (e.g. 10) and counting down to 0 INCLUSIVE spends 11
//      cycles (10,9,...,1,0), not 10 -- a classic fencepost error.
//      Confirmed via testbench TEST 2/3 (measured exactly one extra
//      cycle per gap: 82 vs 80 expected over 2 gaps, 1968 vs 1920 over
//      48). Fixed: the counter now loads (gap_length - 1), so counting
//      down to 0 takes exactly gap_length cycles.
//
// After all three fixes, csk_generator_tb.v passes cleanly: 5/5 test
// groups, 0 errors, including the exact 9216-sample regression check.
//
// Other design decisions made explicit here (spec left these open):
//   a. Gap parity: the gap following the 1st chirp sequence in a packet
//      uses gap_even, the 2nd uses gap_odd, alternating (matches the
//      standard's Figure 2-2 pattern). This is what makes the length
//      arithmetic in point 1 balance exactly for an even sequence count
//      (48) -- independent supporting evidence the parity assignment is
//      right, though still worth a direct eyeball check against
//      TxchirpSequences.
//   b. num_symbols is assumed to always be an exact multiple of 4 (the
//      upstream padding/coding-rate math guarantees this for any
//      well-formed packet). This is NOT re-checked in hardware; verify
//      it as a testbench assertion instead.
//   c. num_symbols == 0 (Task 4's payload-length-0 edge case): the FSM
//      skips straight from IDLE to DONE, requesting nothing, streaming
//      nothing, and inserting no gap (there is no sequence to trail).
//   d. During a gap, subchirp_sel/sample_addr hold their last streamed
//      values (don't-care downstream, since sample_valid is low) -- the
//      multiplier must gate its own output on valid_in, not trust the
//      ROM address during gap cycles.
//
// chirp_index mapping: hardware value 0-3 corresponds to the standard's
// m = 1-4 (i.e. chirp_index_reg + 1 = m). Kept consistent with chirp_rom.
// =========================================================================

module csk_generator #(
    parameter NUM_SYMBOLS_WIDTH = 12   // covers up to 4095 DQPSK symbols;
                                        // largest real packet (127-byte
                                        // payload, 250 kb/s) needs ~2880
) (
    input  wire                          clk,
    input  wire                          reset,          // synchronous, active-high

    input  wire                          start,          // begin generating for this packet
    input  wire [1:0]                    chirp_index,    // 0-3 <-> standard m=1-4, latched at start
    input  wire [NUM_SYMBOLS_WIDTH-1:0]  num_symbols,     // total DQPSK symbols in this packet, latched at start

    input  wire                          dqpsk_valid,     // new DQPSK symbol available
    input  wire                          dqpsk_sign_real, // 0 = +1, 1 = -1
    input  wire                          dqpsk_sign_imag, // 0 = +1, 1 = -1

    output reg  [1:0]                    subchirp_sel,    // drives chirp_rom address (k)
    output reg  [5:0]                    sample_addr,     // drives chirp_rom address (sample index, 0-37 valid)
    output reg                           sign_real_out,   // latched sign, passthrough to multiplier
    output reg                           sign_imag_out,
    output wire                          sample_valid,    // high while a real chirp sample is being addressed
    output reg                           next_symbol_req, // pulses to request the next DQPSK symbol
    output reg                           done             // packet modulation complete (1-cycle pulse)
);

    // ---------------------------------------------------------------
    // Gap length lookup, keyed by the latched chirp_index (0-3 <-> m=1-4)
    // Values from Table 2-2 of the standard / thesis document.
    // ---------------------------------------------------------------
    reg [6:0] gap_even; // max value 70 -> needs 7 bits
    reg [6:0] gap_odd;

    reg [1:0] chirp_index_reg;

    always @(*) begin
        case (chirp_index_reg)
            2'd0: begin gap_even = 7'd10; gap_odd = 7'd70; end // m=1
            2'd1: begin gap_even = 7'd20; gap_odd = 7'd60; end // m=2
            2'd2: begin gap_even = 7'd30; gap_odd = 7'd50; end // m=3
            2'd3: begin gap_even = 7'd40; gap_odd = 7'd40; end // m=4
        endcase
    end

    // ---------------------------------------------------------------
    // FSM state encoding
    // ---------------------------------------------------------------
    localparam S_IDLE     = 3'd0;
    localparam S_REQ_SYM  = 3'd1;  // assert next_symbol_req for one cycle
    localparam S_WAIT_SYM = 3'd2;  // wait for dqpsk_valid, then latch signs
    localparam S_STREAM   = 3'd3;  // walk sample_addr 0..37 for current subchirp
    localparam S_GAP      = 3'd4;  // count down the inter-sequence gap (always runs, even after the last sequence)
    localparam S_DONE     = 3'd5;  // one-cycle done pulse

    // sample_valid is deliberately combinational (not registered): it must
    // be high on the SAME cycle sample_addr/subchirp_sel first present a
    // valid address, with zero lag. A registered version introduced a
    // real bug (found via testbench): sample_addr reads correctly from
    // the very first S_STREAM cycle (set up by the preceding S_WAIT_SYM
    // cycle), but a registered sample_valid only caught up one cycle
    // later -- by which point sample_addr had already advanced past 0.
    reg [2:0] state;
    
    assign sample_valid = (state == S_STREAM);


    // ---------------------------------------------------------------
    // Internal counters / registers
    // ---------------------------------------------------------------
    reg [NUM_SYMBOLS_WIDTH-1:0] symbol_count;   // DQPSK symbols consumed so far
    reg [NUM_SYMBOLS_WIDTH-1:0] num_symbols_reg;
    reg                         seq_parity;     // toggles per completed chirp sequence (0=this gap even, 1=this gap odd)
    reg [6:0]                   gap_counter;
    reg                         last_seq;       // latched: the gap currently running follows the FINAL sequence

    // latched sign bits, valid for the whole 38-sample subchirp
    reg sign_real_latched;
    reg sign_imag_latched;

    always @(posedge clk) begin
        if (reset) begin
            state             <= S_IDLE;
            subchirp_sel      <= 2'd0;
            sample_addr       <= 6'd0;
            sign_real_out     <= 1'b0;
            sign_imag_out     <= 1'b0;
            next_symbol_req   <= 1'b0;
            done              <= 1'b0;
            symbol_count      <= {NUM_SYMBOLS_WIDTH{1'b0}};
            num_symbols_reg   <= {NUM_SYMBOLS_WIDTH{1'b0}};
            chirp_index_reg   <= 2'd0;
            seq_parity        <= 1'b0;
            gap_counter       <= 7'd0;
            last_seq          <= 1'b0;
            sign_real_latched <= 1'b0;
            sign_imag_latched <= 1'b0;

        end else begin
            // defaults each cycle -- explicitly overridden where needed
            next_symbol_req <= 1'b0;
            done             <= 1'b0;

            case (state)

                // -----------------------------------------------------
                S_IDLE: begin
                    if (start) begin
                        chirp_index_reg <= chirp_index;
                        num_symbols_reg <= num_symbols;
                        symbol_count    <= {NUM_SYMBOLS_WIDTH{1'b0}};
                        subchirp_sel    <= 2'd0;
                        seq_parity      <= 1'b0;

                        if (num_symbols == {NUM_SYMBOLS_WIDTH{1'b0}}) begin
                            // edge case: empty packet, nothing to stream, no gap
                            state <= S_DONE;
                        end else begin
                            state <= S_REQ_SYM;
                        end
                    end
                end

                // -----------------------------------------------------
                S_REQ_SYM: begin
                    next_symbol_req <= 1'b1;   // one-cycle pulse
                    state           <= S_WAIT_SYM;
                end

                // -----------------------------------------------------
                S_WAIT_SYM: begin
                    if (dqpsk_valid) begin
                        sign_real_latched <= dqpsk_sign_real;
                        sign_imag_latched <= dqpsk_sign_imag;
                        sample_addr       <= 6'd0;
                        state             <= S_STREAM;
                    end
                    // else: keep waiting, next_symbol_req already fell
                    // back to 0 by default above -- Task 2's encoder is
                    // expected to hold the request internally if it needs
                    // more than one cycle to respond
                end

                // -----------------------------------------------------
                S_STREAM: begin
                    sign_real_out <= sign_real_latched;
                    sign_imag_out <= sign_imag_latched;
                    // subchirp_sel already holds the current k

                    if (sample_addr == 6'd37) begin
                        // last sample of this subchirp being output now
                        symbol_count <= symbol_count + 1'b1;

                        if (subchirp_sel == 2'd3) begin
                            // last subchirp of this chirp sequence done --
                            // a gap ALWAYS follows, whether or not more
                            // sequences remain (see correction note above)
                            subchirp_sel <= 2'd0;
                            // Load (gap_length - 1): counting inclusively
                            // from N down to 0 spends N+1 cycles, not N --
                            // loading N-1 makes the countdown take exactly
                            // N cycles (found via testbench: TEST 2/3 were
                            // measuring one extra cycle per gap before this
                            // fix).
                            gap_counter  <= (seq_parity ? gap_odd : gap_even) - 1'b1;
                            seq_parity   <= ~seq_parity;
                            last_seq     <= ((symbol_count + 1'b1) == num_symbols_reg);
                            state        <= S_GAP;
                        end else begin
                            // move to next subchirp within the same sequence
                            subchirp_sel <= subchirp_sel + 1'b1;
                            state        <= S_REQ_SYM;
                        end

                    end else begin
                        sample_addr <= sample_addr + 1'b1;
                    end
                end

                // -----------------------------------------------------
                S_GAP: begin
                    if (gap_counter == 7'd0) begin
                        // this gap has just finished counting down
                        if (last_seq)
                            state <= S_DONE;      // that was the trailing gap -- packet complete
                        else
                            state <= S_REQ_SYM;    // start the next chirp sequence
                    end else begin
                        gap_counter <= gap_counter - 1'b1;
                    end
                end

                // -----------------------------------------------------
                S_DONE: begin
                    done         <= 1'b1;   // one-cycle pulse
                    state        <= S_IDLE;
                end

                // -----------------------------------------------------
                default: state <= S_IDLE;

            endcase
        end
    end

endmodule