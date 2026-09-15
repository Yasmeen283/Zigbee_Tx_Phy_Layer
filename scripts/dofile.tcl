vlib work
vlog -f ../scripts/source_file.txt
vsim -voptargs=+acc work.tb_interleaver_ppdu_top

add wave *

run -all