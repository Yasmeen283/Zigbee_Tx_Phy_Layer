`timescale 1ns/1ps

// =============================================================================
// IEEE 802.15.4 CSS PHY Transmitter - Integration Testbench
// =============================================================================
// Final DUT interface matched to css_tx_top.v.
//
// DUT configuration:
//   -DUT_RATE=0  -> 1 Mbps
//   -DUT_RATE=1  -> 250 kbps
//
// The testbench:
//   1) loads RAW PSDU bytes into the DUT payload RAM
//   2) sets payload_length_reg and chirp_index
//   3) pulses start
//   4) captures ONLY tx_valid samples
//   5) stops after tx_done
//   6) fails if fifo_overflow ever becomes 1
//   7) writes signed decimal Tx samples for MATLAB bit-exact comparison
// =============================================================================

module tb;

  `ifndef DUT_RATE
    `define DUT_RATE 0
  `endif

  localparam bit RATE_250K = (`DUT_RATE == 1);

  localparam int CLK_PERIOD_NS     = 10;
  localparam int MAX_PAYLOAD_BYTES = 127;
  localparam int NUM_TESTS         = 4;
  localparam longint TIMEOUT_CYCLES = 2_000_000;

  // Match the final top-level parameterisation.
  localparam int N_IN_CFG = RATE_250K ? 6 : 3;
  localparam int M_CFG    = RATE_250K ? 32 : 4;
  localparam int GROUP_CFG = RATE_250K ? 24 : 6;
  localparam int PREAMBLE_BITS_CFG = RATE_250K ? 96 : 48;
  localparam logic [15:0] SFD_CFG = RATE_250K ? 16'h7A23 : 16'h749C;

  // css_tx_top documents chirp_index 0..3 as m=1..4.
  // MATLAB currently uses chirpIndex=1, i.e. m=1, so drive 0 here.
  localparam logic [1:0] CHIRP_INDEX_CFG = 2'd0;

  localparam int DATA_WIDTH_CFG = 8;
  localparam int ADDR_WIDTH_CFG = 7;
  localparam int NUM_SYMBOLS_WIDTH_CFG = 12;
  localparam int ROM_WIDTH_CFG = 5;
  localparam int OUT_WIDTH_CFG = 6;

  localparam string RATE_TAG = RATE_250K ? "250kbps" : "1Mbps";

  int test_lengths [NUM_TESTS] = '{0, 1, 50, 127};

  byte unsigned payload_mem [0:MAX_PAYLOAD_BYTES-1];

  // ------------------------------- DUT I/O ---------------------------------
  logic                         clk;
  logic                         reset;
  logic                         payload_we;
  logic [ADDR_WIDTH_CFG-1:0]    payload_waddr;
  logic [DATA_WIDTH_CFG-1:0]    payload_wdata;
  logic                         start;
  logic [6:0]                   payload_length_reg;
  logic [1:0]                   chirp_index;
  //wire                          busy;
  wire                          tx_done;
  wire signed [OUT_WIDTH_CFG-1:0] tx_real;
  wire signed [OUT_WIDTH_CFG-1:0] tx_imag;
  wire                          tx_valid;
  wire                          fifo_overflow;

  css_tx_top #(
      .DATA_RATE           (RATE_250K),
      .N_IN                (N_IN_CFG),
      .M                   (M_CFG),
      .GROUP_SIZE          (GROUP_CFG),
      .PREAMBLE_TOTAL_BITS (PREAMBLE_BITS_CFG),
      .SFD                 (SFD_CFG),
      .DATA_WIDTH          (DATA_WIDTH_CFG),
      .ADDR_WIDTH          (ADDR_WIDTH_CFG),
      .NUM_SYMBOLS_WIDTH   (NUM_SYMBOLS_WIDTH_CFG),
      .ROM_WIDTH           (ROM_WIDTH_CFG),
      .OUT_WIDTH           (OUT_WIDTH_CFG)
  ) dut (
      .clk                (clk),
      .reset              (reset),
      .payload_we         (payload_we),
      .payload_waddr      (payload_waddr),
      .payload_wdata      (payload_wdata),
      .start_tx              (start),
      .payload_length (payload_length_reg),
      .chirp_index        (chirp_index),
      //.busy               (busy),
      .tx_done            (tx_done),
      .tx_real            (tx_real),
      .tx_imag            (tx_imag),
      .tx_valid           (tx_valid),
      .fifo_overflow      (fifo_overflow)
  );

  // ------------------------------- Clock -----------------------------------
  initial clk = 1'b0;
  always #(CLK_PERIOD_NS/2) clk = ~clk;

  // ------------------------------ Accounting --------------------------------
  integer total_pass;
  integer total_fail;
  integer f_real;
  integer f_imag;
  integer f_log;
  integer captured_samples;
  longint cycles_waited;
  bit timed_out;
  bit overflow_seen;
  integer f_real_hex, f_imag_hex;

  // ----------------------------- Payload input ------------------------------
  initial begin
    // Run the simulator from the project root so this relative path resolves.
    // Create verification/rtl_outputs once before simulation.
    $readmemh("../Verifications/payloads.hex", payload_mem);
  end

  // --------------------------------------------------------------------------
  // Reset. Reset is synchronous in css_tx_top, so hold it across clock edges.
  // --------------------------------------------------------------------------
  task automatic apply_reset;
    begin
      reset            = 1'b1;
      payload_we       = 1'b0;
      payload_waddr    = '0;
      payload_wdata    = '0;
      start            = 1'b0;
      payload_length_reg = '0;
      chirp_index      = CHIRP_INDEX_CFG;
      repeat (5) @(posedge clk);
      reset = 1'b0;
      repeat (2) @(posedge clk);
    end
  endtask

  // --------------------------------------------------------------------------
  // Write RAW PSDU bytes into payload RAM.
  // --------------------------------------------------------------------------
  task automatic write_payload(input int length_bytes);
    int i;
    begin
      payload_we = 1'b0;
      @(negedge clk);
      for (i = 0; i < length_bytes; i++) begin
        payload_we    = 1'b1;
        payload_waddr = i;
        payload_wdata = payload_mem[i];
        @(posedge clk);
        #1;
      end
      @(negedge clk);
      payload_we    = 1'b0;
      payload_waddr = '0;
      payload_wdata = '0;
    end
  endtask

  // --------------------------------------------------------------------------
  // Open per-case capture files.
  // --------------------------------------------------------------------------
  task automatic open_capture_files(input int length_bytes);
    string fname_real;
    string fname_imag;
    string fname_log;
    string fname_real_hex, fname_imag_hex;
    begin
      fname_real = $sformatf("../Verifications/rtl_outputs/rtl_%s_len%03d_real.txt", RATE_TAG, length_bytes);
      fname_imag = $sformatf("../Verifications/rtl_outputs/rtl_%s_len%03d_imag.txt", RATE_TAG, length_bytes);

      fname_real_hex = $sformatf("../Verifications/rtl_outputs/rtl_%s_len%03d_real.hex", RATE_TAG, length_bytes);
      fname_imag_hex = $sformatf("../Verifications/rtl_outputs/rtl_%s_len%03d_imag.hex", RATE_TAG, length_bytes);

      fname_log  = $sformatf("../Verifications/rtl_outputs/rtl_%s_len%03d_log.txt",  RATE_TAG, length_bytes);

      f_real = $fopen(fname_real, "w");
      f_imag = $fopen(fname_imag, "w");
      f_real_hex = $fopen(fname_real_hex, "w");
      f_imag_hex = $fopen(fname_imag_hex, "w");
      f_log  = $fopen(fname_log,  "w");

      if (!f_real || !f_imag || !f_log)
        $fatal(1, "Could not open RTL output files for payload length %0d", length_bytes);

      $fdisplay(f_log, "rate=%s", RATE_TAG);
      $fdisplay(f_log, "payload_length=%0d", length_bytes);
      $fdisplay(f_log, "chirp_index=%0d", CHIRP_INDEX_CFG);
      $fdisplay(f_log, "output_width=%0d", OUT_WIDTH_CFG);
      $fdisplay(f_log, "sample_index,tx_real_signed,tx_imag_signed,tx_valid,tx_done,fifo_overflow");
    end
  endtask

  task automatic close_capture_files;
    begin
      if (f_real) $fclose(f_real);
      if (f_imag) $fclose(f_imag);
      if (f_log)  $fclose(f_log);
      if (f_real_hex) $fclose(f_real_hex);
      if (f_imag_hex) $fclose(f_imag_hex);
    end
  endtask

  // --------------------------------------------------------------------------
  // One complete packet test.
  // --------------------------------------------------------------------------
  task automatic run_one_test(input int length_bytes);
    bit done_seen;
    begin
      captured_samples = 0;
      cycles_waited    = 0;
      timed_out        = 0;
      overflow_seen    = 0;
      done_seen        = 0;

      open_capture_files(length_bytes);
      apply_reset();
      write_payload(length_bytes);

      payload_length_reg = length_bytes[6:0];
      chirp_index = CHIRP_INDEX_CFG;

      // One-cycle start pulse.
      @(negedge clk);
      start = 1'b1;
      @(posedge clk);
      #1;
      start = 1'b0;

      // Capture only valid Tx samples.
      // #1 allows registered DUT outputs to settle after the clock edge.
      while (!done_seen) begin
        @(posedge clk);
        #1;
        cycles_waited++;

        if (fifo_overflow) begin
          overflow_seen = 1'b1;
          $display("[FAIL] %s L=%0d : fifo_overflow asserted", RATE_TAG, length_bytes);
        end

        if (tx_valid) begin
          $fdisplay(f_real, "%0d", $signed(tx_real));
          $fdisplay(f_imag, "%0d", $signed(tx_imag));
          // Two's complement hex format (6-bit masked)
          $fdisplay(f_real_hex, "%02h", tx_real[OUT_WIDTH_CFG-1:0]);
          $fdisplay(f_imag_hex, "%02h", tx_imag[OUT_WIDTH_CFG-1:0]);
          $fdisplay(f_log, "%0d,%0d,%0d,%0d,%0d,%0d",
                    captured_samples, $signed(tx_real), $signed(tx_imag),
                    tx_valid, tx_done, fifo_overflow);
          
          captured_samples++;
        end

        if (tx_done)
          done_seen = 1'b1;

        if (cycles_waited >= TIMEOUT_CYCLES) begin
          timed_out = 1'b1;
          done_seen = 1'b1;
        end
      end

      // Let status signals settle.
      @(negedge clk);

      $fdisplay(f_log, "done_after_cycles=%0d", cycles_waited);
      $fdisplay(f_log, "captured_samples=%0d", captured_samples);
      $fdisplay(f_log, "overflow_seen=%0d", overflow_seen);

      if (timed_out) begin
        $display("[FAIL] %s L=%0d : TIMEOUT after %0d cycles", RATE_TAG, length_bytes, cycles_waited);
        $fdisplay(f_log, "RESULT=FAIL_TIMEOUT");
        total_fail++;
      end else if (overflow_seen) begin
        $display("[FAIL] %s L=%0d : fifo_overflow asserted", RATE_TAG, length_bytes);
        $fdisplay(f_log, "RESULT=FAIL_FIFO_OVERFLOW");
        total_fail++;
      end else begin
        $display("[PASS-BASIC] %s L=%0d : done after %0d cycles, captured %0d valid samples",
                 RATE_TAG, length_bytes, cycles_waited, captured_samples);
        $fdisplay(f_log, "RESULT=PASS_BASIC_COMPLETION");
        total_pass++;
      end

      close_capture_files();
    end
  endtask

  // --------------------------------------------------------------------------
  // Main
  // --------------------------------------------------------------------------
  initial begin
    total_pass = 0;
    total_fail = 0;

    reset             = 1'b1;
    payload_we        = 1'b0;
    payload_waddr     = '0;
    payload_wdata     = '0;
    start             = 1'b0;
    payload_length_reg = '0;
    chirp_index       = CHIRP_INDEX_CFG;

    #1;

    for (int t = 0; t < NUM_TESTS; t++) begin
      run_one_test(test_lengths[t]);
    end

    $display("============================================================");
    $display("CSS PHY BASIC RTL TEST SUMMARY - %s", RATE_TAG);
    $display("Completed tests : %0d", total_pass);
    $display("Failed tests    : %0d", total_fail);
    $display("Next check      : MATLAB fixed-reference exact comparison");
    $display("============================================================");

    if (total_fail != 0)
      $fatal(1, "RTL basic testbench failed for rate %s", RATE_TAG);

    $stop;
  end

endmodule
