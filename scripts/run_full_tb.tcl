# Create work library and output directory
vlib work
vmap work work
#file mkdir rtl_outputs
# Collect all Verilog and SystemVerilog files in the current directory

# ==============================================================================
# 1. RUN 1 Mbps SIMULATION (DUT_RATE = 0)
# ==============================================================================
echo "========================================================="
echo "  COMPILING & RUNNING 1 Mbps SIMULATION (DUT_RATE = 0)"
echo "========================================================="
vlog +define+DUT_RATE=0 -f ../scripts/source_file.txt 
vsim -voptargs=+acc work.tb

radix define ppdu_state {
    "3'd0" S_IDLE
    "3'd1" S_PREAMBLE
    "3'd2" S_PAYLOAD_WAIT
    "3'd3" S_PAYLOAD_SHIFT
    -default default
}

radix define css_gen_state {
    "3'd0" S_IDLE
    "3'd1" S_REQ_SYM
    "3'd2" S_WAIT_SYM
    "3'd3" S_STREAM
    "3'd4" S_GAP
    "3'd5" S_DONE
    -default default
}

# add wave *
do ../scripts/wave.do

run -all

# # ==============================================================================
# # 2. RUN 250 kbps SIMULATION (DUT_RATE = 1)
# # ==============================================================================
# echo "========================================================="
# echo "  COMPILING & RUNNING 250 kbps SIMULATION (DUT_RATE = 1)"
# echo "========================================================="
# eval vlog -work work +define+DUT_RATE=1 $src_files
# vsim -c tb
# run -all
# quit -sim

echo "========================================================="
echo "  ALL SIMULATIONS COMPLETE. Check /rtl_outputs folder."
echo "========================================================="