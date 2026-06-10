# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

# ui_in bits — must match info.yaml pinout
PORT_SEL  = 1 << 0
ALE_N     = 1 << 1
RD_N      = 1 << 2
WR_N      = 1 << 3
CS_N      = 1 << 4
SLEEP     = 1 << 5
RETENTION = 1 << 6

# uo_out bits
COLLISION = 1 << 0
GRANT_A   = 1 << 1
GRANT_B   = 1 << 2


def _ui(port_sel=0, ale_n=1, rd_n=1, wr_n=1, cs_n=1, sleep=0, retention=0):
    """Build ui_in value (active-low controls: 1 = inactive)."""
    val = ALE_N | RD_N | WR_N | CS_N
    if port_sel:
        val |= PORT_SEL
    if not ale_n:
        val &= ~ALE_N
    if not rd_n:
        val &= ~RD_N
    if not wr_n:
        val &= ~WR_N
    if not cs_n:
        val &= ~CS_N
    if sleep:
        val |= SLEEP
    if retention:
        val |= RETENTION
    return val


async def reset_dut(dut):
    dut.ena.value = 1
    dut.ui_in.value = _ui()
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)


async def ram_write(dut, port, addr, data):
    """Write one byte: latch address, then write data."""
  # port: 0 = A, 1 = B
    dut.ui_in.value = _ui(port_sel=port, cs_n=0, ale_n=0)
    dut.uio_in.value = addr
    await ClockCycles(dut.clk, 1)

    dut.ui_in.value = _ui(port_sel=port, cs_n=0, wr_n=0)
    dut.uio_in.value = data
    await ClockCycles(dut.clk, 1)

    dut.ui_in.value = _ui()
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 1)


async def ram_read(dut, port, addr):
    """Read one byte; returns integer 0–255."""
    dut.ui_in.value = _ui(port_sel=port, cs_n=0, ale_n=0)
    dut.uio_in.value = addr
    await ClockCycles(dut.clk, 1)

    dut.ui_in.value = _ui(port_sel=port, cs_n=0, rd_n=0)
    await ClockCycles(dut.clk, 2)

    # DUT drives bus when reading — sample uio_out (wrapper sets uio_oe)
    result = int(dut.uio_out.value)
    dut.ui_in.value = _ui()
    await ClockCycles(dut.clk, 1)
    return result


@cocotb.test()
async def test_port_a_write_read(dut):
    """Write and read back on Port A."""
    dut._log.info("test_port_a_write_read")
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    await reset_dut(dut)

    await ram_write(dut, port=0, addr=0x0A, data=0xAB)
    data = await ram_read(dut, port=0, addr=0x0A)

    assert data == 0xAB, f"Port A read mismatch: got 0x{data:02x}, expected 0xAB"


@cocotb.test()
async def test_port_b_write_read(dut):
    """Write and read back on Port B."""
    dut._log.info("test_port_b_write_read")
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    await reset_dut(dut)

    await ram_write(dut, port=1, addr=0x0B, data=0xCD)
    data = await ram_read(dut, port=1, addr=0x0B)

    assert data == 0xCD, f"Port B read mismatch: got 0x{data:02x}, expected 0xCD"


@cocotb.test()
async def test_dual_port_independence(dut):
    """Port A and Port B can hold different values at different addresses."""
    dut._log.info("test_dual_port_independence")
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    await reset_dut(dut)

    await ram_write(dut, port=0, addr=0x05, data=0x11)
    await ram_write(dut, port=1, addr=0x06, data=0x22)

    assert await ram_read(dut, port=0, addr=0x05) == 0x11
    assert await ram_read(dut, port=1, addr=0x06) == 0x22


@cocotb.test()
async def test_status_idle(dut):
    """After idle, collision should be low and grant reflects no access."""
    dut._log.info("test_status_idle")
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    await reset_dut(dut)

    await ClockCycles(dut.clk, 2)
    status = int(dut.uo_out.value)
    assert (status & COLLISION) == 0, "COLLISION set while idle"
