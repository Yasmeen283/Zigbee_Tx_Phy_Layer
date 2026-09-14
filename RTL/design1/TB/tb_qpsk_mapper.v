`timescale 1ns/1ps

module tb_qpsk_mapper;

    reg  i_bit, q_bit;
    wire signed [1:0] qpsk_real, qpsk_imag;
    integer errors;

    qpsk_mapper dut ( .i_bit(i_bit), .q_bit(q_bit),
                       .qpsk_real(qpsk_real), .qpsk_imag(qpsk_imag) );

    task check;
        input i, q;
        input signed [1:0] exp_r, exp_i;
        begin
            i_bit = i; q_bit = q; #1;
            if (qpsk_real !== exp_r || qpsk_imag !== exp_i) begin
                $display("FAIL I=%0d Q=%0d -> real=%0d imag=%0d (expected real=%0d imag=%0d)",
                          i, q, qpsk_real, qpsk_imag, exp_r, exp_i);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        // From Section 8.2 of the deep-dive doc:
        // I=+1,Q=+1 -> (+1,0) ; I=+1,Q=-1 -> (0,-1) ; I=-1,Q=+1 -> (0,+1) ; I=-1,Q=-1 -> (-1,0)
        check(1'b1, 1'b1, 2'sd1,  2'sd0);
        check(1'b1, 1'b0, 2'sd0, -2'sd1);
        check(1'b0, 1'b1, 2'sd0,  2'sd1);
        check(1'b0, 1'b0, -2'sd1, 2'sd0);

        if (errors == 0)
            $display("PASS: tb_qpsk_mapper -- all 4 constellation points match Section 8.2");
        else
            $display("FAIL: tb_qpsk_mapper -- %0d mismatches", errors);
        $finish;
    end

endmodule
