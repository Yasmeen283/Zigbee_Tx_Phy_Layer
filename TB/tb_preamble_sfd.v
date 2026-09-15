`timescale 1ns/1ps

module tb_preamble_sfd;

    reg [7:0] addr1m, addr250;
    wire b1m, b250;

    preamble_sfd_rom #(.TOTAL_BITS(48), .MEMFILE("vectors/preamble_sfd_1mbps.mem"))
        dut1m (.addr(addr1m), .bit_out(b1m));

    preamble_sfd_rom #(.TOTAL_BITS(96), .MEMFILE("vectors/preamble_sfd_250kbps.mem"))
        dut250 (.addr(addr250), .bit_out(b250));

    integer i, errors;

    initial begin
        errors = 0;

        // ---- 1 Mbps: 32 ones then SFD = 0111010010011100 ----
        for (i = 0; i < 32; i = i + 1) begin
            addr1m = i; #1;
            if (b1m !== 1'b1) begin
                $display("FAIL 1Mbps preamble bit %0d = %b (expected 1)", i, b1m);
                errors = errors + 1;
            end
        end
        begin : sfd1m_check
            reg [15:0] sfd_pat;
            sfd_pat = 16'b0111010010011100;
            for (i = 0; i < 16; i = i + 1) begin
                addr1m = 32 + i; #1;
                if (b1m !== sfd_pat[15-i]) begin
                    $display("FAIL 1Mbps SFD bit %0d = %b expected %b", i, b1m, sfd_pat[15-i]);
                    errors = errors + 1;
                end
            end
        end

        // ---- 250 kbps: 80 ones then SFD (from bipolar -1,1,1,1,1,-1,1,-1,-1,-1,1,-1,-1,-1,1,1) ----
        for (i = 0; i < 80; i = i + 1) begin
            addr250 = i; #1;
            if (b250 !== 1'b1) begin
                $display("FAIL 250kbps preamble bit %0d = %b (expected 1)", i, b250);
                errors = errors + 1;
            end
        end
        begin : sfd250_check
            reg [15:0] sfd_pat;
            sfd_pat = 16'b0111101000100011;
            for (i = 0; i < 16; i = i + 1) begin
                addr250 = 80 + i; #1;
                if (b250 !== sfd_pat[15-i]) begin
                    $display("FAIL 250kbps SFD bit %0d = %b expected %b", i, b250, sfd_pat[15-i]);
                    errors = errors + 1;
                end
            end
        end

        if (errors == 0)
            $display("PASS: tb_preamble_sfd -- both data rates match reference SFD/preamble patterns");
        else
            $display("FAIL: tb_preamble_sfd -- %0d mismatches", errors);
        $finish;
    end

endmodule
