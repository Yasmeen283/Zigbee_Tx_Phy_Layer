`timescale 1ns/1ps

module tb_interleaver_ppdu_top;

    // Configuration: 1Mbps mode (M=4, DATA_RATE=0)
    localparam M                   = 4;
    localparam DATA_RATE           = 1'b0;
    localparam PREAMBLE_TOTAL_BITS = 48;
    localparam CLK_PERIOD          = 10; // 100 MHz

    reg          clk;
    reg          reset;
    reg          start;
    reg  [M-1:0] i_codeword_in;
    reg          i_codeword_valid;
    reg  [M-1:0] q_codeword_in;
    reg          q_codeword_valid;
    reg          last_codeword;

    wire         req_next_symbol;
    wire         i_bit;
    wire         q_bit;
    wire         chip_valid;
    wire         frame_done;

    // DUT Instance
    interleaver_ppdu_top #(
        .M                  (M),
        .DATA_RATE          (DATA_RATE),
        .PREAMBLE_TOTAL_BITS(PREAMBLE_TOTAL_BITS)
    ) u_dut (
        .clk              (clk),
        .reset            (reset),
        .start            (start),
        .i_codeword_in    (i_codeword_in),
        .i_codeword_valid (i_codeword_valid),
        .q_codeword_in    (q_codeword_in),
        .q_codeword_valid (q_codeword_valid),
        .last_codeword    (last_codeword),
        .req_next_symbol  (req_next_symbol),
        .i_bit            (i_bit),
        .q_bit            (q_bit),
        .chip_valid       (chip_valid),
        .frame_done       (frame_done)
    );

    // Clock Generator
    always #(CLK_PERIOD/2) clk = ~clk;

    integer symbol_cnt;

    initial begin
        // Initialize Signals
        clk              = 0;
        reset            = 1;
        start            = 0;
        i_codeword_in    = 0;
        i_codeword_valid = 0;
        q_codeword_in    = 0;
        q_codeword_valid = 0;
        last_codeword    = 0;
        symbol_cnt       = 0;

        // Reset Sequence
        #(CLK_PERIOD * 4);
        reset = 0;
        #(CLK_PERIOD * 2);

        $display("--- Starting PPDU Transmission Test ---");
        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        // Dynamic Handshake Loop
        while (!frame_done) begin
            @(posedge clk);
            
            // Default valid signals low
            i_codeword_valid <= 1'b0;
            q_codeword_valid <= 1'b0;

            if (req_next_symbol) begin
                symbol_cnt = symbol_cnt + 1;
                $display("[TB @ %0t ps] Received req_next_symbol for Symbol #%0d", $time, symbol_cnt);

                if (DATA_RATE == 1'b0) begin
                    // 1Mbps: Supply 1 4-bit codeword pair per symbol request
                    i_codeword_in    <= me_val(symbol_cnt);
                    q_codeword_in    <= ~ me_val(symbol_cnt);
                    i_codeword_valid <= 1'b1;
                    q_codeword_valid <= 1'b1;

                    if (symbol_cnt == 4) begin
                        last_codeword <= 1'b1;
                        $display("[TB @ %0t ps] Asserted LAST codeword flag.", $time);
                    end
                end else begin
                    // 250kbps: Supply 2 consecutive 32-bit codewords per request
                    // Codeword N
                    i_codeword_in    <= 32'hA5A5A5A5;
                    q_codeword_in    <= 32'h5A5A5A5A;
                    i_codeword_valid <= 1'b1;
                    q_codeword_valid <= 1'b1;
                    @(posedge clk);
                    // Codeword N+1
                    i_codeword_in    <= 32'hFFFF0000;
                    q_codeword_in    <= 32'h0000FFFF;
                    i_codeword_valid <= 1'b1;
                    q_codeword_valid <= 1'b1;

                    if (symbol_cnt == 2) begin
                        last_codeword <= 1'b1;
                        $display("[TB @ %0t ps] Asserted LAST codeword flag.", $time);
                    end
                end
            end
        end

        $display("[TB @ %0t ps] Transmission Finished Successfully! (frame_done asserted)", $time);
        #(CLK_PERIOD * 5);
        $finish;
    end

    // Value Generator Helper Function for Test Data
    function [3:0] me_val; input integer idx;
        begin
            case (idx)
                1: me_val = 4'b1010;
                2: me_val = 4'b1100;
                3: me_val = 4'b0011;
                default: me_val = 4'b1111;
            endcase
        end
    endfunction

    // Monitor Output Serial Stream
    always @(posedge clk) begin
        if (chip_valid) begin
            $display("   [CHIP OUTPUT @ %0t ps] I = %b | Q = %b", $time, i_bit, q_bit);
        end
    end

endmodule