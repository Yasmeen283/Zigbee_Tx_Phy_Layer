module csk_generator #(
    parameter NUM_SYMBOLS_WIDTH = 12   // covers up to 4095 DQPSK symbols;
                                        // largest real packet (127-byte
                                        // payload, 250 kb/s) needs ~2880
) (
    input  wire                          clk,
    input  wire                          reset,          // synchronous, active-high

    input  wire                          start,          // begin generating for this packet
    input  wire [1:0]                    chirp_index,    
    input  wire [NUM_SYMBOLS_WIDTH-1:0]  num_symbols,     // total DQPSK symbols in this packet, latched at start

    input  wire                          dqpsk_valid,     // new DQPSK symbol available
    input  wire                          dqpsk_sign_real, // 0 = +1, 1 = -1
    input  wire                          dqpsk_sign_imag, // 0 = +1, 1 = -1

    output reg  [1:0]                    subchirp_sel,    
    output reg  [5:0]                    sample_addr,     
    output reg                           sign_real_out,   // latched sign, passthrough to multiplier
    output reg                           sign_imag_out,
    output wire                          sample_valid,    // high while a real chirp sample is being addressed
    output reg                           next_symbol_req, // pulses to request the next DQPSK symbol
    output reg                           done,             // packet modulation complete (1-cycle pulse)
    output wire gap_active   
);


    reg [6:0] gap_even; // max value 70 -> needs 7 bits
    reg [6:0] gap_odd;

    reg [1:0] chirp_index_reg;

    always @(*) begin
        case (chirp_index_reg)
            2'd0: begin gap_even = 7'd10; gap_odd = 7'd70; end // m=1
            2'd1: begin gap_even = 7'd20; gap_odd = 7'd60; end // m=2
            2'd2: begin gap_even = 7'd30; gap_odd = 7'd50; end // m=3
            2'd3: begin gap_even = 7'd40; gap_odd = 7'd40; end // m=4
        endcase
    end

    
    // FSM state encoding
    localparam S_IDLE     = 3'd0;
    localparam S_REQ_SYM  = 3'd1;  // assert next_symbol_req for one cycle
    localparam S_WAIT_SYM = 3'd2;  // wait for dqpsk_valid, then latch signs
    localparam S_STREAM   = 3'd3;  // walk sample_addr 0..37 for current subchirp
    localparam S_GAP      = 3'd4;  // count down the inter-sequence gap (always runs, even after the last sequence)
    localparam S_DONE     = 3'd5;  // one-cycle done pulse


    reg [2:0] state;
    
    assign sample_valid = (state == S_STREAM);

    assign gap_active = (state == S_GAP);   // Raghad fix 3
    
    // Internal counters / registers
    
    reg [NUM_SYMBOLS_WIDTH-1:0] symbol_count;   // DQPSK symbols consumed so far
    reg [NUM_SYMBOLS_WIDTH-1:0] num_symbols_reg;
    reg                         seq_parity;     // toggles per completed chirp sequence (0=this gap even, 1=this gap odd)
    reg [6:0]                   gap_counter;
    reg                         last_seq;       // latched: the gap currently running follows the FINAL sequence

    reg sign_real_latched;
    reg sign_imag_latched;

    always @(posedge clk) begin
        if (reset) begin
            state             <= S_IDLE;
            subchirp_sel      <= 2'd0;
            sample_addr       <= 6'd0;
            sign_real_out     <= 1'b0;
            sign_imag_out     <= 1'b0;
            next_symbol_req   <= 1'b0;
            done              <= 1'b0;
            symbol_count      <= {NUM_SYMBOLS_WIDTH{1'b0}};
            num_symbols_reg   <= {NUM_SYMBOLS_WIDTH{1'b0}};
            chirp_index_reg   <= 2'd0;
            seq_parity        <= 1'b0;
            gap_counter       <= 7'd0;
            last_seq          <= 1'b0;
            sign_real_latched <= 1'b0;
            sign_imag_latched <= 1'b0;

        end else begin
            next_symbol_req <= 1'b0;
            done             <= 1'b0;

            case (state)


                S_IDLE: begin
                    if (start) begin
                        chirp_index_reg <= chirp_index;
                        num_symbols_reg <= num_symbols;
                        symbol_count    <= {NUM_SYMBOLS_WIDTH{1'b0}};
                        subchirp_sel    <= 2'd0;
                        seq_parity      <= 1'b0;

                        if (num_symbols == {NUM_SYMBOLS_WIDTH{1'b0}}) begin
                            // edge case: empty packet, nothing to stream, no gap
                            state <= S_DONE;
                        end else begin
                            state <= S_REQ_SYM;
                        end
                    end
                end

                S_REQ_SYM: begin
                    next_symbol_req <= 1'b1;   // one-cycle pulse
                    state           <= S_WAIT_SYM;
                end

                S_WAIT_SYM: begin
                    if (dqpsk_valid) begin
                        sign_real_latched <= dqpsk_sign_real;
                        sign_imag_latched <= dqpsk_sign_imag;
                        sample_addr       <= 6'd0;
                        state             <= S_STREAM;
                    end
                    // else: keep waiting, next_symbol_req already fell
                    // back to 0 by default above -- encoder is
                    // expected to hold the request internally if it needs
                    // more than one cycle to respond
                end

                S_STREAM: begin
                    sign_real_out <= sign_real_latched;
                    sign_imag_out <= sign_imag_latched;
                    // subchirp_sel already holds the current k

                    if (sample_addr == 6'd37) begin
                        // last sample of this subchirp being output now
                        symbol_count <= symbol_count + 1'b1;

                        if (subchirp_sel == 2'd3) begin
                            // last subchirp of this chirp sequence done --
                            // a gap ALWAYS follows, whether or not more
                            // sequences remain 
                            subchirp_sel <= 2'd0;
                            // Load (gap_length - 1): counting inclusively
                            // from N down to 0 spends N+1 cycles, not N --
                            // loading N-1 makes the countdown take exactly
                            // N cycles 
                            gap_counter  <= (seq_parity ? gap_odd : gap_even) - 1'b1;
                            seq_parity   <= ~seq_parity;
                            last_seq     <= ((symbol_count + 1'b1) == num_symbols_reg);
                            state        <= S_GAP;
                        end else begin
                            // move to next subchirp within the same sequence
                            subchirp_sel <= subchirp_sel + 1'b1;
                            state        <= S_REQ_SYM;
                        end

                    end else begin
                        sample_addr <= sample_addr + 1'b1;
                    end
                end

                S_GAP: begin
                    if (gap_counter == 7'd0) begin
                        // this gap has just finished counting down
                        if (last_seq)
                            state <= S_DONE;      // that was the trailing gap -- packet complete
                        else
                            state <= S_REQ_SYM;    // start the next chirp sequence
                    end else begin
                        gap_counter <= gap_counter - 1'b1;
                    end
                end

                S_DONE: begin
                    done         <= 1'b1;   // one-cycle pulse
                    state        <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule