onerror {resume}
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
add wave -noupdate /tb/captured_samples
add wave -noupdate -color Pink /tb/overflow_seen
add wave -noupdate -divider TOP
add wave -noupdate -group TOP /tb/payload_we
add wave -noupdate -group TOP /tb/payload_waddr
add wave -noupdate -group TOP /tb/payload_wdata
add wave -noupdate -group TOP /tb/start
add wave -noupdate -group TOP /tb/payload_length_reg
add wave -noupdate -group TOP /tb/chirp_index
add wave -noupdate -group TOP /tb/tx_done
add wave -noupdate -group TOP -radix unsigned /tb/tx_real
add wave -noupdate -group TOP -radix unsigned /tb/tx_imag
add wave -noupdate -group TOP /tb/tx_valid
add wave -noupdate -group TOP /tb/fifo_overflow
add wave -noupdate -group {not needed} /tb/got_real_dbg
add wave -noupdate -group {not needed} /tb/got_imag_dbg
add wave -noupdate -group {not needed} /tb/cycles_waited
add wave -noupdate -group {not needed} /tb/timed_out
add wave -noupdate -divider {tx out}
add wave -noupdate -expand -group imag /tb/got_imag_dbg
add wave -noupdate -expand -group imag -radix unsigned /tb/exp_imag_dbg
add wave -noupdate -expand -group real /tb/got_real_dbg
add wave -noupdate -expand -group real -radix unsigned /tb/exp_real_dbg
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {164829 ps} 0}
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
WaveRestoreZoom {146289 ps} {213132 ps}
