vlib work
vlog -f ../scripts/source_file.txt
vsim -voptargs=+acc work.tb_css_tx_frontend

add wave *

run -all