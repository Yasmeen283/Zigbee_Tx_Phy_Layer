
module css_tx_frontend #(
    parameter GROUP_SIZE = 6,                             // 6 for 1Mbps, 24 for 250kbps
    parameter N_IN       = 3,                             // 3 for 1Mbps, 6 for 250kbps
    parameter M_OUT      = 4,                             // 4 for 1Mbps, 32 for 250kbps
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 7
) (
    input  wire                 clk,
    input  wire                 reset,
    input  wire                 load,
    input  wire                 enable,
    input  wire [6:0]           payload_length_reg,
    input  wire [DATA_WIDTH-1:0] payload_rd_data,
    
    output wire [ADDR_WIDTH-1:0] payload_rd_addr,
    output wire                 frame_done,
    
    // Symbol Mapper Outputs
    output wire [M_OUT-1:0]     i_codeword,
    output wire                 i_codeword_valid,
    output wire [M_OUT-1:0]     q_codeword,
    output wire                 q_codeword_valid,
    output wire [15:0]          padded_total_bits
);

    // 1. Zero Padding Block
    wire [15:0] zp_bit_index;
    wire        zp_bit_out;
    wire [4:0]  pad_bits;
    
    
    zero_padding #(
        .GROUP_SIZE(GROUP_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_zero_padding (
        .clk                (clk),
        .reset              (reset),
        .load               (load),
        .enable             (enable),
        .payload_length_reg (payload_length_reg),
        .pad_bits           (pad_bits),
        .padded_total_bits  (padded_total_bits),
        .payload_rd_data    (payload_rd_data),
        .payload_rd_addr    (payload_rd_addr),
        .bit_index          (zp_bit_index),
        .bit_out            (zp_bit_out),
        .frame_done         (frame_done)
    );

    // Pipeline Alignment Logic:
    // Align bit_index[0] and enable with payload_bit_in 1-cycle register delay
    reg sel_d;
    reg valid_d;

    always @(posedge clk) begin
        if (reset) begin
            sel_d   <= 1'b0;
            valid_d <= 1'b0;
        end else begin
            sel_d   <= zp_bit_index[0];
            valid_d <= enable && (u_zero_padding.state != 2'b00);
        end
    end

    // 2. Demux I/Q Block
    wire i_bit, q_bit;
    wire i_valid_raw, q_valid_raw;

    demux_iq u_demux_iq (
        .bit_in  (zp_bit_out),
        .sel     (sel_d),
        .i_bit   (i_bit),
        .q_bit   (q_bit),
        .i_valid (i_valid_raw),
        .q_valid (q_valid_raw)
    );

    wire i_valid = valid_d && i_valid_raw;
    wire q_valid = valid_d && q_valid_raw;

    // 3. Serial to Parallel Blocks (I & Q Paths)
    wire [N_IN-1:0] i_group, q_group;
    wire            i_group_valid, q_group_valid;

    serial_to_parallel #(.N(N_IN)) u_s2p_i (
        .clk       (clk),
        .reset     (reset),
        .start     (load),
        .valid_in  (i_valid),
        .bit_in    (i_bit),
        .data_out  (i_group),
        .valid_out (i_group_valid)
    );

    serial_to_parallel #(.N(N_IN)) u_s2p_q (
        .clk       (clk),
        .reset     (reset),
        .start     (load),
        .valid_in  (q_valid),
        .bit_in    (q_bit),
        .data_out  (q_group),
        .valid_out (q_group_valid)
    );

    // 4. Symbol Mapper Blocks (I & Q Paths)
    symbol_mapper #(
        .N_IN     (N_IN),
        .M_OUT    (M_OUT)
    ) u_mapper_i (
        .clk            (clk),
        .group_in       (i_group),
        .group_valid    (i_group_valid),
        .codeword_out   (i_codeword),
        .codeword_valid (i_codeword_valid)
    );

    symbol_mapper #(
        .N_IN     (N_IN),
        .M_OUT    (M_OUT)
    ) u_mapper_q (
        .clk            (clk),
        .group_in       (q_group),
        .group_valid    (q_group_valid),
        .codeword_out   (q_codeword),
        .codeword_valid (q_codeword_valid)
    );

endmodule