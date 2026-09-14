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
    output reg  signed [7:0] Tx_imag,         //imaginary part of the CSS/DQCSK sample stream
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
    wire  [7:0]  payload_length_reg;
    


    // wire [4:0]  pad_bits;
    wire [15:0] padded_total_bits;

    zero_padding #( .GROUP_SIZE(6) ) u_zero_padding (
        .total_bits         (total_bits),
        // .pad_bits           (pad_bits),
        .padded_total_bits  (padded_total_bits),
        .bit_index          (16'd0),
        .payload_bit_in     (1'b0),
        .bit_out            ()
    );

    wire [15:0] n_codewords_per_path = padded_total_bits / 16'd6;  // exact: padded_total_bits is a mult of 6
    wire [15:0] n_groups             = 16'd12 + n_codewords_per_path; // 12 preamble/SFD groups + payload groups

    // ---------------------------------------------------------------------
    // raw_bit(idx): the true (pre-padding) PHR+PSDU bit at position idx
    //   idx 0..6   -> PayloadLength[6:0], MSB first (Table 6/11: bits 0-6)
    //   idx 7..11  -> 0 (not-used + reserved)
    //   idx >=12   -> PSDU bit (idx-12), MSB-first within each byte
    // padded_bit(idx): raw_bit(idx) if idx<total_bits, else 0 (zero_padding.v
    // bit-gate, replicated here for combinational multi-bit access)
    // ---------------------------------------------------------------------
    function raw_bit;
        input [15:0] idx;
        reg   [15:0] psdu_idx;
        reg   [6:0]  byte_idx;
        reg   [2:0]  bit_in_byte;
        begin
            if (idx < 7)
                raw_bit = payload_length_reg[6 - idx[2:0]];
            else if (idx < 12)
                raw_bit = 1'b0;
            else begin
                psdu_idx    = idx - 16'd12;
                byte_idx    = psdu_idx[9:3];
                bit_in_byte = 3'd7 - psdu_idx[2:0];
                raw_bit     = payload_mem[byte_idx][bit_in_byte];
            end
        end
    endfunction

    function padded_bit;
        input [15:0] idx;
        begin
            padded_bit = (idx < total_bits) ? raw_bit(idx) : 1'b0;
        end
    endfunction

    // ---------------------------------------------------------------------
    // FSM
    // ---------------------------------------------------------------------
    localparam S_IDLE     = 3'd0,
               S_GEN      = 3'd1,  // generate/DQPSK-encode the 4 symbols of one group
               S_SUBCHIRP = 3'd2,  // stream the 152 modulated chirp samples
               S_GAP      = 3'd3,  // stream the (TEVEN/TODD) idle gap samples
               S_NEXTGRP  = 3'd4,
               S_DONE     = 3'd5;

    reg [2:0]  state;
    reg [15:0] group_idx;
    reg [2:0]  phase;      // 0..4 within S_GEN
    reg [7:0]  chirp_addr; // 0..151 within S_SUBCHIRP
    reg [7:0]  gap_cnt;

    // ---- symbol source selection for the current (group_idx, phase) -------
    wire        in_preamble = (group_idx < 16'd12);
    wire [7:0]  preamble_addr = group_idx[5:0]*4 + phase[1:0];
    wire        pre_bit;

    preamble_sfd_rom #( .TOTAL_BITS(48), .MEMFILE(PREAMBLE_MEMFILE) )
        u_preamble_sfd ( .addr(preamble_addr), .bit_out(pre_bit) );

    wire [15:0] cw_idx = group_idx - 16'd12; // valid only when !in_preamble

    wire       g0 = padded_bit(6*cw_idx),   g1 = padded_bit(6*cw_idx+1),
               g2 = padded_bit(6*cw_idx+2), g3 = padded_bit(6*cw_idx+3),
               g4 = padded_bit(6*cw_idx+4), g5 = padded_bit(6*cw_idx+5);
    wire [2:0] group_in_I = {g0, g2, g4};   // I-path bits of this codeword (Block 2 -- even positions)
    wire [2:0] group_in_Q = {g1, g3, g5};   // Q-path bits of this codeword (odd positions)

    wire [3:0] codeword_I, codeword_Q;
    symbol_mapper #( .N_IN(3), .M_OUT(4), .MEMFILE(SYMROM_1MBPS) )
        u_symmap_I ( .group_in(group_in_I), .codeword_out(codeword_I) );
    symbol_mapper #( .N_IN(3), .M_OUT(4), .MEMFILE(SYMROM_1MBPS) )
        u_symmap_Q ( .group_in(group_in_Q), .codeword_out(codeword_Q) );

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
