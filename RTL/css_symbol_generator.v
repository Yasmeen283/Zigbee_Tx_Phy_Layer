module css_symbol_generator #(
    parameter NUM_SYMBOLS_WIDTH = 12,  
    parameter ROM_WIDTH         = 5,  
    parameter OUT_WIDTH         = 6    
) (
    input  wire                          clk,
    input  wire                          reset,          // synchronous, active-high

    input  wire                          start,          
    input  wire [1:0]                    chirp_index,   
    input  wire [NUM_SYMBOLS_WIDTH-1:0]  num_symbols,    // total DQPSK symbols in this packet, latched at start

    input  wire                          dqpsk_valid,     // new DQPSK symbol available
    input  wire                          dqpsk_sign_real, // 0 = +1, 1 = -1
    input  wire                          dqpsk_sign_imag, // 0 = +1, 1 = -1

    output wire                          next_symbol_req, // pulses to request the next DQPSK symbol
    output wire                          done,            

    output wire signed [OUT_WIDTH-1:0]   tx_real,         // final modulated I output
    output wire signed [OUT_WIDTH-1:0]   tx_imag,         // final modulated Q output
    output wire                          tx_valid         // high exactly when tx_real/tx_imag hold a real sample
);


    reg [1:0] chirp_index_latched;
    always @(posedge clk) begin
        if (reset)
            chirp_index_latched <= 2'd0;
        else if (start)
            chirp_index_latched <= chirp_index;
    end


    wire [1:0] subchirp_sel;
    wire [5:0] sample_addr;
    wire       sign_real_out;
    wire       sign_imag_out;
    wire       sample_valid;
    wire       gap_active;  

    csk_generator #(
        .NUM_SYMBOLS_WIDTH (NUM_SYMBOLS_WIDTH)
    ) u_csk_generator (
        .clk             (clk),
        .reset           (reset),
        .start           (start),
        .chirp_index     (chirp_index),
        .num_symbols     (num_symbols),
        .dqpsk_valid     (dqpsk_valid),
        .dqpsk_sign_real (dqpsk_sign_real),
        .dqpsk_sign_imag (dqpsk_sign_imag),
        .subchirp_sel    (subchirp_sel),
        .sample_addr     (sample_addr),
        .sign_real_out   (sign_real_out),
        .sign_imag_out   (sign_imag_out),
        .sample_valid    (sample_valid),
        .next_symbol_req (next_symbol_req),
        .done            (done),
        .gap_active      (gap_active) 
    );


    wire signed [ROM_WIDTH-1:0] rom_real;
    wire signed [ROM_WIDTH-1:0] rom_imag;

    chirp_rom u_chirp_rom (
        .clk          (clk),
        .chirp_index  (chirp_index_latched),
        .subchirp_sel (subchirp_sel),
        .sample_addr  (sample_addr),
        .rom_real     (rom_real),
        .rom_imag     (rom_imag)
    );

    reg sample_valid_d1;
    reg gap_active_d1;  
    always @(posedge clk) begin
        if (reset) begin
            sample_valid_d1 <= 1'b0;
            gap_active_d1   <= 1'b0; 
        end
        else begin
            sample_valid_d1 <= sample_valid;
            gap_active_d1   <= gap_active; 
        end
    end



    wire signed [ROM_WIDTH-1:0] gap_masked_real = gap_active_d1 ? {ROM_WIDTH{1'b0}} : rom_real; 
    wire signed [ROM_WIDTH-1:0] gap_masked_imag = gap_active_d1 ? {ROM_WIDTH{1'b0}} : rom_imag; 
    complex_multiplier #(
        .ROM_WIDTH (ROM_WIDTH),
        .OUT_WIDTH (OUT_WIDTH)
    ) u_complex_multiplier (
        .clk       (clk),
        .reset     (reset),
        //.rom_real  (rom_real),
        //.rom_imag  (rom_imag),
        .rom_real  (gap_masked_real), 
        .rom_imag  (gap_masked_imag), 
        .sign_real (sign_real_out),
        .sign_imag (sign_imag_out),
        //.valid_in  (sample_valid_d1),
        .valid_in  (sample_valid_d1 | gap_active_d1),  
        .tx_real   (tx_real),
        .tx_imag   (tx_imag),
        .valid_out (tx_valid)
    );

endmodule
