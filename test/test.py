"""External-pin tests shared by RTL and gate-level GitHub Actions jobs."""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge, Timer
from reference import vectors


class Bus:
    def __init__(self, dut):
        self.dut = dut
        self.req = 0

    async def reset(self):
        d = self.dut
        d.ena.value = 1
        d.rst_n.value = 0
        d.ui_in.value = 0
        d.uio_in.value = 0
        self.req = 0
        await ClockCycles(d.clk, 5)
        await FallingEdge(d.clk)
        d.rst_n.value = 1
        await ClockCycles(d.clk, 3)

    async def transfer(self, address, reading, data=0):
        d = self.dut
        await FallingEdge(d.clk)
        d.ui_in.value = data
        ctrl = (address << 2) | (int(reading) << 1)
        d.uio_in.value = ctrl | self.req
        await Timer(5, unit="ns")
        self.req ^= 1
        d.uio_in.value = ctrl | self.req
        for _ in range(12):
            await RisingEdge(d.clk)
            await Timer(5, unit="ns")
            assert int(d.uio_oe.value) == 0xc0
            if ((int(d.uio_out.value) >> 6) & 1) == self.req:
                return int(d.uo_out.value)
        assert False, "Request/ack timeout"

    async def read(self, address):
        return await self.transfer(address, True)

    async def write(self, address, data):
        await self.transfer(address, False, data)

    async def word(self, base, value):
        for i in range(4):
            await self.write(base+i, (value >> (8*i)) & 255)

    async def wait_done(self):
        for _ in range(400):
            status = await self.read(14)
            if status & 2:
                assert not (status & 1), "Done and busy simultaneously"
                return status
        assert False, "Operation timeout"

    async def result(self):
        value = 0
        for i in range(4):
            value |= (await self.read(9+i)) << (8*i)
        return value, await self.read(13)


async def setup(dut):
    dut.clk.value = 0
    cocotb.start_soon(Clock(dut.clk, 33334, unit="ps").start())
    bus = Bus(dut)
    await bus.reset()
    return bus


@cocotb.test()
async def protocol_and_abort(dut):
    bus = await setup(dut)
    assert await bus.read(15) == 0xf1
    assert await bus.read(14) == 0
    for address, data in [(8, 0), (8, 0xc1), (9, 0), (15, 0)]:
        await bus.write(address, data)
        assert await bus.read(14) == 4
        await bus.write(14, 0)
        assert await bus.read(14) == 0
    await bus.word(0, 0x3f800000)
    await bus.word(4, 0x40400000)
    await bus.write(8, 4)  # 1 / 3, long enough to test busy write protection
    await bus.write(0, 255)
    assert await bus.wait_done() == 6
    assert await bus.read(0) == 0
    assert await bus.result() == (0x3eaaaaab, 1)
    await bus.write(14, 0)
    assert await bus.read(14) == 0
    await bus.write(8, 4)
    await bus.reset()  # reset during an operation
    assert await bus.read(14) == 0
    assert await bus.result() == (0, 0)
    await bus.word(0, 0x3f800000)
    await bus.word(4, 0x40400000)
    await bus.write(8, 4)
    await FallingEdge(dut.clk)
    dut.ena.value = 0
    dut.uio_in.value = 0
    bus.req = 0
    await ClockCycles(dut.clk, 5)
    await FallingEdge(dut.clk)
    dut.ena.value = 1
    assert await bus.read(14) == 0
    assert await bus.result() == (0, 0)


@cocotb.test()
async def exact_arithmetic(dut):
    bus = await setup(dut)
    count = 0
    for i, (op, rm, a, b, fixed, wanted, flags) in enumerate(vectors(256)):
        # Sample the large arithmetic boundary cross-product; retain all hand
        # cases, conversion boundaries, random cases and invalid encodings.
        if 16 <= i < 42336 and (i-16) % 97:
            continue
        await bus.word(0, fixed if op == 5 else a)
        await bus.word(4, b)
        await bus.write(8, op | (rm << 3))
        assert await bus.wait_done() == 2
        actual = await bus.result()
        assert actual == (wanted, flags), (
            f"case={count} op={op} rm={rm} a={a:08x} b={b:08x} "
            f"fixed={fixed:08x} got={actual} expected={(wanted, flags)}"
        )
        # Done persists; a held request must not replay the command/read.
        assert await bus.read(14) == 2
        await ClockCycles(dut.clk, 8)
        await Timer(5, unit="ns")
        assert int(dut.uo_out.value) == 2
        assert ((int(dut.uio_out.value) >> 6) & 1) == bus.req
        assert not (int(dut.uio_out.value) & 0x80)
        count += 1
    assert count == 1115
    dut._log.info("Passed %d exact-reference pin transactions", count)
