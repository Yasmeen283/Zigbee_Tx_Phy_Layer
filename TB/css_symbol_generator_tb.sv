// =========================================================================
// tb_css_symbol_generator.sv
//
// Integration testbench for the Task 3 top-level wrapper: chirp_rom +
// csk_generator + complex_multiplier, wired together as
// css_symbol_generator.v.
//
// This is deliberately NOT just a repeat of the unit tests already run
// against csk_generator on its own. Those already proved the sequencing
// FSM is correct in isolation. What ONLY an integration test can catch:
//   - is the 1-cycle ROM latency actually compensated correctly (Stage A)
//   - is the complex multiply correctly fed the RIGHT rom sample paired
//     with the RIGHT sign, at the RIGHT cycle (Stage B)
//   - does tx_valid land on the SAME cycle as the tx_real/tx_imag they
//     describe
//   - does the wrapper's own chirp_index latch actually protect against
//     the caller changing chirp_index mid-packet (TC5 -- this is a
//     regression test for the exact bug class the wrapper was written
//     to prevent)
//
// How the data-correctness check works (Stage A / Stage B):
// This testbench does NOT hard-code any expected chirp sample values,
// and does NOT care what is actually inside chirp_rom_real.mem /
// chirp_rom_imag.mem -- real chirp data, placeholder data, anything.
// Instead it reads the DUT's OWN loaded ROM contents via a hierarchical
// reference (uut.u_chirp_rom.rom_real_mem / rom_imag_mem) and
// independently recomputes what complex_multiplier should have produced,
// using the exact same conditional-negate formula, then compares that
// against the DUT's real tx_real/tx_imag/tx_valid, cycle-exact. This
// means the same testbench is valid whether it's run against dummy
// memory files (as it was written and verified here) or against the
// real, MATLAB-exported chirp ROM contents -- swap the .mem files and
// rerun.
//
// Pipeline timing (see css_symbol_generator.v's own header comment for
// the full derivation):
//   cycle N   : address (chirp_index_latched, subchirp_sel, sample_addr)
//               issued, sample_valid asserted combinationally
//   cycle N+1 : rom_real/rom_imag now respond to the cycle-N address;
//               sign_real_out/sign_imag_out ALSO now reflect cycle N's
//               sign (already registered inside csk_generator); the
//               wrapper's sample_valid_d1 now equals cycle N's
//               sample_valid
//   cycle N+2 : tx_real/tx_imag/tx_valid now reflect complex_multiplier's
//               registered response to cycle N+1's inputs
// =========================================================================

