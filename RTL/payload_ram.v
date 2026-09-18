

module payload_ram #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 7   // 2^7 = 128 bytes maximum PSDU capacity
)(
    input  wire                  clk,
    
    // Write Interface (Payload Loading)
    input  wire                  we,           // Write enable
    input  wire [ADDR_WIDTH-1:0] waddr,        // Write address
    input  wire [DATA_WIDTH-1:0] din,          // Write data byte
    
    // Read Interface (Connected to Framer)
    input  wire [ADDR_WIDTH-1:0] raddr,        // Read address (ram_addr from Framer)
    output reg  [DATA_WIDTH-1:0] dout         // Read data byte (ram_din to Framer)
);

    // 128 x 8-bit RAM Memory Array
    reg [DATA_WIDTH-1:0] ram [0:(1<<ADDR_WIDTH)-1];

    // Synchronous Memory Read & Write Operations
    always @(posedge clk) begin
        if (we) begin
            ram[waddr] <= din;
        end
        dout <= ram[raddr];
    end

endmodule