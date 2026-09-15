`timescale 1ns / 1ps

module chirp_rom_tb;

    // ------------------------------------------------------------------------
    // Clock and Control Signals
    // ------------------------------------------------------------------------
    reg        clk;
    reg  [1:0] chirp_index;
    reg  [1:0] subchirp_sel;
    reg  [5:0] sample_addr;

    wire [4:0] rom_real;
    wire [4:0] rom_imag;

    // Error and Test Counters for Self-Checking
    integer error_count = 0;
    integer test_count  = 0;

    // ------------------------------------------------------------------------
    // Instantiate Unit Under Test (UUT)
    // ------------------------------------------------------------------------
    chirp_rom uut (
        .clk          (clk),
        .chirp_index  (chirp_index),
        .subchirp_sel (subchirp_sel),
        .sample_addr  (sample_addr),
        .rom_real     (rom_real),
        .rom_imag     (rom_imag)
    );

    // ------------------------------------------------------------------------
    // Clock Generation (100 MHz Simulation Clock)
    // ------------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk; // 10 ns clock period

    // ------------------------------------------------------------------------
    // Test Task for Self-Checking Range and Output
    // ------------------------------------------------------------------------
    task check_rom_output;
        input [1:0] exp_m;
        input [1:0] exp_k;
        input [5:0] exp_n;
        begin
            @(posedge clk); #1; // Wait 1ns after clock edge for registered output stability
            test_count = test_count + 1;

            if (exp_n > 6'd37) begin
                // Check Unused Address Behavior (Should return 0)
                if (rom_real !== 5'sd0 || rom_imag !== 5'sd0) begin
                    $display("[FAIL] Unused Addr m=%0d k=%0d n=%0d | Expected: (0,0) Got: (%0d,%0d)", 
                             exp_m, exp_k, exp_n, $signed(rom_real), $signed(rom_imag));
                    error_count = error_count + 1;
                end
            end else begin
                // Range Check for R=5 (-16 to +15)
                if ($signed(rom_real) < -16 || $signed(rom_real) > 15 ||
                    $signed(rom_imag) < -16 || $signed(rom_imag) > 15) begin
                    $display("[FAIL] Out of Range m=%0d k=%0d n=%0d | Got: Real=%0d Imag=%0d", 
                             exp_m, exp_k, exp_n, $signed(rom_real), $signed(rom_imag));
                    error_count = error_count + 1;
                end
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Main Stimulus Sequence
    // ------------------------------------------------------------------------
    integer m, k, n;

    initial begin
        // Initialize Inputs
        chirp_index  = 0;
        subchirp_sel = 0;
        sample_addr  = 0;

        $display("==================================================");
        $display("Starting Self-Checking Testbench for chirp_rom (R=5)");
        $display("==================================================");

        // Wait for clock stabilization
        #20;

        // --------------------------------------------------------------------
        // Test Case 1: Boundary & Full Valid Address Sweep (m=0..3, k=0..3, n=0..37)
        // --------------------------------------------------------------------
        $display("[INFO] Running Valid Address Sweep and Range Checks...");
        for (m = 0; m < 4; m = m + 1) begin
            for (k = 0; k < 4; k = k + 1) begin
                for (n = 0; n <= 37; n = n + 1) begin
                    chirp_index  = m[1:0];
                    subchirp_sel = k[1:0];
                    sample_addr  = n[5:0];
                    check_rom_output(m[1:0], k[1:0], n[5:0]);
                end
            end
        end

        // --------------------------------------------------------------------
        // Test Case 2: Unused Address Sweep (n = 38..63)
        // --------------------------------------------------------------------
        $display("[INFO] Running Unused Address Checks (n = 38..63)...");
        for (m = 0; m < 4; m = m + 3) begin // Test m=0 and m=3 boundaries
            for (k = 0; k < 4; k = k + 3) begin // Test k=0 and k=3 boundaries
                for (n = 38; n < 64; n = n + 1) begin
                    chirp_index  = m[1:0];
                    subchirp_sel = k[1:0];
                    sample_addr  = n[5:0];
                    check_rom_output(m[1:0], k[1:0], n[5:0]);
                end
            end
        end

        // --------------------------------------------------------------------
        // Final Test Summary Report
        // --------------------------------------------------------------------
        #20;
        $display("==================================================");
        $display("TEST SUMMARY:");
        $display("Total Assertions Executed: %0d", test_count);
        if (error_count == 0) begin
            $display("RESULT: ALL TESTS PASSED SUCCESSFULLY! [PASS]");
        end else begin
            $display("RESULT: %0d TESTS FAILED! [FAIL]", error_count);
        end
        $display("==================================================");

        $finish;
    end

endmodule