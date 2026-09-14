`timescale 1ns / 1ps

module tb_zero_padding;

    // Parameters
    parameter GROUP_SIZE = 6;
    parameter DATA_WIDTH = 8;
    parameter ADDR_WIDTH = 7;

    // DUT Inputs
    reg clk;
    reg reset;
    reg load;
    reg enable;
    reg [6:0] payload_length_reg;
    reg [DATA_WIDTH-1:0] payload_rd_data;

    // DUT Outputs
    wire [4:0] pad_bits;
    wire [15:0] padded_total_bits;
    wire [ADDR_WIDTH-1:0] payload_rd_addr;
    wire [15:0] bit_index;
    wire bit_out;
    wire frame_done;

    // Simulated RAM for payload data
    reg [DATA_WIDTH-1:0] ram_memory [0:(1<<ADDR_WIDTH)-1];

    // Self-checking variables
    reg [15:0] expected_padded_total_bits;
    reg [15:0] expected_total_bits;
    reg expected_stream [0:2047]; 
    integer check_idx = 0;
    integer err_count = 0;
    reg data_valid;       // Tracks the 1-cycle latency of bit_out

    // Instantiate the Unit Under Test (UUT)
    zero_padding #(
        .GROUP_SIZE(GROUP_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) uut (
        .clk(clk),
        .reset(reset),
        .load(load),
        .enable(enable),
        .payload_length_reg(payload_length_reg),
        .pad_bits(pad_bits),
        .padded_total_bits(padded_total_bits),
        .payload_rd_data(payload_rd_data),
        .payload_rd_addr(payload_rd_addr),
        .bit_index(bit_index),
        .bit_out(bit_out),
        .frame_done(frame_done)
    );

    // Clock generation (100MHz / 10ns period)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // RAM read logic (combinational read)
    always @(*) begin
        payload_rd_data = ram_memory[payload_rd_addr];
    end

    // Task to generate the expected output sequence
    task generate_expected;
        input [6:0] p_len;
        integer i, b, idx;
        reg [11:0] phr;
        begin
            // 1. Calculate bit counts
            expected_total_bits = 12 + (p_len * 8);
            expected_padded_total_bits = expected_total_bits + ((GROUP_SIZE - (expected_total_bits % GROUP_SIZE)) % GROUP_SIZE);
            phr = {3'b000, 2'b00, p_len};
            idx = 0;
            
            // 2. Populate PHY Header (12 bits)
            for (i = 0; i < 12; i = i + 1) begin
                expected_stream[idx] = phr[i];
                idx = idx + 1;
            end
            
            // 3. Populate PSDU Payload (p_len bytes)
            for (i = 0; i < p_len; i = i + 1) begin
                for (b = 0; b < 8; b = b + 1) begin
                    expected_stream[idx] = ram_memory[i][b];
                    idx = idx + 1;
                end
            end
            
            // 4. Populate Padding Bits (Zeroes)
            while (idx < expected_padded_total_bits) begin
                expected_stream[idx] = 1'b0;
                idx = idx + 1;
            end
        end
    endtask

    // DUT Valid output tracker
    // The DUT updates payload_bit_in synchronously when enable is high and it's not IDLE.
    // Therefore, bit_out is valid exactly 1 cycle later.
    always @(posedge clk) begin
        if (reset)
            data_valid <= 1'b0;
        else if (enable && (uut.state != 2'b00)) 
            data_valid <= 1'b1;
        else
            data_valid <= 1'b0;
    end

    // Self-checking block
    always @(posedge clk) begin
        if (data_valid) begin
            if (bit_out !== expected_stream[check_idx]) begin
                $display("[FAIL] Time: %0t | Index: %4d | Expected: %b | Got: %b", 
                         $time, check_idx, expected_stream[check_idx], bit_out);
                err_count = err_count + 1;
            end
            check_idx = check_idx + 1;
        end
    end

    // Stimulus
    initial begin
        // Initialize Signals
        reset = 1'b1;
        load = 1'b0;
        enable = 1'b0;
        payload_length_reg = 7'd4; // 4 bytes payload to test padding logic properly
        
        // Initialize RAM with test data
        ram_memory[0] = 8'hA5; // 10100101
        ram_memory[1] = 8'h3C; // 00111100
        ram_memory[2] = 8'hF0; // 11110000 
        ram_memory[3] = 8'h45;
        
        // Generate expected golden data
        generate_expected(payload_length_reg);

        // Reset sequence
        #20;
        @(posedge clk);
        reset = 1'b0;

        // Trigger Load
        @(posedge clk);
        load = 1'b1;
        
        // Start shifting bits
        @(posedge clk);
        load = 1'b0;
        enable = 1'b1;

        // Wait for the frame to finish from the DUT
        wait(frame_done == 1'b1);
        
        // Let it run a few more cycles to clock out the final bit and return to IDLE
        repeat(2) @(posedge clk);
        enable = 1'b0;

        // Final Report
        $display("\n==================================================");
        $display("               SIMULATION COMPLETE                ");
        $display("==================================================");
        $display(" Total Bits Checked : %0d", check_idx);
        $display(" Expected Bits      : %0d", expected_padded_total_bits);
        $display(" Errors Found       : %0d", err_count);
        
        if (err_count == 0 && check_idx == expected_padded_total_bits) begin
            $display(" STATUS             : PASSED SUCCESS \n");
        end else begin
            $display(" STATUS             : FAILED ERROR \n");
        end
        $display("==================================================");

        $finish;
    end

endmodule