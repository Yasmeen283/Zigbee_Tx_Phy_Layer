onerror {resume}
radix define ppdu_state {
    "3'd0" "S_IDLE",
    "3'd1" "S_PREAMBLE",
    "3'd2" "S_PAYLOAD_WAIT",
    "3'd3" "S_PAYLOAD_SHIFT",
    -default default
}
radix define css_gen_state {
    "3'd0" "S_IDLE",
    "3'd1" "S_REQ_SYM",
    "3'd2" "S_WAIT_SYM",
    "3'd3" "S_STREAM",
    "3'd4" "S_GAP",
    "3'd5" "S_DONE",
    -default default
}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb/clk
add wave -noupdate /tb/reset
add wave -noupdate /tb/total_pass
add wave -noupdate /tb/total_fail
add wave -noupdate -radix unsigned /tb/sample_index
add wave -noupdate /tb/gold_len
add wave -noupdate /tb/mismatch_pulse
add wave -noupdate /tb/mismatch_count
add wave -noupdate /tb/first_mismatch_idx
add wave -noupdate -radix unsigned /tb/captured_samples
add wave -noupdate -color Pink /tb/overflow_seen
add wave -noupdate -divider TOP
add wave -noupdate -expand -group TOP /tb/payload_we
add wave -noupdate -expand -group TOP /tb/payload_waddr
add wave -noupdate -expand -group TOP /tb/payload_wdata
add wave -noupdate -expand -group TOP /tb/start
add wave -noupdate -expand -group TOP -radix unsigned /tb/payload_length_reg
add wave -noupdate -expand -group TOP /tb/chirp_index
add wave -noupdate -expand -group TOP /tb/tx_done
add wave -noupdate -expand -group TOP -radix unsigned /tb/tx_real
add wave -noupdate -expand -group TOP -radix unsigned /tb/tx_imag
add wave -noupdate -expand -group TOP /tb/tx_valid
add wave -noupdate -expand -group TOP /tb/fifo_overflow
add wave -noupdate -group {not needed} /tb/got_real_dbg
add wave -noupdate -group {not needed} /tb/got_imag_dbg
add wave -noupdate -group {not needed} /tb/cycles_waited
add wave -noupdate -group {not needed} /tb/timed_out
add wave -noupdate -divider {tx out}
add wave -noupdate -expand -group imag -radix decimal /tb/got_imag_dbg
add wave -noupdate -expand -group imag -radix decimal /tb/exp_imag_dbg
add wave -noupdate -expand -group real -radix decimal /tb/got_real_dbg
add wave -noupdate -expand -group real -radix decimal /tb/exp_real_dbg
add wave -noupdate -divider {ppdu former}
add wave -noupdate -radix ppdu_state /tb/dut/u_interleaver_ppdu/u_ppdu_former/state
add wave -noupdate -divider {css generator}
add wave -noupdate -radix css_gen_state /tb/dut/u_tx_datapath/u_css_symbol_generator/u_csk_generator/state
add wave -noupdate -radix unsigned /tb/dut/u_tx_datapath/u_css_symbol_generator/u_csk_generator/symbol_count
add wave -noupdate -divider dqpsk
add wave -noupdate -group dqpsk /tb/dut/u_tx_datapath/u_dqpsk_encoder/dqpsk_sign_imag
add wave -noupdate -group dqpsk /tb/dut/u_tx_datapath/u_dqpsk_encoder/dqpsk_sign_real
add wave -noupdate -group dqpsk /tb/dut/u_tx_datapath/u_dqpsk_encoder/dqpsk_valid
add wave -noupdate -group dqpsk /tb/dut/u_tx_datapath/u_dqpsk_encoder/si_q
add wave -noupdate -group dqpsk /tb/dut/u_tx_datapath/u_dqpsk_encoder/sr_q
add wave -noupdate -divider controller
add wave -noupdate -expand -group controller /tb/dut/u_controller/dp_i_bit
add wave -noupdate -expand -group controller /tb/dut/u_controller/dp_q_bit
add wave -noupdate -expand -group controller /tb/dut/u_controller/dp_qpsk_valid
add wave -noupdate -expand -group cw /tb/dut/u_controller/cw_count
add wave -noupdate -expand -group cw /tb/dut/u_controller/cw_i
add wave -noupdate -expand -group cw /tb/dut/u_controller/cw_q
add wave -noupdate -expand -group cw /tb/dut/u_controller/cw_rptr
add wave -noupdate -expand -group cw /tb/dut/u_controller/cw_wptr
add wave -noupdate -divider {symbol mapper}
add wave -noupdate -expand -group cw_i /tb/dut/u_frontend/u_mapper_i/codeword_out
add wave -noupdate -expand -group cw_i /tb/dut/u_frontend/u_mapper_i/codeword_valid
add wave -noupdate -expand -group cw_q /tb/dut/u_frontend/u_mapper_q/codeword_out
add wave -noupdate -expand -group cw_q /tb/dut/u_frontend/u_mapper_q/codeword_valid
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 9} {90066326 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 150
configure wave -valuecolwidth 141
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {89883646 ps} {90148330 ps}
