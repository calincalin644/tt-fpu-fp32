"""Exact rational FP32 oracle; no host float arithmetic or RTL internal access."""
from fractions import Fraction
import random

NV, DZ, OF, UF, NX = 16, 8, 4, 2, 1
QNAN = 0x7fc00000


def pow2(e):
    return Fraction(1 << e) if e >= 0 else Fraction(1, 1 << -e)


def classify(bits):
    e, m = (bits >> 23) & 255, bits & 0x7fffff
    return ('snan' if not m & 0x400000 else 'nan') if e == 255 and m else ('inf' if e == 255 else 'finite')


def exact(bits):
    e, m = (bits >> 23) & 255, bits & 0x7fffff
    return (-1 if bits >> 31 else 1) * (m if e == 0 else m | 0x800000) * pow2(-149 if e == 0 else e-150)


def round_integer(value, sign, rm):
    q, r = divmod(value.numerator, value.denominator)
    if rm == 0:
        up = 2*r > value.denominator or (2*r == value.denominator and q & 1)
    elif rm == 1:
        up = False
    elif rm == 2:
        up = bool(sign and r)
    elif rm == 3:
        up = bool(not sign and r)
    else:
        up = 2*r >= value.denominator
    return q + int(up), bool(r)


def encode(value, rm, zero_sign=0):
    if not value:
        return zero_sign << 31, 0
    sign = int(value < 0)
    value = abs(value)
    e = value.numerator.bit_length() - value.denominator.bit_length()
    if value < pow2(e):
        e -= 1
    step = pow2(max(e, -126)-23)
    q, inexact = round_integer(value/step, sign, rm)
    flags = (NX if inexact else 0) | (UF if inexact and value < pow2(-126) else 0)
    if q >= (1 << 24):
        q >>= 1
        e += 1
    if e > 127:
        to_inf = rm in (0, 4) or (rm == 2 and sign) or (rm == 3 and not sign)
        return (sign << 31) | (0x7f800000 if to_inf else 0x7f7fffff), OF | NX
    if e < -126:
        return (sign << 31) | q, flags
    return (sign << 31) | ((e+127) << 23) | (q & 0x7fffff), flags


def expected(op, rm, a, b, fixed):
    if rm > 4 or op == 7:
        return (0x7fffffff if op == 6 else QNAN), NV
    if op == 5:
        sign = fixed >> 31
        return encode((-1 if sign else 1)*Fraction(fixed & 0x7fffffff, 32768), rm, sign)
    ca, cb = classify(a), classify(b)
    sa, sb = a >> 31, b >> 31
    if op == 6:
        if ca in ('nan', 'snan'):
            return 0x7fffffff, NV
        if ca == 'inf':
            return (sa << 31) | 0x7fffffff, NV
        q, inexact = round_integer(abs(exact(a))*32768, sa, rm)
        if q > 0x7fffffff:
            return (sa << 31) | 0x7fffffff, NV
        return (sa << 31) | q, NX if inexact else 0
    if ca in ('nan', 'snan') or cb in ('nan', 'snan'):
        return QNAN, NV if 'snan' in (ca, cb) else 0
    za, zb = (a & 0x7fffffff) == 0, (b & 0x7fffffff) == 0
    if op in (1, 2):
        sb ^= op == 2
        if ca == cb == 'inf' and sa != sb:
            return QNAN, NV
        if ca == 'inf':
            return (sa << 31) | 0x7f800000, 0
        if cb == 'inf':
            return (sb << 31) | 0x7f800000, 0
        value = exact(a) + (exact(b) if op == 1 else -exact(b))
        return encode(value, rm, sa if sa == sb else int(rm == 2))
    sign = sa ^ sb
    if op == 3:
        if (ca == 'inf' and zb) or (cb == 'inf' and za):
            return QNAN, NV
        if 'inf' in (ca, cb):
            return (sign << 31) | 0x7f800000, 0
        return encode(exact(a)*exact(b), rm, sign)
    if (za and zb) or ca == cb == 'inf':
        return QNAN, NV
    if ca == 'inf':
        return (sign << 31) | 0x7f800000, 0
    if cb == 'inf':
        return sign << 31, 0
    if zb:
        return (sign << 31) | 0x7f800000, DZ
    return encode(exact(a)/exact(b), rm, sign)


def vectors(random_count):
    # Explicit expectations also check the oracle, including ties and flags.
    known = [
        (1,0,0,0,0,0,0), (1,0,0x3f800000,0x3f800000,0,0x40000000,0),
        (2,2,0x3f800000,0x3f800000,0,0x80000000,0),
        (1,0,0x7f800000,0xff800000,0,QNAN,NV),
        (4,0,0x3f800000,0,0,0x7f800000,DZ),
        (4,0,0,0,0,QNAN,NV), (3,0,1,0x3f000000,0,0,UF|NX),
        (3,4,1,0x3f000000,0,1,UF|NX),
        (3,0,0x7f7fffff,0x40000000,0,0x7f800000,OF|NX),
        (3,1,0x7f7fffff,0x40000000,0,0x7f7fffff,OF|NX),
        (5,0,QNAN,QNAN,32768,0x3f800000,0),
        (5,0,0,0,0x80008000,0xbf800000,0),
        (6,0,0xbf800000,QNAN,0,0x80008000,0),
        (6,0,0x47800000,0,0,0x7fffffff,NV),
        (1,0,0x3f800000,0x33800000,0,0x3f800000,NX),
        (1,4,0x3f800000,0x33800000,0,0x3f800001,NX),
    ]
    for op,rm,a,b,f,out,flags in known:
        assert expected(op,rm,a,b,f) == (out,flags)
        yield op,rm,a,b,f,out,flags
    edges = [0,1,2,0x003fffff,0x00400000,0x007fffff,0x00800000,0x00800001,
             0x33000000,0x33800000,0x3effffff,0x3f000000,0x3f7fffff,0x3f800000,
             0x3f800001,0x40000000,0x40400000,0x477fffff,0x47800000,
             0x7f7fffff,0x7f800000,0x7fc00000,0x7f800001]
    edges += [x | 0x80000000 for x in edges]
    for op in range(1,5):
        for rm in range(5):
            for a in edges:
                for b in edges:
                    yield op,rm,a,b,0,*expected(op,rm,a,b,0)
    fixed_edges = [0,1,2,16383,16384,32767,32768,32769,0x00ffffff,
                   0x01000001,0x01000003,0x3fffffff,0x7fffffbf,0x7fffffc0,0x7fffffff]
    fixed_edges += [x | 0x80000000 for x in fixed_edges]
    for rm in range(5):
        for f in fixed_edges:
            yield 5,rm,QNAN,0x7f800001,f,*expected(5,rm,QNAN,0x7f800001,f)
        for a in edges:
            yield 6,rm,a,0x7f800001,0,*expected(6,rm,a,0x7f800001,0)
    rng = random.Random(0xf32)
    for _ in range(random_count):
        op,rm = rng.randrange(1,7),rng.randrange(5)
        a,b,f = (rng.getrandbits(32) for _ in range(3))
        yield op,rm,a,b,f,*expected(op,rm,a,b,f)
    for op in range(1,8):
        for rm in range(8):
            if op == 7 or rm > 4:
                yield op,rm,0,0,0,*expected(op,rm,0,0,0)

