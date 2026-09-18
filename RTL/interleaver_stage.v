`timescale 1ns/1ps

module interleaver_stage #(
    parameter integer M_OUT     = 4,     // 4 (1Mbps) or 32 (250kbps)
    parameter         DATA_RATE = 1'b0   // 0 = 1Mbps (interleaver elaborated out entirely), 1 = 250kbps (interleaver active)
)(
    input  wire               clk,
    input  wire               reset,

    input  wire [M_OUT-1:0]   codeword_in,
    input  wire               codeword_valid,   // from symbol_mapper

    output reg  [M_OUT-1:0]   data_out,
    output reg                data_valid        // to Form PPDU / parallel_to_serial
);

    generate
        if (DATA_RATE == 1'b0) begin : g_1mbps_bypass

            always @(posedge clk) begin
                if (reset) begin
                    data_out   <= {M_OUT{1'b0}};
                    data_valid <= 1'b0;
                end else begin
                    data_out   <= codeword_in;
                    data_valid <= codeword_valid;
                end
            end

        end 
        else begin : g_250k_interleave
            // 2-State FSM Definitions
            localparam S_WAIT_FIRST  = 1'b0; // Waiting for codeword N
            localparam S_WAIT_SECOND = 1'b1; // First codeword buffered, waiting for codeword N+1

            reg               state;
            reg [M_OUT-1:0]   cw0;
            reg               pending_second;
            reg [M_OUT-1:0]   second_half;

            wire [2*M_OUT-1:0] pair_in  = {cw0, codeword_in};   // {older codeword, newer codeword}
            wire [2*M_OUT-1:0] pair_out;

            interleaver u_interleaver (
                .data_in        (pair_in),
                .data_out       (pair_out)
            );

            always @(posedge clk) begin
                if (reset) begin
                    state          <= S_WAIT_FIRST;
                    cw0            <= {M_OUT{1'b0}};
                    second_half    <= {M_OUT{1'b0}};
                    pending_second <= 1'b0;
                    data_out       <= {M_OUT{1'b0}};
                    data_valid     <= 1'b0;
                end else begin
                    data_valid <= 1'b0;

                    if (pending_second) begin
                        // Stream out second half of the pair (computed previous cycle)
                        data_out       <= second_half;
                        data_valid     <= 1'b1;
                        pending_second <= 1'b0;
                    end else if (codeword_valid) begin
                        case (state)
                            S_WAIT_FIRST: begin
                                // Buffer codeword N and wait for N+1
                                cw0   <= codeword_in;
                                state <= S_WAIT_SECOND;
                            end

                            S_WAIT_SECOND: begin
                                // Codeword N+1 arrived: pair processed combinationally this cycle
                                data_out       <= pair_out[2*M_OUT-1 -: M_OUT];
                                second_half    <= pair_out[M_OUT-1:0];
                                data_valid     <= 1'b1;
                                pending_second <= 1'b1;
                                state          <= S_WAIT_FIRST;
                            end
                        endcase
                    end
                end
            end
        
        end
    endgenerate


endmodule
