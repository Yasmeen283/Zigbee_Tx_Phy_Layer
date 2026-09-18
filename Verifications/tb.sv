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


  // ---------------- golden reference ----------------
  localparam string GOLD_DIR              = "test_vectors";
  localparam bit    STOP_ON_FIRST_MISMATCH = 1'b0;   // set 1 to break into the waveform

  // 1 Mbps, chirp_index=0 (m=1): Tgap = 10 / 70, 4*Tsub = 152
  localparam int SEQ_SAMPLES = 152;
  localparam int GAP_EVEN    = 10;
  localparam int GAP_ODD     = 70;

  int  gold_real [];
  int  gold_imag [];
  int  gold_len;

  // waveform-visible debug signals - add these to the wave window
  int  sample_index;
  int  exp_real_dbg, exp_imag_dbg;
  int  got_real_dbg, got_imag_dbg;
  bit  mismatch_pulse;
  int  mismatch_count;
  int  first_mismatch_idx;
  time first_mismatch_time;

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

  // Helper: Enforce 3-digit zero padding without space artifact issues
  function automatic string format_len3(input int len);
    if (len < 10)
      return $sformatf("00%0d", len);
    else if (len < 100)
      return $sformatf("0%0d", len);
    else
      return $sformatf("%0d", len);
  endfunction

  
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

  // Open per-case capture files.
  task automatic open_capture_files(input int length_bytes);
    string len_str;
    string fname_real, fname_imag, fname_log, fname_real_hex, fname_imag_hex;
    begin
      len_str = format_len3(length_bytes);
      fname_real = $sformatf("../Verifications/rtl_outputs/rtl_%s_len%s_real.txt", RATE_TAG, len_str);
      fname_imag     = $sformatf("../Verifications/rtl_outputs/rtl_%s_len%s_imag.txt", RATE_TAG, len_str);

      fname_real_hex = $sformatf("../Verifications/rtl_outputs/rtl_%s_len%s_real.hex", RATE_TAG, len_str);
      fname_imag_hex = $sformatf("../Verifications/rtl_outputs/rtl_%s_len%s_imag.hex", RATE_TAG, len_str);
      fname_log      = $sformatf("../Verifications/rtl_outputs/rtl_%s_len%s_log.txt",  RATE_TAG, len_str);

      f_real = $fopen(fname_real, "w");
      f_imag = $fopen(fname_imag, "w");
      f_real_hex = $fopen(fname_real_hex, "w");
      f_imag_hex = $fopen(fname_imag_hex, "w");
      f_log  = $fopen(fname_log,  "w");

      if (!f_real || !f_imag || !f_log)
        $error(1, "Could not open RTL output files for payload length %0d", length_bytes);

      $fdisplay(f_log, "rate=%s ", RATE_TAG);
      $fdisplay(f_log, "payload_length=%0d ", length_bytes);
      $fdisplay(f_log, "chirp_index=%0d ", CHIRP_INDEX_CFG);
      $fdisplay(f_log, "output_width=%0d ", OUT_WIDTH_CFG);
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

  // One complete packet test.
  task automatic run_one_test(input int length_bytes);
    bit done_seen;
    begin
      captured_samples = 0;
      cycles_waited    = 0;
      timed_out        = 0;
      overflow_seen    = 0;
      done_seen        = 0;
      mismatch_count      = 0;
      first_mismatch_idx  = -1;
      first_mismatch_time = 0;
      mismatch_pulse      = 1'b0;
      sample_index        = 0;
      load_golden(length_bytes);

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

                mismatch_pulse = 1'b0;

        if (tx_valid) begin
          sample_index = captured_samples;
          got_real_dbg = $signed(tx_real);
          got_imag_dbg = $signed(tx_imag);
          // got_real_dbg = tx_real;
          // got_imag_dbg = tx_imag;

          $fdisplay(f_real, "%0d", got_real_dbg);
          $fdisplay(f_imag, "%0d", got_imag_dbg);
          $fdisplay(f_real_hex, "%02h", tx_real[OUT_WIDTH_CFG-1:0]);
          $fdisplay(f_imag_hex, "%02h", tx_imag[OUT_WIDTH_CFG-1:0]);

          if (captured_samples < gold_len) begin
            exp_real_dbg = gold_real[captured_samples];
            exp_imag_dbg = gold_imag[captured_samples];

            if ((got_real_dbg !== exp_real_dbg) || (got_imag_dbg !== exp_imag_dbg)) begin
              mismatch_pulse = 1'b1;
              mismatch_count++;

              if (first_mismatch_idx < 0) begin
                first_mismatch_idx  = captured_samples;
                first_mismatch_time = $time;
                $display("[MISMATCH] %s L=%0d FIRST at sample %0d, t=%0t : rtl=(%0d,%0d) exp=(%0d,%0d)",
                         RATE_TAG, length_bytes, captured_samples, $time,
                         got_real_dbg, got_imag_dbg, exp_real_dbg, exp_imag_dbg);
                locate_sample(captured_samples);
                if (STOP_ON_FIRST_MISMATCH) $stop;
              end

              if (mismatch_count <= 20)
                $fdisplay(f_log, "MISMATCH idx=%0d rtl=(%0d,%0d) exp=(%0d,%0d) negated=%0d",
                          captured_samples, got_real_dbg, got_imag_dbg,
                          exp_real_dbg, exp_imag_dbg,
                          ((got_real_dbg == -exp_real_dbg) && (got_imag_dbg == -exp_imag_dbg)));
            end
          end

          $fdisplay(f_log, "%0d,%0d,%0d,%0d,%0d,%0d",
                    captured_samples, got_real_dbg, got_imag_dbg,
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

            if (gold_len > 0) begin
        int tail_ok; tail_ok = 1;
        for (int k = captured_samples; k < gold_len; k++)
          if (gold_real[k] != 0 || gold_imag[k] != 0) tail_ok = 0;

        if (gold_len != captured_samples)
          $display("%s %s L=%0d : length %0d vs golden %0d (%0d trailing golden samples, all-zero=%0d)",
                   tail_ok ? "[INFO]" : "[FAIL]", RATE_TAG, length_bytes,
                   captured_samples, gold_len, gold_len-captured_samples, tail_ok);

        if (mismatch_count == 0 && tail_ok)
          $display("[PASS-EXACT] %s L=%0d : bit-exact over %0d samples", RATE_TAG, length_bytes, captured_samples);
        else begin
          $display("[FAIL-DATA]  %s L=%0d : %0d mismatches, first at sample %0d (t=%0t)",
                   RATE_TAG, length_bytes, mismatch_count, first_mismatch_idx, first_mismatch_time);
          total_fail++;
        end
        $fdisplay(f_log, "mismatches=%0d first_mismatch_idx=%0d", mismatch_count, first_mismatch_idx);
      end

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

  task automatic load_golden(input int length_bytes);
    int fdr, fdi, vr, vi, n;
    string fr, fi, len_str;
    begin
      len_str   = format_len3(length_bytes);
      fr = $sformatf("../Verifications/%s/mat_%s_len%s_real.txt", GOLD_DIR, RATE_TAG, len_str);
      fi = $sformatf("../Verifications/%s/mat_%s_len%s_imag.txt", GOLD_DIR, RATE_TAG, len_str);

      gold_len  = 0;
      gold_real = new[600000];
      gold_imag = new[600000];

      fdr = $fopen(fr, "r");
      fdi = $fopen(fi, "r");
      if (fdr == 0 || fdi == 0) begin
        $display("[WARN] golden files missing (%s) - capture only, no checking", fr);
        return;
      end

      n = 0;
      while (($fscanf(fdr, "%d", vr) == 1) && ($fscanf(fdi, "%d", vi) == 1)) begin
        gold_real[n] = vr;
        gold_imag[n] = vi;
        n++;
      end
      $fclose(fdr); $fclose(fdi);
      gold_len = n;
      $display("[INFO] loaded %0d golden samples for %s L=%0d", gold_len, RATE_TAG, length_bytes);
    end
  endtask

  // Map a sample index to (chirp sequence, subchirp/gap, DQPSK symbol number)
  task automatic locate_sample(input int idx);
    int pos, seq, len, off, sub;
    begin
      pos = 0; seq = 0;
      forever begin
        len = SEQ_SAMPLES + ((seq % 2 == 0) ? GAP_EVEN : GAP_ODD);
        if (idx < pos + len) break;
        pos += len; seq++;
      end
      off = idx - pos;
      sub = off / 38;
      if (off >= SEQ_SAMPLES)
        $display("        -> chirp sequence %0d, IN THE GAP (offset %0d)", seq, off - SEQ_SAMPLES);
      else
        $display("        -> chirp sequence %0d, subchirp k=%0d, DQPSK symbol %0d, sample %0d of 38",
                 seq, sub, seq*4 + sub, off % 38);
      if (seq*4 + sub < PREAMBLE_BITS_CFG)
        $display("        -> this is still in PREAMBLE/SFD (symbols 0..%0d)", PREAMBLE_BITS_CFG-1);
      else
        $display("        -> this is in the PAYLOAD (first payload symbol = %0d)", PREAMBLE_BITS_CFG);
    end
  endtask

  // Main
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
      $error(1, "RTL basic testbench failed for rate %s", RATE_TAG);

    $stop;
  end

endmodule
