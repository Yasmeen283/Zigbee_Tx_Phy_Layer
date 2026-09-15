// Self-checking testbench for tx_datapath_top (controller external).
// Models the Controller as a simple symbol source: responds to symbol_req
// with one (i_bit,q_bit) pair + qpsk_valid pulse.
`timescale 1ns/1ps
module tb_tx_datapath_top;
    localparam NSW = 12, ROMW = 5, OUTW = 6;

    logic clk = 0; always #5 clk = ~clk;
    logic reset;
    logic start;
    logic [1:0] chirp_index;
    logic [NSW-1:0] num_symbols;
    logic tx_done;
    logic i_bit, q_bit, qpsk_valid;
    logic symbol_req;
    logic signed [OUTW-1:0] tx_real, tx_imag;
    logic tx_valid;

    tx_datapath_top #(.NUM_SYMBOLS_WIDTH(NSW), .ROM_WIDTH(ROMW), .OUT_WIDTH(OUTW)) uut (
        .clk(clk), .reset(reset), .start(start), .chirp_index(chirp_index),
        .num_symbols(num_symbols), .tx_done(tx_done),
        .i_bit(i_bit), .q_bit(q_bit), .qpsk_valid(qpsk_valid), .symbol_req(symbol_req),
        .tx_real(tx_real), .tx_imag(tx_imag), .tx_valid(tx_valid)
    );

    int unsigned error_count = 0, check_count = 0;
    task automatic check(input bit c, input string m);
        check_count++;
        if (!c) begin error_count++; $display("[%0t] ERROR: %s", $time, m); end
    endtask

    // ---- Controller model: one symbol per request, configurable latency ----
    int resp_min = 0, resp_max = 0, dly;
    int symbols_sent = 0;
    initial begin
        i_bit = 0; q_bit = 0; qpsk_valid = 0;
        forever begin
            @(posedge clk);
            if (symbol_req) begin
                dly = (resp_max > resp_min) ? $urandom_range(resp_max, resp_min) : resp_min;
                repeat (dly) @(posedge clk);
                i_bit      <= $urandom_range(1,0);
                q_bit      <= $urandom_range(1,0);
                qpsk_valid <= 1'b1;
                symbols_sent++;
                @(posedge clk);
                qpsk_valid <= 1'b0;
            end
        end
    end

    // ---- continuous checks ----
    int unsigned tx_valid_count = 0;
    always @(negedge clk) if (!reset) begin
        if (tx_valid) begin
            tx_valid_count++;
            // output must always fit the derived 6-bit signed range
            check(tx_real >= -32 && tx_real <= 31, "tx_real out of 6-bit signed range");
            check(tx_imag >= -32 && tx_imag <= 31, "tx_imag out of 6-bit signed range");
        end
    end

    task automatic do_reset();
        reset <= 1; start <= 0; chirp_index <= 0; num_symbols <= 0;
        repeat (3) @(posedge clk);
        reset <= 0; @(posedge clk);
    endtask

    task automatic run_packet(input [1:0] ci, input [NSW-1:0] n, output int unsigned vc, output int unsigned sent);
        int to;
        tx_valid_count = 0; symbols_sent = 0;
        @(posedge clk);
        chirp_index <= ci; num_symbols <= n; start <= 1;
        @(posedge clk); start <= 0;
        to = 0;
        while (!tx_done && to < 200000) begin @(posedge clk); to++; end
        check(to < 200000, $sformatf("TIMEOUT (ci=%0d n=%0d)", ci, n));
        repeat (4) @(posedge clk);
        vc = tx_valid_count; sent = symbols_sent;
    endtask

    int unsigned vc, sent;
    initial begin
        $display("=== tb_tx_datapath_top ===");
        do_reset();

        // TC1: reset state
        check(tx_valid === 1'b0, "tx_valid not 0 after reset");
        check(tx_done  === 1'b0, "tx_done not 0 after reset");

        // TC2: single chirp sequence, all chirp_index values
        for (int ci = 0; ci < 4; ci++) begin
            run_packet(ci[1:0], 12'd4, vc, sent);
            check(vc == 4*38, $sformatf("ci=%0d: expected %0d tx_valid, got %0d", ci, 4*38, vc));
            check(sent == 4,  $sformatf("ci=%0d: expected 4 symbols consumed, got %0d", ci, sent));
            do_reset();
        end

        // TC3: multi-sequence
        for (int ci = 0; ci < 4; ci++) begin
            run_packet(ci[1:0], 12'd12, vc, sent);
            check(vc == 12*38, $sformatf("ci=%0d: expected %0d tx_valid, got %0d", ci, 12*38, vc));
            check(sent == 12,  $sformatf("ci=%0d: expected 12 symbols consumed, got %0d", ci, sent));
            do_reset();
        end

        // TC4: larger packet (full preamble+SFD+payload scale, 1 Mbps: 48+8=56)
        run_packet(2'd0, 12'd56, vc, sent);
        check(vc == 56*38, $sformatf("expected %0d tx_valid, got %0d", 56*38, vc));
        check(sent == 56,  $sformatf("expected 56 symbols consumed, got %0d", sent));
        do_reset();

        // TC5: 250 kbps scale (96+12=108)
        run_packet(2'd2, 12'd108, vc, sent);
        check(vc == 108*38, $sformatf("expected %0d tx_valid, got %0d", 108*38, vc));
        check(sent == 108,  $sformatf("expected 108 symbols consumed, got %0d", sent));
        do_reset();

        // TC6: variable controller response latency
        resp_min = 0; resp_max = 4;
        run_packet(2'd1, 12'd8, vc, sent);
        check(vc == 8*38, $sformatf("variable latency: expected %0d tx_valid, got %0d", 8*38, vc));
        check(sent == 8,  $sformatf("variable latency: expected 8 symbols, got %0d", sent));
        resp_min = 0; resp_max = 0;
        do_reset();

        // TC7: back-to-back packets
        run_packet(2'd0, 12'd4, vc, sent);
        check(vc == 4*38 && sent == 4, "back-to-back packet 1 stats wrong");
        run_packet(2'd3, 12'd8, vc, sent);
        check(vc == 8*38 && sent == 8, "back-to-back packet 2 stats wrong -- stale state?");

        $display("=========================================");
        if (error_count == 0) $display(" ALL TESTS PASSED (%0d checks, 0 errors)", check_count);
        else                  $display(" TESTS FAILED (%0d checks, %0d errors)", check_count, error_count);
        $display("=========================================");
        $finish;
    end

    initial begin #10_000_000; $display("WATCHDOG TIMEOUT"); $finish; end
endmodule
