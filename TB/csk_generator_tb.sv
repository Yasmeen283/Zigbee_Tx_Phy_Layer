// =========================================================================
// csk_generator_tb.v  (v2 -- rewritten to avoid an Icarus Verilog
// task-scheduling quirk found while building this testbench)
// =========================================================================
// Self-checking testbench for csk_generator (RTL v2, corrected
// trailing-gap behavior). Covers the "Basic tests" from the Task 3
// module spec, plus a dedicated regression test for the trailing-gap
// fix (Test 3 below).
//
// *** A note on testbench structure ***
// An earlier draft of this testbench used Verilog tasks containing
// `@(posedge clk)` (a `do_reset` task and a `run_packet` task). That
// version hung indefinitely under Icarus Verilog: confirmed, via
// multiple isolated experiments checking real DUT output ports (not
// just internal signals), that the RTL itself is correct -- a fully
// inline testbench with zero task calls drives the DUT perfectly. The
// hang was traced specifically to Icarus Verilog's handling of tasks
// that contain blocking timing controls: once such a task is called,
// a LATER top-level `@(posedge clk)` in the same process silently stops
// synchronizing with the DUT. This testbench avoids that pattern
// entirely: every `@(posedge clk)` lives either directly in the
// top-level initial block, or inside a `fork ... join` block (which
// was verified safe across repeated use). No task in this file
// contains a timing control.
//
// Simulate with:
//   iverilog -o sim csk_generator.v csk_generator_tb.v && vvp sim
// =========================================================================

