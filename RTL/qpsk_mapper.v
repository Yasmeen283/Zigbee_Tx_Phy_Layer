`timescale 1ns/1ps

module qpsk_mapper (
    input  wire       i_bit,          // 0 = +1, 1 = -1 (project-wide sign convention)
    input  wire       q_bit,          // 0 = +1, 1 = -1
    output reg  [1:0] qpsk_quadrant   // 00=+1, 01=+j, 10=-1, 11=-j (rotation count x90 deg)
);

    always @(*) begin
        case ({i_bit, q_bit})
            2'b00:   qpsk_quadrant = 2'd2; //  -1
            2'b10:   qpsk_quadrant = 2'd3; //  -j
            2'b11:   qpsk_quadrant = 2'd0; //  +1
            2'b01:   qpsk_quadrant = 2'd1; //  +j
            default: qpsk_quadrant = 2'd0;
        endcase
    end

endmodule
