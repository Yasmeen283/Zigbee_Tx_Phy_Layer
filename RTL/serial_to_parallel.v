// //=============================================================================
// // serial_to_parallel.v
// //
// // Converts incoming serial bits into an N-bit parallel word (e.g., N = 3 or 6).
// // Only accumulates bits when `valid_in` is active.
// //=============================================================================

// module serial_to_parallel #(
//     parameter N = 3                     // Parallel word width (3 for 1Mbps sub-chirp, 6 for 250kbps)
// ) (
//     input  wire         clk,
//     input  wire         reset,            // Synchronous active-high reset
//     input  wire         start,           //?maybe i would need to delay this 1 cycle // Pulse to clear counters for a new frame (e.g., connected to 'load')
//     input  wire         valid_in,       // High when bit_in is valid (e.g., enable & i_valid / q_valid)
//     input  wire         bit_in,        // Serial input bit

//     output reg  [N-1:0] data_out,        // N-bit parallel output
//     output reg          valid_out       // Active for 1 cycle when a full N-bit word is ready
// );

//     reg [$clog2(N):0] bit_cnt;
//     reg [N-1:0]       shift_reg;

//     always @(posedge clk) begin
//         if (reset) begin
//             bit_cnt   <= 'd0;
//             shift_reg <= 'd0;
//             data_out  <= 'd0;
//             valid_out <= 1'b0;
//         end
//         else if (start) begin
//             bit_cnt   <= 'd0;
//             shift_reg <= 'd0;
//             data_out  <= 'd0;
//             valid_out <= 1'b0;
//         end
//         else begin
//             valid_out <= 1'b0;

//             if (valid_in) begin
//                 // Shift incoming bit in from MSB side (LSB first)
//                 shift_reg <= {bit_in, shift_reg[N-1:1]};

//                 if (bit_cnt == N - 1) begin
//                     bit_cnt   <= 'd0;
//                     data_out  <= {bit_in, shift_reg[N-1:1]};
//                     valid_out <= 1'b1;
//                 end else begin
//                     bit_cnt   <= bit_cnt + 1'b1;
//                 end
//             end
//         end
//     end

// endmodule

//=============================================================================
// serial_to_parallel.v
//
// Converts incoming serial bits into an N-bit parallel word (e.g., N = 3 or 6).
// Only accumulates bits when `valid_in` is active.
//=============================================================================

module serial_to_parallel #(
    parameter N = 3                     // Parallel word width (3 for 1Mbps sub-chirp, 6 for 250kbps)
) (
    input  wire         clk,
    input  wire         reset,            // Synchronous active-high reset
    input  wire         start,           //?maybe i would need to delay this 1 cycle // Pulse to clear counters for a new frame (e.g., connected to 'load')
    input  wire         valid_in,       // High when bit_in is valid (e.g., enable & i_valid / q_valid)
    input  wire         bit_in,        // Serial input bit

    output reg  [N-1:0] data_out,        // N-bit parallel output
    output reg          valid_out       // Active for 1 cycle when a full N-bit word is ready
);

    reg [$clog2(N):0] bit_cnt;
    reg [N-1:0]       shift_reg;

    always @(posedge clk) begin
        if (reset) begin
            bit_cnt   <= 'd0;
            shift_reg <= 'd0;
            data_out  <= 'd0;
            valid_out <= 1'b0;
        end
        else if (start) begin
            bit_cnt   <= 'd0;
            shift_reg <= 'd0;
            data_out  <= 'd0;
            valid_out <= 1'b0;
        end
        else begin
            valid_out <= 1'b0;

            if (valid_in) begin
                // Shift incoming bit in from MSB side (LSB first)
                //////////////////raghad fix 5//////////////////////
                //shift_reg <= {bit_in, shift_reg[N-1:1]};
                shift_reg <= {shift_reg[N-2:0], bit_in};

                if (bit_cnt == N - 1) begin
                    bit_cnt   <= 'd0;
                    //data_out  <= {bit_in, shift_reg[N-1:1]};
                    data_out  <= {shift_reg[N-2:0], bit_in};
                    valid_out <= 1'b1;
                end else begin
                    bit_cnt   <= bit_cnt + 1'b1;
                end
            end
        end
    end

endmodule