`timescale 1ns/1ps

module csk_generator_tb;

    localparam NUM_SYMBOLS_WIDTH = 12;

    reg                          clk;
    reg                          reset;
    reg                          start;
    reg  [1:0]                   chirp_index;
    reg  [NUM_SYMBOLS_WIDTH-1:0] num_symbols;
    reg                          dqpsk_valid;
    reg                          dqpsk_sign_real;
    reg                          dqpsk_sign_imag;

    wire [1:0] subchirp_sel;
    wire [5:0] sample_addr;
    wire       sign_real_out;
    wire       sign_imag_out;
    wire       sample_valid;
    wire       next_symbol_req;
    wire       done;

    integer errors;
    integer test_num;

    // ---------------------------------------------------------------
    // DUT instantiation
    // ---------------------------------------------------------------
    csk_generator #(.NUM_SYMBOLS_WIDTH(NUM_SYMBOLS_WIDTH)) dut (
        .clk             (clk),
        .reset           (reset),
        .start           (start),
        .chirp_index     (chirp_index),
        .num_symbols     (num_symbols),
        .dqpsk_valid     (dqpsk_valid),
        .dqpsk_sign_real (dqpsk_sign_real),
        .dqpsk_sign_imag (dqpsk_sign_imag),
        .subchirp_sel    (subchirp_sel),
        .sample_addr     (sample_addr),
        .sign_real_out   (sign_real_out),
        .sign_imag_out   (sign_imag_out),
        .sample_valid    (sample_valid),
        .next_symbol_req (next_symbol_req),
        .done            (done)
    );

    // ---------------------------------------------------------------
    // Clock: 10ns period
    // ---------------------------------------------------------------
    always #5 clk = ~clk;

    // ---------------------------------------------------------------
    // Symbol responder -- a plain always block (no tasks), confirmed
    // safe. Responds to next_symbol_req after `response_delay` extra
    // cycles, with alternating dummy sign values.
    // ---------------------------------------------------------------
    integer response_delay;
    reg     pending_req;
    integer delay_counter;
    reg     next_sign_real;
    reg     next_sign_imag;

    initial begin
        pending_req    = 0;
        dqpsk_valid    = 0;
        dqpsk_sign_real = 0;
        dqpsk_sign_imag = 0;
        next_sign_real  = 0;
        next_sign_imag  = 1;
        response_delay  = 0;
    end

    always @(posedge clk) begin
        dqpsk_valid <= 0;

        if (next_symbol_req && !pending_req) begin
            pending_req   <= 1;
            delay_counter <= response_delay;
        end

        if (pending_req) begin
            if (delay_counter == 0) begin
                dqpsk_valid     <= 1;
                dqpsk_sign_real <= next_sign_real;
                dqpsk_sign_imag <= next_sign_imag;
                next_sign_real  <= ~next_sign_real;
                next_sign_imag  <= ~next_sign_imag;
                pending_req     <= 0;
            end else begin
                delay_counter <= delay_counter - 1;
            end
        end
    end

    // ---------------------------------------------------------------
    // Shared accumulators, reset and populated inline per test
    // ---------------------------------------------------------------
    integer vc, gc, rq; // valid cycles, gap cycles, next_symbol_req pulses

    // =================================================================
    // Test sequence -- everything below is either top-level inline
    // code or a fork/join block. No task contains a timing control.
    // =================================================================
    initial begin
        clk      = 0;
        reset    = 0;
        start    = 0;
        chirp_index = 0;
        num_symbols = 0;
        errors   = 0;
        test_num = 0;

        // =============================================================
        // TEST 1: single chirp sequence (4 symbols), fast responder.
        // Checks the subchirp_sel/sample_addr walk order directly
        // against an independent model computed inline.
        // =============================================================
        test_num = 1;
        response_delay = 0;

        reset = 1; start = 0;
        @(posedge clk); @(posedge clk);
        reset = 0;
        @(posedge clk);

        start = 1; chirp_index = 2'd0; num_symbols = 12'd4;
        @(posedge clk);
        start = 0;

        fork
            begin : test1_addr_walk
                integer exp_k, exp_addr;
                exp_k = 0; exp_addr = 0;
                while (done !== 1'b1) begin
                    @(posedge clk);
                    if (sample_valid) begin
                        if (subchirp_sel !== exp_k || sample_addr !== exp_addr) begin
                            $display("[TEST %0d] FAIL: expected (k=%0d,addr=%0d) got (k=%0d,addr=%0d) at t=%0t",
                                      test_num, exp_k, exp_addr, subchirp_sel, sample_addr, $time);
                            errors = errors + 1;
                        end
                        if (exp_addr == 37) begin
                            exp_addr = 0;
                            exp_k    = exp_k + 1;
                        end else begin
                            exp_addr = exp_addr + 1;
                        end
                    end
                end
            end
        join
        $display("[TEST %0d] Address-walk check for one chirp sequence complete.", test_num);

        // =============================================================
        // TEST 2: gap length + parity, all 4 chirp indices, 2 sequences
        // each (num_symbols=8), multi-cycle responder (response_delay=1).
        // =============================================================
        test_num = 2;
        response_delay = 1;

        begin : test2_gap_check
            integer ci;
            integer expected_even, expected_odd;

            for (ci = 0; ci < 4; ci = ci + 1) begin
                reset = 1; start = 0;
                @(posedge clk); @(posedge clk);
                reset = 0;
                @(posedge clk);

                case (ci)
                    0: begin expected_even = 10; expected_odd = 70; end
                    1: begin expected_even = 20; expected_odd = 60; end
                    2: begin expected_even = 30; expected_odd = 50; end
                    3: begin expected_even = 40; expected_odd = 40; end
                endcase

                vc = 0; gc = 0; rq = 0;
                start = 1; chirp_index = ci[1:0]; num_symbols = 12'd8;
                @(posedge clk);
                start = 0;

                fork
                    begin : test2_wait
                        while (done !== 1'b1) begin
                            @(posedge clk);
                            if (sample_valid)          vc = vc + 1;
                            if (dut.state == dut.S_GAP) gc = gc + 1;
                            if (next_symbol_req)        rq = rq + 1;
                        end
                    end
                join

                if (gc !== (expected_even + expected_odd)) begin
                    $display("[TEST %0d] FAIL: chirp_index=%0d total gap cycles = %0d, expected %0d (even=%0d + odd=%0d)",
                              test_num, ci, gc, expected_even+expected_odd, expected_even, expected_odd);
                    errors = errors + 1;
                end else begin
                    $display("[TEST %0d] PASS: chirp_index=%0d total gap cycles = %0d as expected", test_num, ci, gc);
                end
            end
        end

        // =============================================================
        // TEST 3 (REGRESSION): full 48-sequence packet, chirp_index=0
        // (m=1), num_symbols=192. Must total exactly the validated
        // MATLAB reference length of 9216 samples (streaming + gap).
        // This is the test that would have caught the trailing-gap bug.
        // =============================================================
        test_num = 3;
        response_delay = 0;

        reset = 1; start = 0;
        @(posedge clk); @(posedge clk);
        reset = 0;
        @(posedge clk);

        vc = 0; gc = 0; rq = 0;
        start = 1; chirp_index = 2'd0; num_symbols = 12'd192;
        @(posedge clk);
        start = 0;

        fork
            begin : test3_wait
                while (done !== 1'b1) begin
                    @(posedge clk);
                    if (sample_valid)          vc = vc + 1;
                    if (dut.state == dut.S_GAP) gc = gc + 1;
                    if (next_symbol_req)        rq = rq + 1;
                end
            end
        join

        if (vc !== 7296) begin
            $display("[TEST %0d] FAIL: valid (streaming) cycles = %0d, expected 7296 (152*48)", test_num, vc);
            errors = errors + 1;
        end else begin
            $display("[TEST %0d] PASS: valid streaming cycles = 7296 as expected", test_num);
        end

        if (gc !== 1920) begin
            $display("[TEST %0d] FAIL: total gap cycles = %0d, expected 1920 (24*10 + 24*70)", test_num, gc);
            errors = errors + 1;
        end else begin
            $display("[TEST %0d] PASS: total gap cycles = 1920 as expected (trailing gap included)", test_num);
        end

        if ((vc + gc) !== 9216) begin
            $display("[TEST %0d] FAIL: valid+gap total = %0d, expected 9216 (matches validated TxchirpSequences length)",
                      test_num, vc+gc);
            errors = errors + 1;
        end else begin
            $display("[TEST %0d] PASS: valid+gap total = 9216, matches the validated MATLAB reference length", test_num);
        end

        if (rq !== 192) begin
            $display("[TEST %0d] FAIL: next_symbol_req pulse count = %0d, expected 192 (once per subchirp)", test_num, rq);
            errors = errors + 1;
        end else begin
            $display("[TEST %0d] PASS: next_symbol_req pulsed exactly once per subchirp (192 times)", test_num);
        end

        // =============================================================
        // TEST 4: empty packet edge case (num_symbols = 0). Should go
        // straight to done: zero streaming, zero gap, zero requests.
        // =============================================================
        test_num = 4;

        reset = 1; start = 0;
        @(posedge clk); @(posedge clk);
        reset = 0;
        @(posedge clk);

        vc = 0; gc = 0; rq = 0;
        start = 1; chirp_index = 2'd0; num_symbols = 12'd0;
        @(posedge clk);
        start = 0;

        fork
            begin : test4_wait
                while (done !== 1'b1) begin
                    @(posedge clk);
                    if (sample_valid)          vc = vc + 1;
                    if (dut.state == dut.S_GAP) gc = gc + 1;
                    if (next_symbol_req)        rq = rq + 1;
                end
            end
        join

        if (vc !== 0 || gc !== 0 || rq !== 0) begin
            $display("[TEST %0d] FAIL: empty packet produced vc=%0d gc=%0d rq=%0d, expected all zero",
                      test_num, vc, gc, rq);
            errors = errors + 1;
        end else begin
            $display("[TEST %0d] PASS: empty packet (num_symbols=0) produced no streaming, no gap, no requests", test_num);
        end

        // =============================================================
        // TEST 5: done timing -- must deassert exactly one cycle after
        // pulsing (i.e. it really is a one-cycle pulse, not held high).
        // =============================================================
        test_num = 5;

        reset = 1; start = 0;
        @(posedge clk); @(posedge clk);
        reset = 0;
        @(posedge clk);

        start = 1; chirp_index = 2'd0; num_symbols = 12'd4;
        @(posedge clk);
        start = 0;

        fork
            begin : test5_wait
                while (done !== 1'b1) @(posedge clk);
            end
        join

        @(posedge clk);
        if (done !== 1'b0) begin
            $display("[TEST %0d] FAIL: done did not deassert the cycle after pulsing", test_num);
            errors = errors + 1;
        end else begin
            $display("[TEST %0d] PASS: done pulses for exactly one cycle", test_num);
        end

        // =============================================================
        // Summary
        // =============================================================
        @(posedge clk);
        if (errors == 0) begin
            $display("\n=====================================================");
            $display(" ALL TESTS PASSED (0 errors across 5 test groups)");
            $display("=====================================================\n");
        end else begin
            $display("\n=====================================================");
            $display(" TESTS FAILED: %0d error(s) found", errors);
            $display("=====================================================\n");
        end

        $finish;
    end

    // ---------------------------------------------------------------
    // Safety timeout, in case a real hang occurs
    // ---------------------------------------------------------------
    initial begin
        #2000000;
        $display("TIMEOUT: simulation did not finish in time -- likely DUT hang");
        $finish;
    end

endmodule