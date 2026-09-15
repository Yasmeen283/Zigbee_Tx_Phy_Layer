`timescale 1ns/1ps
//=============================================================================
// tb_css_tx_top.v -- full-chain integration testbench (Section 6 of the
// project spec: "a full-chain testbench that applies a payload, runs the
// simulation, and compares... against the... MATLAB model output").
//
// No bit-exact full-chain MATLAB golden file was provided among the project
// inputs (only per-block references: preambleSFD.txt, chirpSequence.txt,
// payload.txt), so this testbench is self-checking against two independent
// sources of truth instead:
//   1) The exact arithmetic worked example in Section 13 of the deep-dive
//      doc, for the project's own default configuration (payloadLength=25,
//      chirpIndex=1, 1 Mbps): padded_total_bits=216, n_codewords/path=36,
//      n_groups=48, total_symbols=192, total Tx samples=9216.
//   2) A bit-exact hand-derived expected sample: since the first 32
//      preamble chips are constant '1' on both I and Q, the first 4 QPSK/
//      DQPSK symbols of the packet are all (Xr,Xi)=(1,0), so
//      S(0)=S(1)=S(2)=S(3) = (1,0)*(1,1) = (1,1) (the initial condition
//      passes straight through). At chirp_rom address 151 (last sample of
//      chirp_m1.mem, chirpIndex=1) the stored sample is (real,imag) =
//      (-31, 0), so the very first group's last modulated sample must be
//      Tx = (1+j1)*(-31+j0) = (-31, -31).
//=============================================================================

module tb_css_tx_top;

    reg clk, reset;
    reg start_Tx;
    reg [7:0] PayloadLength;
    reg payload_wr_en;
    reg [6:0] payload_wr_addr;
    reg [7:0] payload_wr_data;
    wire done_Tx;
    wire signed [7:0] Tx_real, Tx_imag;
    wire tx_valid;

    css_tx_top dut (
        .clk(clk), .reset(reset),
        .start_Tx(start_Tx), .PayloadLength(PayloadLength),
        .payload_wr_en(payload_wr_en), .payload_wr_addr(payload_wr_addr), .payload_wr_data(payload_wr_data),
        .done_Tx(done_Tx), .Tx_real(Tx_real), .Tx_imag(Tx_imag), .tx_valid(tx_valid)
    );

    always #5 clk = ~clk;

    reg [7:0] payload_bytes [0:27];
    integer i, errors;
    integer sample_count;
    reg [2:0] prev_state;
    reg       first151_checked;

    localparam S_SUBCHIRP = 3'd2, S_GAP = 3'd3;

    initial begin
        errors = 0;
        sample_count = 0;
        first151_checked = 1'b0;
        clk = 0; reset = 1; start_Tx = 0; PayloadLength = 8'd0;
        payload_wr_en = 0; payload_wr_addr = 0; payload_wr_data = 0;

        $readmemb("vectors/payload.mem", payload_bytes);

        repeat (3) @(negedge clk);
        reset = 0;
        @(negedge clk);

        // load the first 25 bytes (payloadLength=25, the project's own default)
        for (i = 0; i < 25; i = i + 1) begin
            payload_wr_en   = 1'b1;
            payload_wr_addr = i[6:0];
            payload_wr_data = payload_bytes[i];
            @(negedge clk);
        end
        payload_wr_en = 1'b0;

        PayloadLength = 8'd25;
        start_Tx = 1'b1;
        @(negedge clk);
        start_Tx = 1'b0;

        // ---- structural checks against the Section-13 worked example ----
        #1;
        if (dut.padded_total_bits !== 16'd216) begin
            $display("FAIL padded_total_bits=%0d expected 216", dut.padded_total_bits);
            errors = errors + 1;
        end
        if (dut.n_codewords_per_path !== 16'd36) begin
            $display("FAIL n_codewords_per_path=%0d expected 36", dut.n_codewords_per_path);
            errors = errors + 1;
        end
        if (dut.n_groups !== 16'd48) begin
            $display("FAIL n_groups=%0d expected 48", dut.n_groups);
            errors = errors + 1;
        end

        // ---- run until done_Tx, counting samples and catching the addr-151 event ----
        prev_state = dut.state;
        while (done_Tx !== 1'b1) begin
            @(posedge clk);
            if (tx_valid) sample_count = sample_count + 1;

            // detect the edge SUBCHIRP(addr=151,group=0) -> GAP : Tx_real/Tx_imag
            // now hold the modulated sample for chirp_rom address 151 of group 0
            if (!first151_checked && prev_state == S_SUBCHIRP && dut.state == S_GAP && dut.group_idx == 16'd0) begin
                first151_checked = 1'b1;
                #1;
                if (Tx_real !== -8'sd31 || Tx_imag !== -8'sd31) begin
                    $display("FAIL first-group addr=151 sample = (%0d,%0d), expected (-31,-31)", Tx_real, Tx_imag);
                    errors = errors + 1;
                end else
                    $display("INFO first-group addr=151 sample = (%0d,%0d) matches hand-derived expectation", Tx_real, Tx_imag);
            end
            prev_state = dut.state;
        end

        // total modulated (non-gap) samples must be n_groups * 152 = 48*152 = 7296
        if (sample_count !== 7296) begin
            $display("FAIL total tx_valid sample count = %0d, expected 7296 (48 groups x 152)", sample_count);
            errors = errors + 1;
        end else
            $display("INFO total modulated samples = %0d (matches 48 groups x 152)", sample_count);

        if (errors == 0)
            $display("PASS: tb_css_tx_top -- structural counts and first bit-exact sample match expectations");
        else
            $display("FAIL: tb_css_tx_top -- %0d mismatches", errors);
        $finish;
    end

    // safety timeout
    initial begin
        #2_000_000;
        $display("FAIL: tb_css_tx_top -- timeout waiting for done_Tx");
        $finish;
    end

endmodule
