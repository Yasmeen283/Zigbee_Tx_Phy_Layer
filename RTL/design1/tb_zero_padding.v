`timescale 1ns/1ps

module tb_zero_padding;

    reg  [15:0] total_bits;
    wire [4:0]  pad_bits;
    wire [15:0] padded_total_bits;
    reg  [15:0] bit_index;
    reg         payload_bit_in;
    wire        bit_out;

    integer errors;

    zero_padding #( .GROUP_SIZE(6) ) dut (
        .total_bits         (total_bits),
        .pad_bits           (pad_bits),
        .padded_total_bits  (padded_total_bits),
        .bit_index          (bit_index),
        .payload_bit_in     (payload_bit_in),
        .bit_out            (bit_out)
    );

    task check_len;
        input [15:0] tb_in;
        input [4:0]  exp_pad;
        input [15:0] exp_padded;
        begin
            total_bits = tb_in; #1;
            if (pad_bits !== exp_pad || padded_total_bits !== exp_padded) begin
                $display("FAIL len: total_bits=%0d pad=%0d(exp %0d) padded=%0d(exp %0d)",
                          tb_in, pad_bits, exp_pad, padded_total_bits, exp_padded);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;

        // worked example from the deep-dive doc: 25-byte payload, 1 Mbps
        //   200 (PSDU) + 12 (PHR) = 212 -> pad 4 -> 216
        check_len(16'd212, 5'd4, 16'd216);

        // already a multiple of 6 -> no padding
        check_len(16'd216, 5'd0, 16'd216);

        // smallest case
        check_len(16'd1,   5'd5, 16'd6);
        check_len(16'd0,   5'd0, 16'd0);

        // max payload (127 bytes): 127*8+12 = 1028 ; 1028 mod 6 = 2 -> pad 4 -> 1032
        check_len(16'd1028, 5'd4, 16'd1032);

        // ---- bit gate: inside range passes through, outside range is 0 ----
        total_bits = 16'd212;
        payload_bit_in = 1'b1;
        bit_index = 16'd0;   #1;
        if (bit_out !== 1'b1) begin $display("FAIL gate: bit_index=0 inside range should pass through"); errors = errors + 1; end

        bit_index = 16'd211; #1;
        if (bit_out !== 1'b1) begin $display("FAIL gate: bit_index=211 (last real bit) should pass through"); errors = errors + 1; end

        bit_index = 16'd212; #1;
        if (bit_out !== 1'b0) begin $display("FAIL gate: bit_index=212 (first padding bit) should be 0"); errors = errors + 1; end

        bit_index = 16'd215; #1;
        if (bit_out !== 1'b0) begin $display("FAIL gate: bit_index=215 (last padding bit) should be 0"); errors = errors + 1; end

        payload_bit_in = 1'b0;
        bit_index = 16'd100; #1;
        if (bit_out !== 1'b0) begin $display("FAIL gate: bit_index=100, payload_bit_in=0, should read 0"); errors = errors + 1; end

        if (errors == 0)
            $display("PASS: tb_zero_padding");
        else
            $display("FAIL: tb_zero_padding -- %0d mismatches", errors);
        $finish;
    end

endmodule
