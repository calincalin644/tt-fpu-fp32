## How it works

This is a multi-cycle FP32 arithmetic unit with an acknowledged byte interface.
Binary32 values have one sign bit, eight exponent bits and 23 fraction bits.
The core supports signed zero, subnormal numbers, infinities and NaNs. It uses
iterative alignment/normalization, a 24-step multiplier and a 28-step divider;
overall latency depends on the operands. Poll completion rather than assuming
a fixed number of cycles.

The current SKY26d hardening target is four tiles (`2x2`) at 30 MHz. This allocation
is a physical implementation trial, not a claim of successful hardening.

### Operations

| Command | Operation |
|---|---|
| 1 | A + B |
| 2 | A - B |
| 3 | A * B |
| 4 | A / B |
| 5 | Fixed-point A to FP32 |
| 6 | FP32 A to fixed point |
| 7 | Invalid operation: canonical NaN and NV |

The fixed-point representation is **sign-magnitude**, not two's complement:
`value = (-1)^word[31] * word[30:0] / 32768`. Both signs of zero are supported.
Conversions ignore B. Float-to-fixed results outside the representable magnitude
saturate to maximum magnitude with NV; infinity preserves its sign and NaNs
produce positive maximum magnitude. Valid inexact conversions set NX.

### Rounding and exceptions

Rounding codes are 0 = nearest/even, 1 = toward zero, 2 = toward negative
infinity, 3 = toward positive infinity, 4 = nearest/ties away. Codes 5–7 produce
NV and canonical NaN (positive maximum magnitude for fixed output).

Flags [4:0] are NV, DZ, OF, UF, NX. They describe the last completed operation,
not accumulated history. NaNs are canonicalized to `0x7fc00000`; signaling NaNs
set NV. Underflow requires inexactness and uses **tininess before rounding**.
Overflow returns infinity or maximum finite magnitude according to rounding
mode and sign. This is not a claim of complete RISC-V F-extension compliance.

## How to test

### Pins

| Pins | Direction from chip | Function |
|---|---|---|
| ui_in[7:0] | Input | Write byte |
| uo_out[7:0] | Output | Registered read byte |
| uio[0] | Input | Request toggle |
| uio[1] | Input | Read=1, write=0 |
| uio[5:2] | Input | Register address |
| uio[6] | Output | Acknowledge toggle |
| uio[7] | Output | Busy |
| clk | Input | 30 MHz clock target |
| rst_n | Input | Active-low reset; hold for multiple clock edges |

The chip drives only BIDIR bits 6 and 7 (`uio_oe=0xc0`). A controller driving
bits 0–5 must leave bits 6–7 as inputs. Dedicated outputs are always driven.

### Register map

All 32-bit words transfer **least-significant byte first**.

| Address | Access | Meaning |
|---|---|---|
| 0–3 | R/W | Operand A or fixed input |
| 4–7 | R/W | Operand B |
| 8 | R/W | Write `{00, rounding[2:0], command[2:0]}` to start; read current core command/mode |
| 9–12 | R | Last completed result, FP32 or fixed |
| 13 | R | Last result's exception flags |
| 14 | R/W | Read bit 0=busy, bit 1=done, bit 2=protocol error; write when idle to clear done/error |
| 15 | R | Protocol ID `0xf1` |

Hold request at zero during reset. For each transfer:

1. Set address, direction and write data while request is unchanged.
2. Allow data/control to settle, then toggle request.
3. Keep data/control stable until acknowledge matches request.
4. For a read, allow output propagation to settle and sample uo_out.
5. Begin the next transfer only after acknowledgement.

The tested 1 MHz host driver uses 2 microseconds of setup before toggling request
and 2 microseconds after seeing acknowledge. Request alone is synchronized with
two FFs; the stable bundled data/control establish multi-bit coherence.

A start sets busy and clears previous done/error. Completion captures result and
flags, clears busy, and latches done. Writes while busy are acknowledged but
ignored and set protocol error. Reads remain available. Operation 0, reserved
control bits 7:6, and writes to read-only registers produce protocol errors.
Operand writes alone retain the previous result/done. There is no command queue.

`ena=0` aborts an operation and clears wrapper state on a clock edge. It does not
gate the clock. Return request to zero while disabled/reset before restarting.

### Example: 1.5 + 2.25

Write A=`0x3fc00000` to addresses 0–3 and B=`0x40100000` to addresses 4–7.
Write `0x01` to address 8 (addition, nearest/even). Poll address 14 for done;
then addresses 9–12 must return `0x40700000` (3.75), and address 13 must be zero.

The repository's cocotb tests exercise this protocol on both RTL and gate-level
netlists. They also test exception flags, all rounding modes, busy write rejection,
held requests, reset and enable/disable behavior.

## External hardware

A controller capable of driving the input bus and reading the output bus is
required; no display or PMOD is needed. The Tiny Tapeout RP2350 demo board can
serve as the controller. For that setup, set INPUT DIP switches off, disconnect
INPUT/BIDIR peripherals, and use RP2350 BIDIR output-enable mask `0x3f`.
