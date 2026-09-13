`timescale 1ns/1ps

module tb_dqpsk_encoder;

    reg clk, reset, symbol_valid;
    reg signed [1:0] x_real, x_imag;
    wire signed [1:0] s_real, s_imag;

    dqpsk_encoder dut (
        .clk(clk), .reset(reset), .symbol_valid(symbol_valid),
        .x_real(x_real), .x_imag(x_imag),
        .s_real(s_real), .s_imag(s_imag)
    );

    always #5 clk = ~clk;

    // ---- independent reference model: same recursion, computed in the TB ----
    integer ref_mem_r [0:3];
    integer ref_mem_i [0:3];
    integer ref_wptr;
    integer exp_r, exp_i;

    // The 4 possible QPSK symbols, cycled through in a known order so the
    // TB and the DUT are always driven identically.
    reg signed [1:0] seq_r [0:15];
    reg signed [1:0] seq_i [0:15];
    integer n, errors;

    initial begin
        // exercise all 4 QPSK constellation points, repeated, 16 symbols total
        seq_r[0]=1;  seq_i[0]=0;   seq_r[1]=0;  seq_i[1]=-1;
        seq_r[2]=0;  seq_i[2]=1;   seq_r[3]=-1; seq_i[3]=0;
        seq_r[4]=-1; seq_i[4]=0;   seq_r[5]=1;  seq_i[5]=0;
        seq_r[6]=0;  seq_i[6]=-1;  seq_r[7]=0;  seq_i[7]=1;
        seq_r[8]=0;  seq_i[8]=1;   seq_r[9]=-1; seq_i[9]=0;
        seq_r[10]=1; seq_i[10]=0;  seq_r[11]=0; seq_i[11]=-1;
        seq_r[12]=0; seq_i[12]=-1; seq_r[13]=0; seq_i[13]=1;
        seq_r[14]=-1;seq_i[14]=0;  seq_r[15]=1; seq_i[15]=0;
    end

    initial begin
        errors = 0;
        clk = 0; reset = 1; symbol_valid = 0; x_real = 0; x_imag = 0;
        ref_mem_r[0]=1; ref_mem_r[1]=1; ref_mem_r[2]=1; ref_mem_r[3]=1;
        ref_mem_i[0]=1; ref_mem_i[1]=1; ref_mem_i[2]=1; ref_mem_i[3]=1;
        ref_wptr = 0;

        @(negedge clk); @(negedge clk);
        reset = 0;

        for (n = 0; n < 16; n = n + 1) begin
            @(negedge clk);
            x_real = seq_r[n]; x_imag = seq_i[n]; symbol_valid = 1;
            // reference model: S(n) = X(n)*S(n-4)
            exp_r = seq_r[n]*ref_mem_r[ref_wptr] - seq_i[n]*ref_mem_i[ref_wptr];
            exp_i = seq_r[n]*ref_mem_i[ref_wptr] + seq_i[n]*ref_mem_r[ref_wptr];
            ref_mem_r[ref_wptr] = exp_r;
            ref_mem_i[ref_wptr] = exp_i;
            ref_wptr = (ref_wptr + 1) % 4;

            @(negedge clk); // one cycle later, DUT's s_real/s_imag reflect S(n)
            symbol_valid = 0;
            if (s_real !== exp_r[1:0] || s_imag !== exp_i[1:0]) begin
                $display("FAIL n=%0d X=(%0d,%0d) -> DUT S=(%0d,%0d) expected (%0d,%0d)",
                          n, seq_r[n], seq_i[n], s_real, s_imag, exp_r, exp_i);
                errors = errors + 1;
            end
        end

        if (errors == 0)
            $display("PASS: tb_dqpsk_encoder -- matches independent S(n)=X(n)*S(n-4) reference model");
        else
            $display("FAIL: tb_dqpsk_encoder -- %0d mismatches", errors);
        $finish;
    end

endmodule
