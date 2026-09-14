// ============================================================================
// Block 1: Zero Padding / Payload Framer Module
// Standard: IEEE 802.15.4 CSS Physical Layer (2450 MHz)
// 
// Description:
// Concatenates the 12-bit PHY Header (PHR) and incoming payload (PSDU) into
// a unified bitstream, then calculates and appends zero-padding bits to align
// the total length to a multiple of N (N = 6 for 1 Mbps, N = 24 for 250 kbps).
// ============================================================================

module zero_padding (
    input  wire        clk,
    input  wire        reset,
    input  wire        start_Tx,
    input  wire        data_rate,       // 0: 1 Mbps, 1: 250 kbps
    input  wire [7:0]  payloadLength,   // Payload length in bytes (0 to 127)
    
    // RAM Interface to read PSDU bytes
    output reg  [6:0]  ram_addr,
    input  wire [7:0]  ram_din,
    
    // Output Stream Interface
    output reg         bit_out,
    output reg         bit_valid,
    output reg         padding_done
);

    // ------------------------------------------------------------------------
    // FSM State Encoding
    // ------------------------------------------------------------------------
    localparam IDLE         = 3'b000;
    localparam LOAD_BYTE    = 3'b001;
    localparam STREAM_PHR   = 3'b010;
    localparam STREAM_PAYLOAD= 3'b011;
    localparam STREAM_PAD   = 3'b100;
    localparam DONE         = 3'b101;

    reg [2:0] state, next_state;

    // ------------------------------------------------------------------------
    // Internal Registers & Counters
    // ------------------------------------------------------------------------
    reg [11:0] phr_reg;             // 12-bit PHY Header
    reg [7:0]  shift_reg;           // Shift register for current payload byte
    reg [3:0]  bit_cnt;             // Bit index counter within a byte/PHR
    reg [6:0]  byte_cnt;            // Byte counter for payload (up to 127)
    reg [4:0]  pad_cnt;             // Counter for added padding bits
    reg [4:0]  pad_total;           // Calculated total padding bits required

    // ------------------------------------------------------------------------
    // Length & Padding Calculation Logic
    // Total bits = 12 (PHR) + payloadLength * 8
    // 1 Mbps:   padded to multiple of 6  --> pad_total = (6 - (total % 6)) % 6
    // 250 kbps: padded to multiple of 24 --> pad_total = (24 - (total % 24)) % 24
    // ------------------------------------------------------------------------
    wire [10:0] total_unpadded_bits = 12 + (payloadLength << 3);
    wire [4:0]  rem_6  = total_unpadded_bits % 6;
    wire [4:0]  rem_24 = total_unpadded_bits % 24;
    
    wire [4:0] calc_pad_1M   = (rem_6 == 0)  ? 5'd0 : (5'd6 - rem_6);
    wire [4:0] calc_pad_250k = (rem_24 == 0) ? 5'd0 : (5'd24 - rem_24);

    // ------------------------------------------------------------------------
    // State Register
    // ------------------------------------------------------------------------
    always @(posedge clk or posedge reset) begin
        if (reset)
            state <= IDLE;
        else
            state <= next_state;
    end

    // ------------------------------------------------------------------------
    // Next-State Logic
    // ------------------------------------------------------------------------
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (start_Tx)
                    next_state = STREAM_PHR;
            end

            STREAM_PHR: begin
                if (bit_cnt == 4'd11) begin
                    if (payloadLength == 8'd0)
                        next_state = (pad_total == 5'd0) ? DONE : STREAM_PAD;
                    else
                        next_state = LOAD_BYTE;
                end
            end

            LOAD_BYTE: begin
                next_state = STREAM_PAYLOAD;
            end

            STREAM_PAYLOAD: begin
                if (bit_cnt == 4'd7) begin
                    if (byte_cnt + 1'b1 == payloadLength)
                        next_state = (pad_total == 5'd0) ? DONE : STREAM_PAD;
                    else
                        next_state = LOAD_BYTE;
                end
            end

            STREAM_PAD: begin
                if (pad_cnt + 1'b1 == pad_total)
                    next_state = DONE;
            end

            DONE: begin
                next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end

    // ------------------------------------------------------------------------
    // Datapath & Control Logic
    // ------------------------------------------------------------------------
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            ram_addr     <= 7'd0;
            bit_out      <= 1'b0;
            bit_valid    <= 1'b0;
            padding_done <= 1'b0;
            bit_cnt      <= 4'd0;
            byte_cnt     <= 7'd0;
            pad_cnt      <= 5'd0;
            pad_total    <= 5'd0;
            phr_reg      <= 12'd0;
            shift_reg    <= 8'd0;
        end else begin
            // Default pulse signals
            bit_valid    <= 1'b0;
            padding_done <= 1'b0;

            case (state)
                IDLE: begin
                    if (start_Tx) begin
                        // PHR layout: Bits 0-6 = Length, Bits 7-8 = 0, Bits 9-11 = Reserved (0)
                        phr_reg   <= {5'b00000, payloadLength[6:0]};
                        pad_total <= (data_rate == 1'b0) ? calc_pad_1M : calc_pad_250k;
                        bit_cnt   <= 4'd0;
                        byte_cnt  <= 7'd0;
                        pad_cnt   <= 5'd0;
                        ram_addr  <= 7'd0;
                    end
                end

                STREAM_PHR: begin
                    bit_out   <= phr_reg[bit_cnt];
                    bit_valid <= 1'b1;
                    if (bit_cnt == 4'd11)
                        bit_cnt <= 4'd0;
                    else
                        bit_cnt <= bit_cnt + 1'b1;
                end

                LOAD_BYTE: begin
                    shift_reg <= ram_din;
                    bit_cnt   <= 4'd0;
                end

                STREAM_PAYLOAD: begin
                    bit_out   <= shift_reg[7 - bit_cnt]; // Stream MSB first
                    bit_valid <= 1'b1;
                    if (bit_cnt == 4'd7) begin
                        bit_cnt  <= 4'd0;
                        byte_cnt <= byte_cnt + 1'b1;
                        ram_addr <= ram_addr + 1'b1;
                    end else begin
                        bit_cnt  <= bit_cnt + 1'b1;
                    end
                end

                STREAM_PAD: begin
                    bit_out   <= 1'b0; // Pad zero bits
                    bit_valid <= 1'b1;
                    pad_cnt   <= pad_cnt + 1'b1;
                end

                DONE: begin
                    padding_done <= 1'b1;
                end
            endcase
        end
    end

endmodule