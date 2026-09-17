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

add wave *

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