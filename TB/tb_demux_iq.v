`timescale 1ns/1ps

module tb_demux_iq;

    reg         bit_in;
    reg  [15:0] bit_index;
    wire        i_bit, q_bit, i_valid, q_valid;

    integer i, errors;
    reg [0:9] pattern; // 10 bits: bit1..bit10 in Section 5's own numbering example

    demux_iq dut (
        .bit_in(bit_in), .bit_index(bit_index),
        .i_bit(i_bit), .q_bit(q_bit),
        .i_valid(i_valid), .q_valid(q_valid)
    );

    initial begin
        errors  = 0;
        pattern = 10'b1011001101; // arbitrary padded-stream fragment

        for (i = 0; i < 10; i = i + 1) begin
            bit_in    = pattern[i];
            bit_index = i[15:0];
            #1;
            // 0-based: even index -> I, odd index -> Q (Section 5: "bit1->I, bit2->Q,..." 1-indexed == even/odd 0-indexed)
            if (i % 2 == 0) begin
                if (!(i_valid === 1'b1 && q_valid === 1'b0 && i_bit === bit_in)) begin
                    $display("FAIL idx=%0d expected I-valid, got i_valid=%b q_valid=%b i_bit=%b",
                              i, i_valid, q_valid, i_bit);
                    errors = errors + 1;
                end
            end else begin
                if (!(q_valid === 1'b1 && i_valid === 1'b0 && q_bit === bit_in)) begin
                    $display("FAIL idx=%0d expected Q-valid, got i_valid=%b q_valid=%b q_bit=%b",
                              i, i_valid, q_valid, q_bit);
                    errors = errors + 1;
                end
            end
        end

        if (errors == 0)
            $display("PASS: tb_demux_iq");
        else
            $display("FAIL: tb_demux_iq -- %0d mismatches", errors);
        $finish;
    end

endmodule
