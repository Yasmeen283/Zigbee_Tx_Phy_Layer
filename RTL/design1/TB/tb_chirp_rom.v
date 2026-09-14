`timescale 1ns/1ps

module tb_chirp_rom;

    reg  [7:0] addr;
    wire signed [5:0] chirp_real, chirp_imag;
    integer errors;

    chirp_rom #( .SAMPLES(152), .MEMFILE("vectors/chirp_m1.mem") )
        dut ( .addr(addr), .chirp_real(chirp_real), .chirp_imag(chirp_imag) );

    task check;
        input [7:0] a;
        input signed [5:0] exp_r, exp_i;
        begin
            addr = a; #1;
            if (chirp_real !== exp_r || chirp_imag !== exp_i) begin
                $display("FAIL addr=%0d real=%0d(exp %0d) imag=%0d(exp %0d)",
                          a, chirp_real, exp_r, chirp_imag, exp_i);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        // spot checks against chirp_m1.mem (== project's chirpSequence.txt, chirpIndex=1),
        // 6-bit two's complement: real then imag, 152 samples each
        check(8'd0,   6'b000000, 6'b000000); //   0 ,   0
        check(8'd151, 6'b100001, 6'b000000); // -31 ,   0   (last sample of the sequence)
        check(8'd75,  6'b000000, 6'b100001); //   0 , -31   (subchirp-1/subchirp-2 boundary area)

        if (errors == 0)
            $display("PASS: tb_chirp_rom -- ROM contents match chirpSequence.txt (chirpIndex=1)");
        else
            $display("FAIL: tb_chirp_rom -- %0d mismatches", errors);
        $finish;
    end

endmodule
