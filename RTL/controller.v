`timescale 1ns/1ps

module controller #(
    parameter integer N_IN                = 3,    // 3 (1Mbps) / 6 (250kbps)
    parameter integer M                   = 4,    // 4 (1Mbps) / 32 (250kbps)
    parameter integer GROUP_SIZE          = 6,    // 6 (1Mbps) / 24 (250kbps)
    parameter integer PREAMBLE_TOTAL_BITS = 48,   // 48 (1Mbps) / 96 (250kbps)
    parameter integer NUM_SYMBOLS_WIDTH   = 12,
    parameter integer FIFO_DEPTH          = 256,
    parameter integer FIFO_AW             = 8     // $clog2(FIFO_DEPTH)
)(
    input  wire                          clk,
    input  wire                          reset,

    //  packet-level control 
    input  wire                          start_tx,              // 1-cycle pulse: begin a PPDU
    input  wire [6:0]                    payload_length, // payload length in bytes
    output wire [NUM_SYMBOLS_WIDTH-1:0]  num_symbols,        // total symbols for this packet
    output reg [6:0]                     payload_length_reg,
    //  to / from css_tx_frontend
    output wire                          fe_load,
    output wire                          fe_enable,
    input  wire [M-1:0]                  fe_i_codeword,
    input  wire                          fe_i_codeword_valid,
    input  wire [M-1:0]                  fe_q_codeword,
    input  wire                          fe_q_codeword_valid,
    input  wire                          fe_frame_done,
    input  wire [15:0]                   padded_total_bits,

    // to / from interleaver_ppdu_top
    output wire                          pf_start,
    output reg  [M-1:0]                  pf_i_codeword,
    output reg                           pf_i_codeword_valid,
    output reg  [M-1:0]                  pf_q_codeword,
    output reg                           pf_q_codeword_valid,
    output reg                           pf_last_codeword,
    input  wire                          pf_req_next_symbol,
    input  wire                          pf_i_bit,
    input  wire                          pf_q_bit,
    input  wire                          pf_chip_valid,

    // to / from tx_datapath_top 
    output wire                          dp_start,
    input  wire                          dp_symbol_req,
    output reg                           dp_i_bit,
    output reg                           dp_q_bit,
    output reg                           dp_qpsk_valid,

    //  status
    output reg                           fifo_overflow   // verification aid; should never assert
);

    localparam integer PHR_BITS = 12;

    wire [15:0] total_bits_now        = PHR_BITS + ({9'd0, payload_length} << 3);
    wire [15:0] remainder_now         = total_bits_now % GROUP_SIZE;
    wire [15:0] pad_bits_now          = GROUP_SIZE - remainder_now;
    wire [15:0] padded_total_bits_now = total_bits_now + pad_bits_now;

    wire [15:0] codeword_pairs  = padded_total_bits_now / (2*N_IN);
    wire [15:0] payload_chips   = codeword_pairs * M;
    wire [15:0] total_symbols   = PREAMBLE_TOTAL_BITS + payload_chips;

    assign num_symbols = total_symbols[NUM_SYMBOLS_WIDTH-1:0];

    assign fe_load  = start_tx;
    assign pf_start = start_tx;
    assign dp_start = start_tx;


    localparam integer CW_DEPTH = 4;

    reg [M-1:0] cw_i   [0:CW_DEPTH-1];
    reg [M-1:0] cw_q   [0:CW_DEPTH-1];
    reg         cw_last[0:CW_DEPTH-1];
    reg [2:0]   cw_wptr, cw_rptr, cw_count;

    wire cw_full  = (cw_count == CW_DEPTH);
    wire cw_empty = (cw_count == 3'd0);

    // Frontend advances only while there is room to accept what it makes,
    // and only while the packet is live and the frontend has not finished.
    reg fe_done_latched;
    assign fe_enable = !cw_full ;

    always @(posedge clk) begin
        if (reset)          fe_done_latched <= 1'b0;
        else if (start_tx)     fe_done_latched <= 1'b0;
        else if (fe_frame_done && fe_enable) fe_done_latched <= 1'b1;
    end


    reg [1:0]          chip_mem [0:FIFO_DEPTH-1];
    reg [FIFO_AW-1:0]  chip_wptr, chip_rptr;
    reg [FIFO_AW:0]    chip_count;

    wire chip_fifo_empty = (chip_count == 0);
    wire [FIFO_AW:0] chip_space = FIFO_DEPTH[FIFO_AW:0] - chip_count;

    // Release a codeword pair only when the FIFO can absorb the whole
    // codeword the p2s shifters will then emit back-to-back.
    wire chip_room_for_codeword = (chip_space > M);


    reg  pf_req_pending;


    reg [M-1:0] hold_i, hold_q;
    reg         have_i, have_q;
    reg         hold_last;

    wire i_avail = have_i || fe_i_codeword_valid;
    wire q_avail = have_q || fe_q_codeword_valid;

    wire [M-1:0] push_i = have_i ? hold_i : fe_i_codeword;
    wire [M-1:0] push_q = have_q ? hold_q : fe_q_codeword;
    wire         push_last = hold_last || fe_frame_done || fe_done_latched;

    wire cw_push = i_avail && q_avail && !cw_full;
    wire cw_pop  = pf_req_pending && !cw_empty && chip_room_for_codeword;

    always @(posedge clk) begin
        if (reset) begin
            have_i <= 1'b0; have_q <= 1'b0; hold_last <= 1'b0;
            hold_i <= {M{1'b0}}; hold_q <= {M{1'b0}};
            payload_length_reg <= 7'd0;
        end else if (start_tx) begin 
            have_i <= 1'b0; have_q <= 1'b0; hold_last <= 1'b0;
            hold_i <= {M{1'b0}}; hold_q <= {M{1'b0}};
            payload_length_reg <= payload_length;
        end else if (cw_push) begin
            have_i <= 1'b0; have_q <= 1'b0; hold_last <= 1'b0;
        end else begin
            if (fe_i_codeword_valid) begin hold_i <= fe_i_codeword; have_i <= 1'b1; end
            if (fe_q_codeword_valid) begin hold_q <= fe_q_codeword; have_q <= 1'b1; end
            if (fe_frame_done || fe_done_latched) hold_last <= 1'b1;
        end
    end

    always @(posedge clk) begin
        if (reset )         pf_req_pending <= 1'b0;
        else if (start_tx)  pf_req_pending <= 1'b0;
        else if (pf_req_next_symbol) pf_req_pending <= 1'b1;
        else if (cw_pop)             pf_req_pending <= 1'b0;
    end

    integer idx ;
    always @(posedge clk) begin
        if (reset) begin
            cw_wptr <= 3'd0;  cw_rptr <= 3'd0;  cw_count <= 3'd0;
            pf_i_codeword       <= {M{1'b0}};
            pf_q_codeword       <= {M{1'b0}};
            pf_i_codeword_valid <= 1'b0;
            pf_q_codeword_valid <= 1'b0;
            pf_last_codeword    <= 1'b0;
            for (idx = 0; idx < CW_DEPTH; idx = idx + 1) begin
                cw_i[idx]    <= {M{1'b0}};
                cw_q[idx]    <= {M{1'b0}};
                cw_last[idx] <= 1'b0;
            end
        end else if (start_tx) begin
            cw_wptr <= 3'd0;  cw_rptr <= 3'd0;  cw_count <= 3'd0;
            pf_i_codeword       <= {M{1'b0}};
            pf_q_codeword       <= {M{1'b0}};
            pf_i_codeword_valid <= 1'b0;
            pf_q_codeword_valid <= 1'b0;
            pf_last_codeword    <= 1'b0;
        end else begin
            pf_i_codeword_valid <= 1'b0;
            pf_q_codeword_valid <= 1'b0;

            if (cw_push) begin
                cw_i   [cw_wptr[1:0]] <= push_i;
                cw_q   [cw_wptr[1:0]] <= push_q;
                cw_last[cw_wptr[1:0]] <= push_last;
                cw_wptr <= cw_wptr + 3'd1;
            end

            if (cw_pop) begin
                pf_i_codeword       <= cw_i   [cw_rptr[1:0]];
                pf_q_codeword       <= cw_q   [cw_rptr[1:0]];
                pf_last_codeword    <= cw_last[cw_rptr[1:0]];
                pf_i_codeword_valid <= 1'b1;
                pf_q_codeword_valid <= 1'b1;
                cw_rptr <= cw_rptr + 3'd1;
            end

            case ({cw_push, cw_pop})
                2'b10:   cw_count <= cw_count + 3'd1;
                2'b01:   cw_count <= cw_count - 3'd1;
                default: cw_count <= cw_count;  // 00 and 11 leave it unchanged
            endcase
        end
    end

    wire chip_push = pf_chip_valid;
    wire chip_pop  = dp_symbol_req && !chip_fifo_empty;

    always @(posedge clk) begin
        if (reset) begin
            chip_wptr     <= {FIFO_AW{1'b0}};
            chip_rptr     <= {FIFO_AW{1'b0}};
            chip_count    <= {(FIFO_AW+1){1'b0}};
            dp_i_bit      <= 1'b0;
            dp_q_bit      <= 1'b0;
            dp_qpsk_valid <= 1'b0;
            fifo_overflow <= 1'b0;
        end else if (start_tx) begin
            chip_wptr     <= {FIFO_AW{1'b0}};
            chip_rptr     <= {FIFO_AW{1'b0}};
            chip_count    <= {(FIFO_AW+1){1'b0}};
            dp_i_bit      <= 1'b0;
            dp_q_bit      <= 1'b0;
            dp_qpsk_valid <= 1'b0;
            fifo_overflow <= 1'b0;
        end else begin
            dp_qpsk_valid <= 1'b0;

            if (chip_push && (chip_count == FIFO_DEPTH))
                fifo_overflow <= 1'b1;   // sticky; verification aid only

            if (chip_push && !chip_pop) begin
                chip_mem[chip_wptr] <= {pf_i_bit, pf_q_bit};
                chip_wptr  <= chip_wptr + 1'b1;
                chip_count <= chip_count + 1'b1;
            end else if (!chip_push && chip_pop) begin
                {dp_i_bit, dp_q_bit} <= chip_mem[chip_rptr];
                dp_qpsk_valid <= 1'b1;
                chip_rptr  <= chip_rptr + 1'b1;
                chip_count <= chip_count - 1'b1;
            end else if (chip_push && chip_pop) begin
                chip_mem[chip_wptr] <= {pf_i_bit, pf_q_bit};
                chip_wptr <= chip_wptr + 1'b1;
                {dp_i_bit, dp_q_bit} <= chip_mem[chip_rptr];
                dp_qpsk_valid <= 1'b1;
                chip_rptr <= chip_rptr + 1'b1;
                // count unchanged
            end
        end
    end

endmodule