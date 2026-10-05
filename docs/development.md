# Hardening preparation — 2026-10-05

This repository is based on the supplied SKY26d template (initial commit
9234e50). Its existing GDS/precheck/gate-test/docs/FPGA action references remain
on `ttsky26d`, with SKY130A selected by the GDS workflow. Four tiles are allocated
as `2x2` in info.yaml. The first preparation used a 1 MHz target
(1000 ns clock period); the current 30 MHz target is recorded below. Density
and hold margins retain template values.

The source comes from the fpudiss multi-cycle FP32 design. Its FPGA predecessor
passed 1,115 physical FabricFox arithmetic cases at 1 MHz. That hardware result
belongs to the previous FPGA bitstream, not to an ASIC netlist produced here.
The original floating-point project was by Pirvu Ilie-Sergiu (2025); this
submission integrates the corrected multi-cycle implementation and byte wrapper.

Integration changes:

- Renamed the TT top to tt_um_calincalin644_fpu_fp32 and copied the iterative core
  into src/. The parallel reference FPU and FPGA primitives are not included.
- Made exponent truncation to the encoded field/counter explicit and marked
  intentionally unused bits. Numerical behavior is unchanged in regression.
- Replaced example metadata, pin descriptions, datasheet and README.
- Replaced the example test with external-pin cocotb tests usable for RTL and
  GL, plus a full RTL regression invoked by the test workflow. The oracle uses
  exact Python rational arithmetic.
- Used CURDIR in the test Makefile so make -C works; preserved the supplied
  gate-level power wires and standard PDK model/netlist setup. Wave dumps are
  opt-in to avoid very large artifacts on long regressions.

Local checks completed:

| Check | Result |
|---|---|
| Full RTL pin regression | 54,742 vectors plus protocol/reset/ena checks passed |
| Cocotb RTL | 2 tests passed; 1,115 arithmetic cases plus protocol/abort coverage |
| Cocotb mapped SKY130 gates | Same 2 tests and 1,115 arithmetic cases passed |
| Metadata/workflow checks | Four tiles, clock, source files, all 24 pin entries and SKY26d action refs agree |
| Diff whitespace check | Passed |

Tools: Icarus 12.0, cocotb 2.1.0, Yosys 0.33, Python 3.12 locally. CI retains the
supplied Python 3.11 setup and pins cocotb 2.1.0 via test/requirements.txt.

The local gate test used a fresh mapped netlist of this repository's sources
and local SKY130 functional models. Power connections were added to that test
netlist. This validates synthesized functionality and the shared GL testbench;
it is not a routed netlist, SDF timing test, or hardening result. GitHub's gl_test
job will use the actual netlist from its matching GDS run.

The handoff's local synthesis recipe reports **31,071.0496 um2** of mapped cells
for this integration, before clock-tree/physical overhead. This is a new mapping
measurement, not a reuse of the FPGA prototype's prior 31,013.4944-um2 estimate.
No four-tile physical fit has been proven. Source hashes and verification summary
are recorded in validation.json; local detailed logs are under test/output/.

Verilator was unavailable locally. An attempted package download failed because
the configured package mirror could not be resolved. No local Verilator pass is
claimed. The hardening flow's linter remains enabled; no linter suppression,
false path, multicycle exception, or disabled physical check was introduced.

GitHub Actions have not been dispatched and no commit or push was made by this
preparation step. After pushing, inspect the GDS, precheck and GL test jobs and
retain their exact run URL, commit, logs and submission artifact before assessing
physical readiness.


## 18 MHz initial hardening target

The user selected 18 MHz as the initial target, superseding the briefly proposed
20 MHz experiment before any hardening run. Set clock_hz to 18,000,000 and
CLOCK_PERIOD to 55.555556 ns; the four-tile 2x2 allocation is unchanged.
Cocotb uses a 55,556 ps clock (rounded to the simulator's 1 ps resolution) and
5 ns bus setup/sample delays. Prior physical FPGA results remain at 1 MHz;
neither its bitstream nor board clock was changed. Functional simulation does
not establish ASIC timing closure; the hardening flow must verify the new target.

At the updated test clock, both RTL and local mapped-netlist cocotb suites
passed: 2 tests each, including 1,115 exact arithmetic cases and protocol/abort
checks. These are functional checks without SDF; 18 MHz timing is unproven.


## 30 MHz hardening experiment

Set clock_hz to 30,000,000 and CLOCK_PERIOD to 33.333333 ns. Keep the
four-tile 2x2 allocation, placement density, repair margins, and RTL unchanged
to isolate the effect of the tighter clock target. Cocotb uses a 33,334 ps
period, rounded to an even number of picoseconds for equal half-cycles at
1 ps simulator resolution; bus setup/sample delays remain 5 ns.

The preceding 18 MHz routed run reported 32.640656 ns worst setup slack,
but also slew and capacitance violations. This motivates the experiment;
it does not establish timing closure at 30 MHz. The next GitHub hardening
run must verify setup, hold, electrical checks, and physical area.
