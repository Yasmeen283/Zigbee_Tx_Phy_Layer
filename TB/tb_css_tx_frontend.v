`timescale 1ns/1ps

module tb_css_tx_frontend;

    parameter DATA_WIDTH = 8;
    parameter ADDR_WIDTH = 7;

    // Memory File Paths - Adjust if necessary
    parameter MEMFILE_1M   = "../RTL/design1/vectors/symbol_mapper_1Mbps.mem";
    parameter MEMFILE_250K = "../RTL/design1/vectors/symbol_mapper_250kbps.mem";

    reg clk;
    reg reset;
    reg load_1m, load_250k;
    reg enable_1m, enable_250k;
    reg [6:0] payload_length_reg;
    reg [DATA_WIDTH-1:0] ram_memory [0:(1<<ADDR_WIDTH)-1];

    // DUT 1: 1 Mbps Mode (N=3, M=4, GROUP_SIZE=6)
    wire [ADDR_WIDTH-1:0] payload_rd_addr_1m;
    wire frame_done_1m;
    wire [3:0] i_codeword_1m, q_codeword_1m;
    wire i_valid_1m, q_valid_1m;

    // DUT 2: 250 kbps Mode (N=6, M=32, GROUP_SIZE=24)
    wire [ADDR_WIDTH-1:0] payload_rd_addr_250k;
    wire frame_done_250k;
    wire [31:0] i_codeword_250k, q_codeword_250k;
    wire i_valid_250k, q_valid_250k;

    // Output check trackers
    integer err_count_1m = 0;
    integer err_count_250k = 0;
    integer i_cnt_1m = 0, q_cnt_1m = 0;
    integer i_cnt_250k = 0, q_cnt_250k = 0;

    // Golden RAM Tables for Verification
    reg [3:0]  rom_1m   [0:7];
    reg [31:0] rom_250k [0:63];

    // Expected Golden Queues
    reg [3:0]  exp_i_cw_1m [0:255], exp_q_cw_1m [0:255];
    reg [31:0] exp_i_cw_250k [0:255], exp_q_cw_250k [0:255];
    integer total_words_1m = 0, total_words_250k = 0;

    // Load memory files and check for path errors
    task create_mem_files;
        begin
            $readmemb(MEMFILE_1M, rom_1m);
            $readmemb(MEMFILE_250K, rom_250k);

            // Diagnostic check for memory load failure
            if (rom_1m[0] === 4'bxxxx) begin
                $display("[ERROR] Failed to load 1Mbps MEM file from: %s", MEMFILE_1M);
            end
            if (rom_250k[0] === 32'bxxxx) begin
                $display("[ERROR] Failed to load 250kbps MEM file from: %s", MEMFILE_250K);
            end
        end
    endtask

    // Helper task to compute golden streams
    task generate_golden_data;
        input [6:0] p_len;
        input integer n_in;
        input integer group_size;
        input integer is_250k_mode;
        
        integer i, b, idx, bits_tot, padded_tot;
        reg [11:0] phr;
        reg stream [0:4095];
        reg [5:0] grp_i, grp_q;
        integer g_i_cnt, g_q_cnt;
        begin
            phr = {3'b000, 2'b00, p_len};
            bits_tot = 12 + (p_len * 8);
            padded_tot = bits_tot + ((group_size - (bits_tot % group_size)) % group_size);

            idx = 0;
            for (i = 0; i < 12; i = i + 1) begin
                stream[idx] = phr[i];
                idx = idx + 1;
            end
            for (i = 0; i < p_len; i = i + 1) begin
                for (b = 0; b < 8; b = b + 1) begin
                    stream[idx] = ram_memory[i][b];
                    idx = idx + 1;
                end
            end
            while (idx < padded_tot) begin
                stream[idx] = 1'b0;
                idx = idx + 1;
            end

            g_i_cnt = 0; g_q_cnt = 0;
            grp_i = 0; grp_q = 0;
            
            if (!is_250k_mode) begin
                total_words_1m = padded_tot / (2 * n_in);
                for (i = 0; i < padded_tot; i = i + 2) begin
                    grp_i[g_i_cnt % n_in] = stream[i];
                    grp_q[g_q_cnt % n_in] = stream[i+1];
                    g_i_cnt = g_i_cnt + 1;
                    g_q_cnt = g_q_cnt + 1;

                    if (g_i_cnt % n_in == 0) begin
                        exp_i_cw_1m[(g_i_cnt/n_in)-1] = rom_1m[grp_i[2:0]];
                        exp_q_cw_1m[(g_q_cnt/n_in)-1] = rom_1m[grp_q[2:0]];
                        grp_i = 0; grp_q = 0;
                    end
                end
            end else begin
                total_words_250k = padded_tot / (2 * n_in);
                for (i = 0; i < padded_tot; i = i + 2) begin
                    grp_i[g_i_cnt % n_in] = stream[i];
                    grp_q[g_q_cnt % n_in] = stream[i+1];
                    g_i_cnt = g_i_cnt + 1;
                    g_q_cnt = g_q_cnt + 1;

                    if (g_i_cnt % n_in == 0) begin
                        exp_i_cw_250k[(g_i_cnt/n_in)-1] = rom_250k[grp_i[5:0]];
                        exp_q_cw_250k[(g_q_cnt/n_in)-1] = rom_250k[grp_q[5:0]];
                        grp_i = 0; grp_q = 0;
                    end
                end
            end
        end
    endtask

    // DUT 1: 1 Mbps Instance
    css_tx_frontend #(
        .GROUP_SIZE(6), .N_IN(3), .M_OUT(4),
        .MEMFILE_I(MEMFILE_1M), .MEMFILE_Q(MEMFILE_1M)
    ) uut_1m (
        .clk(clk), .reset(reset), .load(load_1m), .enable(enable_1m),
        .payload_length_reg(payload_length_reg),
        .payload_rd_data(ram_memory[payload_rd_addr_1m]),
        .payload_rd_addr(payload_rd_addr_1m),
        .frame_done(frame_done_1m),
        .i_codeword(i_codeword_1m), .i_codeword_valid(i_valid_1m),
        .q_codeword(q_codeword_1m), .q_codeword_valid(q_valid_1m)
    );

    // DUT 2: 250 kbps Instance
    css_tx_frontend #(
        .GROUP_SIZE(24), .N_IN(6), .M_OUT(32),
        .MEMFILE_I(MEMFILE_250K), .MEMFILE_Q(MEMFILE_250K)
    ) uut_250k (
        .clk(clk), .reset(reset), .load(load_250k), .enable(enable_250k),
        .payload_length_reg(payload_length_reg),
        .payload_rd_data(ram_memory[payload_rd_addr_250k]),
        .payload_rd_addr(payload_rd_addr_250k),
        .frame_done(frame_done_250k),
        .i_codeword(i_codeword_250k), .i_codeword_valid(i_valid_250k),
        .q_codeword(q_codeword_250k), .q_codeword_valid(q_valid_250k)
    );

    // Clock Generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Self-checking monitors
    always @(posedge clk) begin
        if (i_valid_1m) begin
            if (i_codeword_1m !== exp_i_cw_1m[i_cnt_1m]) begin
                $display("[FAIL 1M I] Index %0d | Exp: %b | Got: %b", i_cnt_1m, exp_i_cw_1m[i_cnt_1m], i_codeword_1m);
                err_count_1m = err_count_1m + 1;
            end
            i_cnt_1m = i_cnt_1m + 1;
        end
        if (q_valid_1m) begin
            if (q_codeword_1m !== exp_q_cw_1m[q_cnt_1m]) begin
                $display("[FAIL 1M Q] Index %0d | Exp: %b | Got: %b", q_cnt_1m, exp_q_cw_1m[q_cnt_1m], q_codeword_1m);
                err_count_1m = err_count_1m + 1;
            end
            q_cnt_1m = q_cnt_1m + 1;
        end

        if (i_valid_250k) begin
            if (i_codeword_250k !== exp_i_cw_250k[i_cnt_250k]) begin
                $display("[FAIL 250K I] Index %0d | Exp: %b | Got: %b", i_cnt_250k, exp_i_cw_250k[i_cnt_250k], i_codeword_250k);
                err_count_250k = err_count_250k + 1;
            end
            i_cnt_250k = i_cnt_250k + 1;
        end
        if (q_valid_250k) begin
            if (q_codeword_250k !== exp_q_cw_250k[q_cnt_250k]) begin
                $display("[FAIL 250K Q] Index %0d | Exp: %b | Got: %b", q_cnt_250k, exp_q_cw_250k[q_cnt_250k], q_codeword_250k);
                err_count_250k = err_count_250k + 1;
            end
            q_cnt_250k = q_cnt_250k + 1;
        end
    end

    // Stimulus Execution
    initial begin
        create_mem_files();

        ram_memory[0] = 8'hA5;
        ram_memory[1] = 8'h3C;
        ram_memory[2] = 8'hF0;
        ram_memory[3] = 8'h54;

        reset = 1'b1;
        load_1m = 1'b0;   enable_1m = 1'b0;
        load_250k = 1'b0; enable_250k = 1'b0;

        // ---------------------------------------------------------------------
        // Test Case 1: 1 Mbps Mode (N=3, M=4)
        // ---------------------------------------------------------------------
        payload_length_reg = 7'd4;
        generate_golden_data(7'd4, 3, 6, 0);
        
        #20; @(posedge clk); reset = 1'b0;
        @(posedge clk); load_1m = 1'b1;
        @(posedge clk); load_1m = 1'b0; enable_1m = 1'b1;

        wait(frame_done_1m);
        repeat(5) @(posedge clk);
        enable_1m = 1'b0;

        // ---------------------------------------------------------------------
        // Test Case 2: 250 kbps Mode (N=6, M=32)
        // ---------------------------------------------------------------------
        payload_length_reg = 7'd3;  // Correct payload length for Test Case 2
        i_cnt_250k = 0; q_cnt_250k = 0; // Reset index trackers
        generate_golden_data(7'd3, 6, 24, 1);
        
        #20; @(posedge clk); reset = 1'b1;
        #20; @(posedge clk); reset = 1'b0;
        @(posedge clk); load_250k = 1'b1;
        @(posedge clk); load_250k = 1'b0; enable_250k = 1'b1;

        wait(frame_done_250k);
        repeat(5) @(posedge clk);
        enable_250k = 1'b0;

        $display("\n=======================================================");
        $display("                 FRONTEND TEST REPORT                  ");
        $display("=======================================================");
        $display(" Mode 1 (1 Mbps, N=3, M=4):");
        $display("   I/Q Words Checked: %0d / %0d", i_cnt_1m, total_words_1m);
        $display("   Errors Found     : %0d", err_count_1m);
        $display(" Mode 2 (250 kbps, N=6, M=32):");
        $display("   I/Q Words Checked: %0d / %0d", i_cnt_250k, total_words_250k);
        $display("   Errors Found     : %0d", err_count_250k);
        $display("=======================================================");

        if (err_count_1m == 0 && err_count_250k == 0 && i_cnt_1m == total_words_1m && i_cnt_250k == total_words_250k)
            $display(" OVERALL STATUS     : PASSED SUCCESS\n");
        else
            $display(" OVERALL STATUS     : FAILED ERROR\n");

        $finish;
    end

endmodule