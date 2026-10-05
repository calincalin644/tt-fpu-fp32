# FPU verification

`make` runs the cocotb tests in `test.py` through `tb.v`, which instantiates
`tt_um_calincalin644_fpu_fp32`. No hierarchical forcing or internal RTL signal
access is used. Check the result explicitly:

```sh
make
python -m cocotb_tools.check_results results.xml
```

`protocol_and_abort` checks reset, register access, invalid writes, writes during
busy, result retention and ena abort. `exact_arithmetic` checks 1,115 arithmetic
vectors and all five exception flags against `reference.py` (exact rationals).

For the full 54,742-vector RTL pin regression:

```sh
python run_full.py
```

GitHub's gate-test action supplies `gate_level_netlist.v` and the PDK. The same
cocotb tests run with `make GATES=yes`; tb.v connects VPWR/VGND through wires.
This checks the netlist from that specific hardening run.

Waveform dumping is opt-in: `make SIM_ARGS="-fst +WAVES"`. Generated simulator
files and logs are ignored by Git. See ../docs/development.md for completed
local verification and its limits.
