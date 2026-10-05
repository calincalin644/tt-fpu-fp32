# FP32 Arithmetic Unit — Tiny Tapeout SKY26d

Multi-cycle binary32 addition, subtraction, multiplication, division, and
conversion to/from 32-bit sign-magnitude fixed point with 15 fractional bits.
Operands and results use an acknowledged byte interface.

- **Allocation:** `2x2` = four tiles.
- **Clock target:** 18 MHz (`clock_hz: 18000000`, `CLOCK_PERIOD: 55.555556` ns).
- **Top:** `tt_um_calincalin644_fpu_fp32`.
- **Process/workflow:** SKY130A, `TinyTapeout/tt-gds-action@ttsky26d`.
- [Pin protocol and numerical behavior](docs/info.md).
- [Validation and provenance](docs/development.md).

## Start hardening

Commit and push this repository's changes to GitHub. The `gds`, `test`, and
`docs` workflows run on push. Alternatively, after the changes are on GitHub,
open **Actions → gds → Run workflow** and select the branch containing them:

https://github.com/calincalin644/tt-fpu-fp32/actions/workflows/gds.yaml

The GDS workflow runs hardening, followed by precheck and gate-level tests.
Inspect **all three** before treating the design as ready. Download `GDS_logs`
and `tt_submission` artifacts from that exact run. The optional viewer job
uses GitHub Pages; configure the repository's Pages source as GitHub Actions
if you want the layout viewer. Its deployment is separate from the GDS result.

No hardening run or four-tile fit has yet been established for this repository.
The default placement density and hold-repair settings are retained. No timing
exceptions or disabled lint checks were added.

## Local tests

With Python, Icarus Verilog and vvp available:

```sh
python -m pip install -r test/requirements.txt
cd test
make
python -m cocotb_tools.check_results results.xml
cd ..
python test/run_full.py
```

The cocotb suite checks 1,115 exact-reference arithmetic cases plus protocol,
reset and disable behavior using only external pins; it is also used by the
post-hardening gate-level workflow. The standalone full RTL test checks 54,742
vectors. Expected results use exact rational arithmetic, not host float math.
To generate waveforms, run `make SIM_ARGS="-fst +WAVES"` from `test/`.

The source is self-contained in `src/`; no files from the parent workspace,
FPGA primitives, original parallel FPU, board software, or game logic are
needed by GitHub Actions.
