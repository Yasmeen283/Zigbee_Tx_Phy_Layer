`timescale 1ns/1ps

module tb_css_modulator;

    reg signed [1:0] s_real, s_imag;
    reg signed [5:0] chirp_real, chirp_imag;
    wire signed [7:0] tx_real, tx_imag;
    integer errors;

    css_modulator dut (
        .s_real(s_real), .s_imag(s_imag),
        .chirp_real(chirp_real), .chirp_imag(chirp_imag),
        .tx_real(tx_real), .tx_imag(tx_imag)
    );

    task check;
        input signed [1:0] sr, si;
        input signed [5:0] cr, ci;
        input signed [7:0] exp_r, exp_i;
        begin
            s_real = sr; s_imag = si; chirp_real = cr; chirp_imag = ci; #1;
            if (tx_real !== exp_r || tx_imag !== exp_i) begin
                $display("FAIL S=(%0d,%0d) C=(%0d,%0d) -> Tx=(%0d,%0d) expected (%0d,%0d)",
                          sr, si, cr, ci, tx_real, tx_imag, exp_r, exp_i);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        // (Sr+jSi)*(Cr+jCi) = (Sr*Cr - Si*Ci) + j(Sr*Ci + Si*Cr)
        check(2'sd1,  2'sd1,  6'sd5,   -6'sd3,  8'sd8,   8'sd2);   // 5+3 , -3+5
        check(-2'sd1, 2'sd1,  6'sd10,   6'sd4,  -8'sd14,  8'sd6);  // -10-4 , -4+10
        check(2'sd1, -2'sd1, -6'sd20,  6'sd15, -8'sd5,   8'sd35);  // -20+15 , 15+20
        check(-2'sd1,-2'sd1,  6'sd31, -6'sd32, -8'sd63,  8'sd1);   // -31-32 , 32-31
        check(2'sd1,  2'sd1,  6'sd0,   6'sd0,  8'sd0,   8'sd0);    // silence sample

        if (errors == 0)
            $display("PASS: tb_css_modulator -- complex multiply matches hand-computed products");
        else
            $display("FAIL: tb_css_modulator -- %0d mismatches", errors);
        $finish;
    end

endmodule