`timescale 1ns/1ps

module tb_css_symbol_generator;

    localparam NUM_SYMBOLS_WIDTH = 12;
    localparam ROM_WIDTH         = 5;
    localparam OUT_WIDTH         = 6;

    // ---------------------------------------------------------------
    // Clock / reset
    // ---------------------------------------------------------------
    logic clk = 0;
    always #5 clk = ~clk;
    logic reset;

    // ---------------------------------------------------------------
    // DUT ports
    // ---------------------------------------------------------------
    logic        start;
    logic [1:0]  chirp_index;
    logic [NUM_SYMBOLS_WIDTH-1:0] num_symbols;

    logic        dqpsk_valid;
    logic        dqpsk_sign_real;
    logic        dqpsk_sign_imag;

    logic        next_symbol_req;
    logic        done;

    logic signed [OUT_WIDTH-1:0] tx_real;
    logic signed [OUT_WIDTH-1:0] tx_imag;
    logic        tx_valid;

    css_symbol_generator #(
        .NUM_SYMBOLS_WIDTH (NUM_SYMBOLS_WIDTH),
        .ROM_WIDTH         (ROM_WIDTH),
        .OUT_WIDTH         (OUT_WIDTH)
    ) uut (
        .clk             (clk),
        .reset           (reset),
        .start           (start),
        .chirp_index     (chirp_index),
        .num_symbols     (num_symbols),
        .dqpsk_valid     (dqpsk_valid),
        .dqpsk_sign_real (dqpsk_sign_real),
        .dqpsk_sign_imag (dqpsk_sign_imag),
        .next_symbol_req (next_symbol_req),
        .done            (done),
        .tx_real         (tx_real),
        .tx_imag         (tx_imag),
        .tx_valid        (tx_valid)
    );

    // ---------------------------------------------------------------
    // Bookkeeping
    // ---------------------------------------------------------------
    int unsigned error_count = 0;
    int unsigned check_count = 0;

    task automatic check(input bit cond, input string msg);
        check_count++;
        if (!cond) begin
            error_count++;
            $display("[%0t] ERROR: %s", $time, msg);
        end
    endtask

    // ---------------------------------------------------------------
    // DQPSK symbol source model (same style used for csk_generator's own
    // unit test): responds to next_symbol_req after a configurable
    // random delay, with signs pulled from a queue or random if empty.
    // ---------------------------------------------------------------
    bit sign_queue_sr[$];
    bit sign_queue_si[$];

    int resp_delay_min = 0;
    int resp_delay_max = 0;
    int delay;
    bit s_sr, s_si;

    initial begin
        dqpsk_valid = 1'b0; dqpsk_sign_real = 1'b0; dqpsk_sign_imag = 1'b0;
        forever begin
            @(posedge clk);
            if (next_symbol_req) begin
                delay = (resp_delay_max > resp_delay_min) ?
                         $urandom_range(resp_delay_max, resp_delay_min) : resp_delay_min;
                repeat (delay) @(posedge clk);
                if (sign_queue_sr.size() != 0) begin
                    s_sr = sign_queue_sr.pop_front();
                    s_si = sign_queue_si.pop_front();
                end else begin
                    s_sr = $urandom_range(1,0);
                    s_si = $urandom_range(1,0);
                end
                dqpsk_sign_real <= s_sr;
                dqpsk_sign_imag <= s_si;
                dqpsk_valid     <= 1'b1;
                @(posedge clk);
                dqpsk_valid <= 1'b0;
            end
        end
    end

    // =================================================================
    // STAGE A -- one cycle after an address is issued, check the ROM
    // response is bit-exact against the DUT's own loaded memory, and
    // that sample_valid_d1 correctly reflects last cycle's sample_valid.
    // =================================================================
    reg [1:0] addrA_chirp_index;
    reg [1:0] addrA_subchirp_sel;
    reg [5:0] addrA_sample_addr;
    reg       addrA_valid;

    always @(posedge clk) begin
        addrA_chirp_index  <= uut.chirp_index_latched;
        addrA_subchirp_sel <= uut.subchirp_sel;
        addrA_sample_addr  <= uut.sample_addr;
        addrA_valid        <= uut.sample_valid;
    end

    // =================================================================
    // STAGE B -- one more cycle later, snapshot the (now ROM-correct)
    // rom_real/rom_imag + sign bits + delayed valid, exactly as
    // complex_multiplier itself would have latched them.
    // =================================================================
    reg signed [ROM_WIDTH-1:0] mulB_rom_real;
    reg signed [ROM_WIDTH-1:0] mulB_rom_imag;
    reg                        mulB_sign_real;
    reg                        mulB_sign_imag;
    reg                        mulB_valid;

    always @(posedge clk) begin
        mulB_rom_real  <= uut.rom_real;
        mulB_rom_imag  <= uut.rom_imag;
        mulB_sign_real <= uut.sign_real_out;
        mulB_sign_imag <= uut.sign_imag_out;
        mulB_valid     <= uut.sample_valid_d1;
    end

    // =================================================================
    // Continuous checks -- sampled at negedge so all posedge updates
    // (DUT's and this testbench's own shadow registers) have settled.
    // =================================================================
    logic signed [ROM_WIDTH-1:0] exp_rom_real, exp_rom_imag;
    logic signed [OUT_WIDTH-1:0] c_ext, d_ext;
    logic signed [OUT_WIDTH-1:0] exp_tx_real, exp_tx_imag;
    reg       chirp_index_at_start_valid;
    int unsigned tx_valid_count = 0;

    always @(negedge clk) begin
        if (!reset) begin

            // ---- Stage A checks: ROM correctness + valid-delay alignment ----
            if (addrA_valid) begin
                exp_rom_real = uut.u_chirp_rom.rom_real_mem[{addrA_chirp_index, addrA_subchirp_sel, addrA_sample_addr}];
                exp_rom_imag = uut.u_chirp_rom.rom_imag_mem[{addrA_chirp_index, addrA_subchirp_sel, addrA_sample_addr}];
                check(uut.rom_real === exp_rom_real,
                      $sformatf("rom_real mismatch at addr(ci=%0d,k=%0d,a=%0d): got %0d expected %0d",
                                addrA_chirp_index, addrA_subchirp_sel, addrA_sample_addr, uut.rom_real, exp_rom_real));
                check(uut.rom_imag === exp_rom_imag,
                      $sformatf("rom_imag mismatch at addr(ci=%0d,k=%0d,a=%0d): got %0d expected %0d",
                                addrA_chirp_index, addrA_subchirp_sel, addrA_sample_addr, uut.rom_imag, exp_rom_imag));
            end
            check(uut.sample_valid_d1 == addrA_valid,
                  "sample_valid_d1 does not equal sample_valid delayed by exactly 1 cycle");

            // ---- Stage B checks: complex multiply correctness ----
            if (mulB_valid) begin
                c_ext = {{(OUT_WIDTH-ROM_WIDTH){mulB_rom_real[ROM_WIDTH-1]}}, mulB_rom_real};
                d_ext = {{(OUT_WIDTH-ROM_WIDTH){mulB_rom_imag[ROM_WIDTH-1]}}, mulB_rom_imag};
                exp_tx_real = (mulB_sign_real ? -c_ext : c_ext) - (mulB_sign_imag ? -d_ext : d_ext);
                exp_tx_imag = (mulB_sign_real ? -d_ext : d_ext) + (mulB_sign_imag ? -c_ext : c_ext);
                check(tx_real === exp_tx_real,
                      $sformatf("tx_real mismatch: got %0d expected %0d (rom_real=%0d rom_imag=%0d sr=%0b si=%0b)",
                                tx_real, exp_tx_real, mulB_rom_real, mulB_rom_imag, mulB_sign_real, mulB_sign_imag));
                check(tx_imag === exp_tx_imag,
                      $sformatf("tx_imag mismatch: got %0d expected %0d (rom_real=%0d rom_imag=%0d sr=%0b si=%0b)",
                                tx_imag, exp_tx_imag, mulB_rom_real, mulB_rom_imag, mulB_sign_real, mulB_sign_imag));
            end
            check(tx_valid == mulB_valid,
                  "tx_valid does not equal sample_valid delayed by exactly 2 cycles total");

            if (tx_valid) tx_valid_count++;

            // ---- chirp_index latch regression check (TC5 relies on this) ----
            if (chirp_index_at_start_valid)
                check(uut.chirp_index_latched == chirp_index_at_start,
                      $sformatf("chirp_index_latched drifted mid-packet: now %0d, expected %0d (latched at start)",
                                uut.chirp_index_latched, chirp_index_at_start));
        end
    end

    // Tracks what chirp_index SHOULD stay latched at, from the testbench's
    // own point of view -- independent of uut.chirp_index_latched, so the
    // check above is a genuine external check, not a circular one.
    reg [1:0] chirp_index_at_start;
    

    // ---------------------------------------------------------------
    // Reset
    // ---------------------------------------------------------------
    task automatic do_reset();
        reset = 1'b1; start = 1'b0; chirp_index = 2'd0; num_symbols = '0;
        sign_queue_sr.delete(); sign_queue_si.delete();
        chirp_index_at_start_valid = 1'b0;
        repeat (3) @(posedge clk);
        reset <= 1'b0;
        @(posedge clk);
    endtask

    // ---------------------------------------------------------------
    // Drive one packet, wait for done, return the observed tx_valid count.
    // `drift_index`, if >= 0, is written to the LIVE chirp_index input a
    // few cycles into the packet -- TC5 uses this to prove the wrapper's
    // latch actually holds against exactly this kind of interference.
    // ---------------------------------------------------------------
    task automatic run_packet(
        input  [1:0]  idx,
        input  [NUM_SYMBOLS_WIDTH-1:0] n_syms,
        input  int    drift_index,   // -1 = no drift
        output int unsigned tx_valid_count_out
    );
        int unsigned timeout_cycles;

        tx_valid_count = 0;

        @(posedge clk);
        chirp_index <= idx;
        num_symbols <= n_syms;
        start       <= 1'b1;
        chirp_index_at_start = idx;
        @(posedge clk);              // <-- DUT samples start=1 HERE and updates
                                      //     chirp_index_latched on THIS edge
        start <= 1'b0;
        chirp_index_at_start_valid = 1'b1;  // only safe to start checking now,
                                             // one cycle later than before

        if (drift_index >= 0) begin
            repeat (5) @(posedge clk);
            chirp_index <= drift_index[1:0]; // interference: should have NO effect on this packet
        end

        timeout_cycles = 0;
        while (!done && timeout_cycles < 200000) begin
            @(posedge clk);
            timeout_cycles++;
        end
        check(timeout_cycles < 200000,
              $sformatf("TIMEOUT waiting for done (chirp_index=%0d, num_symbols=%0d)", idx, n_syms));

        repeat (4) @(posedge clk); // let the 2-cycle output pipeline fully drain past done
        chirp_index_at_start_valid = 1'b0;

        tx_valid_count_out = tx_valid_count;
    endtask

    // =================================================================
    // TEST SEQUENCE
    // =================================================================
    int unsigned tvc;

    initial begin
        chirp_index_at_start_valid = 1'b0;

        $display("==================================================");
        $display(" css_symbol_generator integration testbench starting");
        $display("==================================================");

        // ---------------- TC1: reset ----------------
        $display("\n-- TC1: reset behavior --");
        reset = 1'b1; start = 1'b0; chirp_index = 2'd0; num_symbols = '0;
        repeat (3) @(posedge clk);
        check(tx_valid == 1'b0, "tx_valid not 0 immediately after reset");
        check(done     == 1'b0, "done not 0 immediately after reset");
        do_reset();

        // ---------------- TC2: empty packet ----------------
        $display("\n-- TC2: empty packet (num_symbols == 0) --");
        run_packet(2'd0, '0, -1, tvc);
        check(tvc == 0, $sformatf("empty packet produced %0d tx_valid samples, expected 0", tvc));
        do_reset();

        // ---------------- TC3: single sequence, all chirp_index values ----------------
        $display("\n-- TC3: single chirp sequence (num_symbols=4), all chirp_index values --");
        for (int idx = 0; idx < 4; idx++) begin
            run_packet(idx[1:0], 12'd4, -1, tvc);
            check(tvc == 4*38, $sformatf("idx=%0d: expected %0d tx_valid samples, got %0d", idx, 4*38, tvc));
            do_reset();
        end

        // ---------------- TC4: multi-sequence packet, all chirp_index values ----------------
        $display("\n-- TC4: multi-sequence packet (3 sequences = 12 symbols), all chirp_index values --");
        for (int idx = 0; idx < 4; idx++) begin
            run_packet(idx[1:0], 12'd12, -1, tvc);
            check(tvc == 12*38, $sformatf("idx=%0d: expected %0d tx_valid samples, got %0d", idx, 12*38, tvc));
            do_reset();
        end

        // ---------------- TC5: chirp_index drift mid-packet (wrapper-latch regression) ----------------
        $display("\n-- TC5: chirp_index changes mid-packet -- must NOT affect this packet's ROM data --");
        run_packet(2'd1, 12'd8, 3 /* drift to index 3 mid-packet */, tvc);
        check(tvc == 8*38, $sformatf("TC5: expected %0d tx_valid samples, got %0d", 8*38, tvc));
        do_reset();

        // ---------------- TC6: variable DQPSK response latency ----------------
        $display("\n-- TC6: variable DQPSK response latency (0-4 cycle stalls) --");
        resp_delay_min = 0; resp_delay_max = 4;
        run_packet(2'd2, 12'd8, -1, tvc);
        check(tvc == 8*38, $sformatf("TC6: expected %0d tx_valid samples, got %0d", 8*38, tvc));
        resp_delay_min = 0; resp_delay_max = 0;
        do_reset();

        // ---------------- TC7: back-to-back packets ----------------
        $display("\n-- TC7: back-to-back packets, different chirp_index/num_symbols each time --");
        run_packet(2'd0, 12'd4, -1, tvc);
        check(tvc == 4*38, "TC7 (packet 1): unexpected tx_valid count");
        run_packet(2'd3, 12'd8, -1, tvc);
        check(tvc == 8*38, "TC7 (packet 2): unexpected tx_valid count -- possible stale state from packet 1");
        do_reset();

        // ---------------- Summary ----------------
        $display("\n==================================================");
        if (error_count == 0)
            $display(" ALL TESTS PASSED  (%0d checks, 0 errors)", check_count);
        else
            $display(" TESTS FAILED  (%0d checks, %0d errors)", check_count, error_count);
        $display("==================================================");

        $finish;
    end

    // ---------------------------------------------------------------
    // Safety watchdog
    // ---------------------------------------------------------------
    initial begin
        #5_000_000;
        $display("GLOBAL WATCHDOG TIMEOUT -- simulation did not finish in time");
        $finish;
    end

endmodule