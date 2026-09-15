// =========================================================================
// css_symbol_generator.v
// Task 3 top-level wrapper -- ties chirp_rom + csk_generator +
// complex_multiplier together into the single block Task 2's top-level
// controller / DQPSK encoder instantiates. Corresponds to the "CSS
// Symbols ROM" + Controller + "X" multiplier chain in Figure 3-3 of the
// thesis document.
//
// This module's only job is INTEGRATION: wiring the three already-built
// submodules together correctly, including compensating for the timing
// each one introduces on its own. Nothing here re-implements sequencing,
// addressing, or the multiply -- see the individual modules for that.
//
// ---------------------------------------------------------------------
// Why the wiring isn't a plain 1:1 passthrough (read this before editing)
// ---------------------------------------------------------------------
// chirp_rom is a SYNCHRONOUS, REGISTERED ROM: the sample it returns on
// (rom_real, rom_imag) corresponds to whatever address was on
// (chirp_index, subchirp_sel, sample_addr) ONE CYCLE EARLIER.
//
// csk_generator's sample_valid is COMBINATIONAL (assign sample_valid =
// (state == S_STREAM);) -- it is asserted the SAME cycle an address is
// issued, with zero latency.
//
// csk_generator's sign_real_out / sign_imag_out are REGISTERED (set
// inside the S_STREAM case body), so they update to match whatever
// address was just issued starting the NEXT cycle -- i.e. they carry
// exactly ONE cycle of latency already, by construction.
//
// Net result: sign_real_out/sign_imag_out already land in step with
// chirp_rom's registered output for the SAME address, with no extra
// delay needed. sample_valid does NOT -- it is asserted a cycle too
// early relative to the ROM data it's supposed to flag. This wrapper
// adds exactly one register stage (sample_valid_d1) to fix that, and
// nothing else. Do not delay sign_real_out/sign_imag_out again, or
// they will end up misaligned by a cycle in the other direction.
//
// chirp_index: csk_generator LATCHES chirp_index into its own internal
// chirp_index_reg at the `start` pulse and is not affected by the input
// changing mid-packet -- but chirp_rom has no such latch and will use
// whatever is on its chirp_index input EVERY cycle. If the top-level
// chirp_index input were fed to chirp_rom directly and something
// upstream changed it mid-packet (e.g. preparing the next packet's
// setting while this one is still streaming), chirp_rom would silently
// address the WRONG chirp sequence for the remainder of the packet. To
// make this module correct regardless of how the caller drives its
// chirp_index input, chirp_index is latched HERE too, on the same
// `start` pulse, and that latched copy -- not the live input -- is what
// feeds chirp_rom.
//
// Total pipeline latency, address-issued to final Tx sample: 2 cycles
// (1 from chirp_rom's registered read, 1 from complex_multiplier's
// registered output).
//
// `done` is passed straight through from csk_generator with no extra
// delay: csk_generator's v3 FSM always runs a gap (at least 10 cycles)
// after the final chirp sequence before asserting `done`, which is far
// longer than this module's 2-cycle pipeline drain time, so by the time
// `done` pulses every real sample has already appeared on
// (tx_real, tx_imag, tx_valid).
// =========================================================================

module css_symbol_generator #(
    parameter NUM_SYMBOLS_WIDTH = 12,  // must match csk_generator's NUM_SYMBOLS_WIDTH
    parameter ROM_WIDTH         = 5,   // must match chirp_rom's word width (R)
    parameter OUT_WIDTH         = 6    // ROM_WIDTH + 1 -- see complex_multiplier.v
) (
    input  wire                          clk,
    input  wire                          reset,          // synchronous, active-high

    input  wire                          start,          // begin generating for this packet
    input  wire [1:0]                    chirp_index,    // 0-3 <-> standard m=1-4, latched at start
    input  wire [NUM_SYMBOLS_WIDTH-1:0]  num_symbols,    // total DQPSK symbols in this packet, latched at start

    input  wire                          dqpsk_valid,     // new DQPSK symbol available
    input  wire                          dqpsk_sign_real, // 0 = +1, 1 = -1
    input  wire                          dqpsk_sign_imag, // 0 = +1, 1 = -1

    output wire                          next_symbol_req, // pulses to request the next DQPSK symbol
    output wire                          done,            // packet modulation complete (1-cycle pulse)

    output wire signed [OUT_WIDTH-1:0]   tx_real,         // final modulated I output
    output wire signed [OUT_WIDTH-1:0]   tx_imag,         // final modulated Q output
    output wire                          tx_valid         // high exactly when tx_real/tx_imag hold a real sample
);

    // ---------------------------------------------------------------
    // chirp_index: latch our own copy at `start`, independent of
    // csk_generator's internal chirp_index_reg, so chirp_rom always
    // addresses the same chirp sequence csk_generator is sequencing --
    // see the header comment above for why this is needed.
    // ---------------------------------------------------------------
    reg [1:0] chirp_index_latched;
    always @(posedge clk) begin
        if (reset)
            chirp_index_latched <= 2'd0;
        else if (start)
            chirp_index_latched <= chirp_index;
    end

    // ---------------------------------------------------------------
    // csk_generator: sequencing / control
    // ---------------------------------------------------------------
    wire [1:0] subchirp_sel;
    wire [5:0] sample_addr;
    wire       sign_real_out;
    wire       sign_imag_out;
    wire       sample_valid;

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
        .done            (done)
    );

    // ---------------------------------------------------------------
    // chirp_rom: 1-cycle registered read, addressed by csk_generator's
    // live subchirp_sel/sample_addr and OUR latched chirp_index copy.
    // ---------------------------------------------------------------
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

    // ---------------------------------------------------------------
    // One-cycle valid delay: the ONLY timing fix-up this wrapper needs
    // to add. Compensates for chirp_rom's registered read latency.
    // sign_real_out/sign_imag_out need no equivalent delay -- see the
    // header comment for why they already land in step with rom_real/
    // rom_imag one cycle later, by construction.
    // ---------------------------------------------------------------
    reg sample_valid_d1;
    always @(posedge clk) begin
        if (reset)
            sample_valid_d1 <= 1'b0;
        else
            sample_valid_d1 <= sample_valid;
    end

    // ---------------------------------------------------------------
    // complex_multiplier: combines the (now aligned) ROM sample with
    // the DQPSK sign bits, adding one more cycle of registered latency.
    // ---------------------------------------------------------------
    complex_multiplier #(
        .ROM_WIDTH (ROM_WIDTH),
        .OUT_WIDTH (OUT_WIDTH)
    ) u_complex_multiplier (
        .clk       (clk),
        .reset     (reset),
        .rom_real  (rom_real),
        .rom_imag  (rom_imag),
        .sign_real (sign_real_out),
        .sign_imag (sign_imag_out),
        .valid_in  (sample_valid_d1),
        .tx_real   (tx_real),
        .tx_imag   (tx_imag),
        .valid_out (tx_valid)
    );

endmodule
