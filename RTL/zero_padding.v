//=============================================================================
// Block 1 (Zero Padding / payload framer) of the CSS PHY transmitter.
//=============================================================================

module zero_padding #(
    parameter GROUP_SIZE = 6 ,     // 6 for 1 Mbps, 24 for 250 kbps
    parameter DATA_WIDTH = 8 ,
    parameter ADDR_WIDTH = 7 
) (
    input  wire         clk,
    input  wire         reset,              // synchronous, active-high
    input  wire         load,              // pulse: reload bit_index to 0 for a new PPDU
    input  wire         enable,           // advance bit_index by 1 each cycle while high

    // ---- length / padding arithmetic --------------------------------------
    input  wire [6:0]   payload_length_reg,          // PHR(12) + PSDU(8*payloadLength) bit count
    output wire [15:0]  padded_total_bits,         // total_bits + pad_bits (multiple of GROUP_SIZE)

    // ---- read payload ----------------------------------------------------

    input  wire [DATA_WIDTH-1:0] payload_rd_data,    
    output reg  [ADDR_WIDTH-1:0] payload_rd_addr, 

    // ---- serial bit gate ----------------------------------------------------
    output wire  bit_index_sel,          // 0-based position within the padded stream --
                                           // value of PHR/PSDU bit `bit_index` (only meaningful
                                          // when bit_index < total_bits; framer/RAM supplies it)

    output wire         bit_out,            // payload bit, or 0 inside the padding region
    output reg  [1:0]   state,             //output for css tx frontend
    output wire         frame_done        // high when bit_index is on the last bit of the padded frame
);

    // ------------------------------------------------------------------
    // Padding arithmetic -- combinational
    // ------------------------------------------------------------------
    //PHR(12) + PSDU(8*payloadLength) bit count
    reg [15:0]  bit_index ;
    wire [4:0]  pad_bits;            // 0 .. GROUP_SIZE-1 zero bits appended //max no of 0's is 23 for the 250k mode
    wire [15:0] total_bits ;
    assign total_bits = 16'd12 + ({9'd0, payload_length_reg} << 3); //12 bit phy header + (no bytes * 8 )

    
    wire [15:0] remainder;
    // assign remainder = total_bits - (GROUP_SIZE * (total_bits / GROUP_SIZE));
    assign remainder = total_bits % GROUP_SIZE ; //?synthesizable
//************************************************************************************
    //Raghad trial 2 fix
    //assign pad_bits          = (remainder == 0) ? 5'd0 : (GROUP_SIZE - remainder);
    assign pad_bits = GROUP_SIZE - remainder;

//********************************************************************
    assign padded_total_bits = total_bits + pad_bits;

    // ------------------------------------------------------------------
    // bit_index sequencing: registered counter, walks
    // 0 .. padded_total_bits-1, one step per cycle while enabled.
    // ------------------------------------------------------------------
    
    reg payload_bit_in ;
    reg [2:0] word_idx ; 
    wire [11:0] phy_header ;

    assign phy_header = {3'b000 ,2'b00 , payload_length_reg} ; //0->6 payload length , 7->8 not used , 9->11 reserved 

    localparam [1:0] IDLE = 2'b00,
                     PHR  = 2'b01,
                     PSDU = 2'b11; 

    reg [1:0] next_state ;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE ;
        end
        else begin
            state <= next_state ;
        end
    end

    always @(*) begin
        next_state = state ;
        case(state) 
            IDLE: begin
                if (load) begin
                    next_state = PHR ;
                end
            end
            PHR: begin
                if (bit_index == 'd11) begin
                    next_state = PSDU ;
                end
            end
            PSDU: begin
                if (frame_done) begin
                    next_state = IDLE ;
                end
            end
            default: begin
                next_state = state ;
            end
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            bit_index <= 16'd0;
            payload_bit_in <= 1'b0 ;
            payload_rd_addr <= 'b0 ;
            word_idx <= 1'b0 ;
        end 
        else begin
            case (state) 
                IDLE: begin
                    bit_index <= 16'd0;
                    payload_bit_in <= 1'b0 ;
                    payload_rd_addr <= 'b0 ;
                    word_idx <= 1'b0 ;
                end

                PHR: begin
                    if(enable) begin
                        bit_index <= bit_index + 16'd1;
                        payload_bit_in <= phy_header[bit_index] ;
                    end
                end

                PSDU: begin
                    if (enable && !frame_done) begin
                        bit_index <= bit_index + 16'd1;
                        word_idx <= word_idx + 1'b1 ;
                        payload_bit_in <= payload_rd_data[word_idx];
                        if(&word_idx) begin // end of byte 
                            payload_rd_addr <= payload_rd_addr + 1'b1 ;
                        end
                    end
                end 
            endcase
        end 
    end

    assign frame_done = (bit_index == (padded_total_bits - 16'd1)); //? -1 ?
    //------------------------------------------------------------------
    // Serial bit gate (combinational): substitute 0 once bit_index has
    // walked past the real PHR/PSDU bits and into the padding region.
    // ------------------------------------------------------------------
    reg  [15:0] bit_index_d ;
    always @(posedge clk) begin
        if (reset)
            bit_index_d <= 16'd0;
        else
            bit_index_d <= bit_index;
    end

    assign bit_out = (bit_index_d < total_bits) ? payload_bit_in : 1'b0;

    assign bit_index_sel = bit_index[0];
endmodule