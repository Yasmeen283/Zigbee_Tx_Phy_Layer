vlib work
vlog -f ../scripts/source_file.txt
vsim -voptargs=+acc work.tb_zero_padding

add wave *

run -all