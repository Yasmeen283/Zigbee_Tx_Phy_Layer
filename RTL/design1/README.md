# CSS PHY Transmitter — RTL Package

This completes the transmitter chain per the project spec (Section 5.1) and
the deep-dive doc's block list, following the recommended build order:

  Symbol Mapper → Zero Padding/Demux → Interleaver → Preamble/SFD ROM →
  QPSK Mapper → DQPSK encoder → CSK Generator/chirp ROM → top-level
  controller/integration

## What's new in this pass

| Block (spec §5.1)                          | File                     | Testbench                |
|---------------------------------------------|---------------------------|---------------------------|
| Zero-padding / payload framer (Block 1)      | `rtl/zero_padding.v`      | `tb/tb_zero_padding.v`    |
| Demux (I/Q bit splitter) (Block 2)           | `rtl/demux_iq.v`          | `tb/tb_demux_iq.v`        |
| QPSK Mapper (Block 5.2)                      | `rtl/qpsk_mapper.v`       | `tb/tb_qpsk_mapper.v`     |
| DQPSK differential encoder (Block 6)         | `rtl/dqpsk_encoder.v`     | `tb/tb_dqpsk_encoder.v`   |
| CSK Generator / chirp ROM (Block 7)          | `rtl/chirp_rom.v`         | `tb/tb_chirp_rom.v`       |
| Chirp Modulation / DQCSK (Block 8)           | `rtl/css_modulator.v`     | `tb/tb_css_modulator.v`   |
| **Top-level transmitter (Section 5)**        | `rtl/css_tx_top.v`        | `tb/tb_css_tx_top.v`      |

Carried over from the previous pass (unchanged): `symbol_mapper.v`,
`interleaver.v`, `preamble_sfd_rom.v` + `tb_preamble_sfd.v`.

New ROM vector files (`vectors/`), generated from the project's own MATLAB
outputs / the standard's Hadamard construction, since no `vectors/` folder
was supplied:
- `symbol_mapper_1mbps.mem`, `symbol_mapper_250kbps.mem` — bi-orthogonal
  Walsh–Hadamard codeword tables (`hadamard(4)`/`hadamard(32)` stacked with
  their negation, Section 6.2 of the deep-dive doc).
- `preamble_sfd_1mbps.mem` — from the supplied `preambleSFD.txt`.
- `preamble_sfd_250kbps.mem` — 80 ones + the 250 kbps SFD pattern (matches
  the value already hard-coded as the expected result in `tb_preamble_sfd.v`).
- `chirp_m1.mem` — exact copy of the supplied `chirpSequence.txt`
  (chirpIndex = 1, the project default): 152 real + 152 imag 6-bit
  two's-complement samples.
- `payload.mem` — copy of the supplied `payload.txt`, used by the
  integration testbench.

## Scope note

`css_tx_top.v` implements the **1 Mbps** data path end-to-end (the project
spec explicitly allows a single-rate implementation as a reduced-scope
option). `interleaver.v` is verified standalone; wiring it in between the
Symbol Mapper and QPSK Mapper (gated on a `DATA_RATE` parameter) is the only
extra step a 250 kbps extension of the controller needs.

`chirpIndex` is fixed to **m = 1** (`simulationParameters.m`'s own default),
via `CHIRP_MEMFILE`. Swap in a different `vectors/chirp_mN.mem` (152 real +
152 imag 6-bit samples for that index) and the matching `TEVEN`/`TODD`
values from Table 15 of the reference doc to support another chirp index.

## Top-level interface

Matches Table 3-1 / Table 17 of the reference document exactly
(`clk`, `reset`, `start_Tx`, `PayloadLength`, `done_Tx`, `Tx_real`,
`Tx_imag`), plus two additions the spec explicitly permits ("add internal
signals as needed"): a `payload_wr_en/addr/data` write port so the MAC can
fill the 127×8 payload RAM before asserting `start_Tx` (mirrors the
reference architecture's own payload-RAM description), and a `tx_valid`
strobe (high on cycles carrying a real modulated sample, low during the
inter-chirp-sequence gap) that's convenient for simulation/ChipScope capture
but not required by a real DAC.

## Verification status

Unit testbenches for the 5 new datapath blocks are self-checking against
hand-derived / independently-modeled expected values (see comments in each
`tb_*.v`). No full-chain bit-exact MATLAB golden-vector file was included
among the project inputs (only per-block references — `chirpSequence.txt`,
`preambleSFD.txt`, `payload.txt`), so `tb_css_tx_top.v` self-checks against:

1. The exact worked-example arithmetic in Section 13 of the deep-dive doc
   for `payloadLength = 25` (`padded_total_bits=216`, `n_codewords/path=36`,
   `n_groups=48`, total modulated samples `= 48*152 = 7296`).
2. A bit-exact hand-derived sample: the packet's first 4 DQPSK symbols are
   all `(1,1)` (preamble is constant, and the initial DQPSK memory is
   `1+j1`), so the last sample of the first chirp sequence (`chirp_rom`
   address 151, which is `(-31, 0)` in `chirp_m1.mem`) must produce
   `Tx = (1+j1)*(-31+j0) = (-31, -31)`.

To run with a simulator (e.g. Icarus Verilog) from this directory:

```bash
iverilog -g2001 -o sim rtl/*.v tb/tb_css_tx_top.v && vvp sim
```

(swap `tb_css_tx_top.v` for any other testbench to run it standalone; each
one only needs the specific `rtl/*.v` files it depends on, but including all
of `rtl/*.v` is harmless since Verilog ignores unused modules.)

## Still open (per the project's own "Deliverables" list, Section 9)

- Behavioral-simulation waveform capture/screenshots (needs an actual
  simulator run — see command above).
- The MSE accuracy report comparing this RTL's fixed-point output against
  the floating-point MATLAB reference (Section 3.3 of the project doc);
  `chirp_m1.mem` already *is* the fixed-point golden data, so this mainly
  needs the floating-point chirp samples from `chirpSequenceGenerator.m` to
  diff against.
- Synthesis/implementation (utilization + timing) once a target FPGA/toolchain
  is chosen.
- A 250 kbps extension of `css_tx_top.v` (wire in `interleaver.v`, swap the
  `250kbps` vector files, use `N_IN=6,M_OUT=32` Symbol Mapper instances).
