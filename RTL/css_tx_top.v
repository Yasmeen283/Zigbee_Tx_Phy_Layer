//=============================================================================
// css_tx_top.v
//
// Top-level CSS PHY transmitter 

 
//
// Additional signals (beyond Table 17, but explicitly allowed by the spec
// -- "you may add internal signals as needed"): a simple write port for the
// MAC layer to fill the 127x8 payload RAM before asserting start_Tx (per
// the reference architecture: "MAC layer fills the payload RAM with
// payload data" then "sends start_Tx"), and a tx_valid strobe that is high
// for every cycle Tx_real/Tx_imag carries a genuine modulated sample
// (useful for simulation/ChipScope capture; a real DAC would just sample
// every clock).
//
// ---------------------------------------------------------------------------
// SCOPE: this integration implements the 1 Mbps data path in full (the
// project spec explicitly allows "a single-rate implementation ... as an
// acceptable reduced-scope option"). chirpIndex is fixed to the project
// default (m=1, simulationParameters.m) via the CHIRP_MEMFILE parameter.
// The Interleaver block (interleaver.v) is verified standalone and is the
// only extra block a 250 kbps extension of this controller would need to
// instantiate between the Symbol Mapper and the QPSK Mapper.
// ---------------------------------------------------------------------------
//
// DATAPATH / TIMING SUMMARY (matches Section 13 "worked example" of the
// deep-dive doc for payloadLength=25):
//   total_bits         = 12 (PHR) + 8*PayloadLength
//   pad_bits           = zero_padding() -> multiple of 6
//   n_codewords/path   = padded_total_bits / 6      (36 for the example)
//   n_groups           = 12 (preamble+SFD groups)  + n_codewords/path
//                         (12 = 48 preamble/SFD chips / 4)
//   total_symbols      = 4 * n_groups
//   total_Tx_samples   = sum over all groups of (152 + gap), gap alternating
//                         TEVEN/TODD by group parity (9216 for the example)
//
// Per group of 4 QPSK/DQPSK symbols:
//   phase 0..3  : present symbol i to qpsk_mapper -> dqpsk_encoder,
//                 capture S(n) into s_reg[i] one cycle later
//   phase 4     : capture S(3), no new symbol
//   SUBCHIRP    : addr 0..151 into chirp_rom, modulate with s_reg[addr/38]
//   GAP         : TEVEN (even group_idx) or TODD (odd group_idx) idle cycles
//=============================================================================

