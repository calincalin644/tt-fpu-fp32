#!/usr/bin/env python3
"""Full, portable RTL pin regression, complementing the RTL/GL cocotb suite."""
import hashlib
import os
from pathlib import Path
import shlex
import subprocess
from reference import vectors
ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'test/sim_build/full'
BUILD.mkdir(parents=True,exist_ok=True)
path=BUILD/'vectors.txt'
with path.open('w') as f:
    for count,v in enumerate(vectors(12000),1):
        op,rm,a,b,fixed,out,flags=v
        f.write(f'{op} {rm} {a:08x} {b:08x} {fixed:08x} {out:08x} {flags:02x}\n')
sources=[ROOT/'src/flpoint_iterative.sv',ROOT/'src/tt_um_calincalin644_fpu_fp32.v',ROOT/'test/pins_tb.sv']
cmd=shlex.split(os.environ.get('IVERILOG','iverilog'))
cmd+=['-g2012','-s','pins_tb','-o',str(BUILD/'test.vvp')]+list(map(str,sources))
subprocess.run(cmd,check=True)
r=subprocess.run(shlex.split(os.environ.get('VVP','vvp'))+[str(BUILD/'test.vvp'),f'+vectors={path}'],text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=180)
(BUILD/'simulation.log').write_text(r.stdout)
print(r.stdout,end='')
(BUILD/'sha256.txt').write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(ROOT)}\n' for p in sources+[ROOT/'test/reference.py',Path(__file__).resolve(),path]))
if r.returncode or f'PASS: {count} pin-level' not in r.stdout: raise SystemExit(r.returncode or 1)