module css_tx_top #(
    parameter integer TEVEN           = 10,   // chirpIndex=1 (Table 15 of ref. doc)
    parameter integer TODD            = 70,
    parameter         SYMROM_1MBPS    = "vectors/symbol_mapper_1mbps.mem",
    parameter         PREAMBLE_MEMFILE= "vectors/preamble_sfd_1mbps.mem",
    parameter         CHIRP_MEMFILE   = "vectors/chirp_m1.mem" ,
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 7 
) (
    input  wire        clk,                               //system clock
    input  wire        reset,                            //system reset

    input  wire        start_Tx,                       //MAC -> PHY: begin transmission
    input  wire [6:0]  PayloadLength,                 //payload length in bytes (0..127)

    // payload RAM write port (MAC fills this before start_Tx; see header)
    input  wire                   payload_wr_en,
    input  wire [ADDR_WIDTH-1:0]  payload_wr_addr,   // byte index 0..126
    input  wire [DATA_WIDTH-1:0]  payload_wr_data,

    output reg               done_Tx,           //PHY -> MAC: transmission finished (1-cycle pulse)
    output reg  signed [7:0] Tx_real,          //real part of the CSS/DQCSK sample stream
    output reg  signed [7:0] Tx_imag         //imaginary part of the CSS/DQCSK sample stream
    // output reg         tx_valid              // extra: 1 while Tx_real/Tx_imag carry a real sample
);

    // ---------------------------------------------------------------------
    // Payload RAM (127 bytes x 8 bits) -- simple write port from the MAC
    // ---------------------------------------------------------------------
    wire [DATA_WIDTH-1:0] payload_rd_data ;
    wire [ADDR_WIDTH-1:0] payload_rd_addr ;

    payload_ram #(.DATA_WIDTH(DATA_WIDTH),.ADDR_WIDTH(ADDR_WIDTH)) (
        .we(payload_wr_en),
        .waddr(payload_wr_addr),
        .din(payload_wr_data),

        .raddr(payload_rd_addr), 
        .dout(payload_rd_data) 
    );

    // ---------------------------------------------------------------------
    // Length / padding arithmetic (Block 1 -- zero_padding.v reused for the
    // pure length calculation; the per-bit gating + I/Q demuxing needed for
    // simultaneous 6-bit-group access below is done with the equivalent
    // combinational function raw_bit()/padded_bit(), since symbol_mapper
    // needs 6 padded-stream bits available in the same cycle).
    // ---------------------------------------------------------------------
    wire  [6:0]  payload_length_reg;
    wire load_zero_padding ;
    wire enable_zero_padding ;

    wire [4:0]  pad_bits;
    wire [15:0] padded_total_bits;
    wire [15:0] bit_index ;
    wire bit_out_zero_padding ;
    wire frame_done ;

    zero_padding #(.GROUP_SIZE(GROUP_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH) ) u_zero_padding (
        .clk(clk),
        .reset(reset),
        .load(load_zero_padding),
        .enable(enable_zero_padding),
        .payload_length_reg(payload_length_reg),
        .pad_bits(pad_bits),
        .padded_total_bits(padded_total_bits),
        .payload_rd_data(payload_rd_data),
        .payload_rd_addr(payload_rd_addr),
        .bit_index(bit_index),
        .bit_out(bit_out),
        .frame_done(frame_done)
    );


    // ---------------------------------------------------------------------
    // IQ Demux
    //---------------------------------------------------------------------
    wire i_bit , q_bit ;
    wire i_valid , q_valid ;
    demux_iq u_demux_iq (
        .bit_in(bit_out_zero_padding),
        .sel(bit_index[0]),
        .i_bit(i_bit),
        .q_bit(q_bit),
        .i_valid(i_valid),
        .q_valid(q_valid)
    );

    // ---------------------------------------------------------------------
    // serial to parallel   
    //---------------------------------------------------------------------
        parameter N = 3 ; //3 ror 1M , 6 for 250k
        wire [N-1:0] i_symbol , q_symbol ;
        wire i_symbol_valid , q_symbol_valid ;

        // Instantiate I-Path Serial to Parallel (N = 3 or 6)
        serial_to_parallel #(.N(N)) s2p_i (
            .clk       (clk),
            .reset     (reset),
            .start     (load_zero_padding),
            .valid_in  (enable_zero_padding && i_valid),
            .bit_in    (i_bit),
            .data_out  (i_symbol),
            .valid_out (i_symbol_valid)
        );

        // Instantiate Q-Path Serial to Parallel (N = 3 or 6)
        serial_to_parallel #(.N(N)) s2p_q (
            .clk       (clk),
            .reset     (reset),
            .start     (load_zero_padding),
            .valid_in  (enable_zero_padding && q_valid),
            .bit_in    (q_bit),
            .data_out  (q_symbol),
            .valid_out (q_symbol_valid)
        );
   
    // ---------------------------------------------------------------------
    // symbol mapper   
    //---------------------------------------------------------------------
    parameter M = 4 ; //4 for 1M ,32 for 250k
    wire i_codeword_valid , q_codeword_valid ;
    wire [M-1:0] i_codeword , q_codeword ;

    symbol_mapper #( .N_IN(N), .M_OUT(M), .MEMFILE(SYMROM_1MBPS) )
        u_symmap_I (.clk(clk), 
                    .group_in(i_symbol) , 
                    .group_valid(i_symbol_valid), 
                    .codeword_out(i_codeword) ,
                    .codeword_valid(i_codeword_valid));

    symbol_mapper #( .N_IN(N), .M_OUT(M), .MEMFILE(SYMROM_1MBPS) )
        u_symmap_Q (.clk(clk), 
                    .group_in(q_symbol) , 
                    .group_valid(q_symbol_valid), 
                    .codeword_out(q_codeword) ,
                    .codeword_valid(q_codeword_valid));
  

    preamble_sfd_rom #( .TOTAL_BITS(48), .MEMFILE(PREAMBLE_MEMFILE) )
        u_preamble_sfd ( .addr(preamble_addr), .bit_out(pre_bit) );
    wire i_bit = in_preamble ? pre_bit : codeword_I[3 - phase[1:0]];
    wire q_bit = in_preamble ? pre_bit : codeword_Q[3 - phase[1:0]];

    wire signed [1:0] x_real, x_imag;
    qpsk_mapper u_qpsk_mapper ( .i_bit(i_bit), .q_bit(q_bit),
                                 .qpsk_real(x_real), .qpsk_imag(x_imag) );

    // ---- DQPSK encoder (continuous across the whole packet) ---------------
    wire signed [1:0] s_real, s_imag;
    // Combinational, not registered: must land on the IDLE->GEN edge itself
    // (present while state==S_IDLE && start_Tx, i.e. the cycle *before* the
    // edge that moves to S_GEN/phase=0) so symbol 0 of the new packet is
    // consumed by the encoder's multiply, not swallowed by its reset.
    wire              dqpsk_reset  = reset || ((state == S_IDLE) && start_Tx);
    wire              symbol_valid = (state == S_GEN) && (phase < 3'd4);

    dqpsk_encoder u_dqpsk (
        .clk(clk), .reset(dqpsk_reset), .symbol_valid(symbol_valid),
        .x_real(x_real), .x_imag(x_imag),
        .s_real(s_real), .s_imag(s_imag)
    );

    reg signed [1:0] s_reg_real [0:3];
    reg signed [1:0] s_reg_imag [0:3];

    // ---- chirp ROM + modulator ---------------------------------------------
    wire signed [5:0] chirp_real, chirp_imag;
    chirp_rom #( .SAMPLES(152), .MEMFILE(CHIRP_MEMFILE) )
        u_chirp_rom ( .addr(chirp_addr), .chirp_real(chirp_real), .chirp_imag(chirp_imag) );

    // subchirp index k = chirp_addr / 38, via comparators (avoids a divider)
    wire [1:0] subchirp_k = (chirp_addr < 8'd38)  ? 2'd0 :
                             (chirp_addr < 8'd76)  ? 2'd1 :
                             (chirp_addr < 8'd114) ? 2'd2 : 2'd3;

    wire signed [7:0] mod_real, mod_imag;
    css_modulator u_modulator (
        .s_real(s_reg_real[subchirp_k]), .s_imag(s_reg_imag[subchirp_k]),
        .chirp_real(chirp_real), .chirp_imag(chirp_imag),
        .tx_real(mod_real), .tx_imag(mod_imag)
    );

    wire [7:0] gap_len = group_idx[0] ? TODD[7:0] : TEVEN[7:0];

    integer i;

    always @(posedge clk) begin
        if (reset) begin
            state              <= S_IDLE;
            done_Tx            <= 1'b0;
            Tx_real            <= 8'sd0;
            Tx_imag            <= 8'sd0;
            tx_valid           <= 1'b0;
            group_idx          <= 16'd0;
            phase              <= 3'd0;
            chirp_addr         <= 8'd0;
            gap_cnt            <= 8'd0;
            payload_length_reg <= 8'd0;
            for (i = 0; i < 4; i = i + 1) begin
                s_reg_real[i] <= 2'sd0;
                s_reg_imag[i] <= 2'sd0;
            end
        end else begin
            done_Tx     <= 1'b0;
            tx_valid    <= 1'b0;

            case (state)
                // -------------------------------------------------------
                S_IDLE: begin
                    if (start_Tx) begin
                        payload_length_reg <= PayloadLength;
                        group_idx          <= 16'd0;
                        phase              <= 3'd0;
                        state              <= S_GEN;   // dqpsk_reset (comb.) is already
                                                        // high this cycle -- S(-4)..S(-1)=1+j1
                    end
                end

                // -------------------------------------------------------
                S_GEN: begin
                    if (phase >= 3'd1)
                        begin
                            s_reg_real[phase - 3'd1] <= s_real;
                            s_reg_imag[phase - 3'd1] <= s_imag;
                        end
                    if (phase < 3'd4)
                        phase <= phase + 3'd1;
                    else begin
                        phase      <= 3'd0;
                        chirp_addr <= 8'd0;
                        state      <= S_SUBCHIRP;
                    end
                end

                // -------------------------------------------------------
                S_SUBCHIRP: begin
                    Tx_real    <= mod_real;
                    Tx_imag    <= mod_imag;
                    tx_valid   <= 1'b1;
                    if (chirp_addr == 8'd151) begin
                        chirp_addr <= 8'd0;
                        gap_cnt    <= 8'd0;
                        state      <= S_GAP;
                    end else
                        chirp_addr <= chirp_addr + 8'd1;
                end

                // -------------------------------------------------------
                S_GAP: begin
                    Tx_real  <= 8'sd0;
                    Tx_imag  <= 8'sd0;
                    tx_valid <= 1'b0;
                    if (gap_cnt == gap_len - 8'd1)
                        state <= S_NEXTGRP;
                    else
                        gap_cnt <= gap_cnt + 8'd1;
                end

                // -------------------------------------------------------
                S_NEXTGRP: begin
                    if (group_idx == n_groups - 16'd1) begin
                        state <= S_DONE;
                    end else begin
                        group_idx <= group_idx + 16'd1;
                        phase     <= 3'd0;
                        state     <= S_GEN;
                    end
                end

                // -------------------------------------------------------
                S_DONE: begin
                    done_Tx <= 1'b1;
                    state   <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
