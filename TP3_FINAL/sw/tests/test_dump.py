import random

import pytest

from host.dump import Dump, DumpError, LatchInfo, decode, encode, expected_length


def random_dump(rng: random.Random) -> Dump:
    m = rng.choice([0, 1, 3, 256, rng.randint(0, 256)])
    idxs = sorted(rng.sample(range(256), m))
    return Dump(
        halted=rng.random() < 0.5, timeout=rng.random() < 0.5,
        aborted=rng.random() < 0.5, version=rng.randint(0, 255),
        cycles=rng.getrandbits(32), pc=rng.getrandbits(32),
        x=tuple(rng.getrandbits(32) for _ in range(32)),
        latches=tuple(rng.getrandbits(32) for _ in range(16)),
        mem=tuple((i * 4, rng.getrandbits(32)) for i in idxs),
    )


def test_round_trip_1000() -> None:
    rng = random.Random(1234)
    for _ in range(1000):
        d = random_dump(rng)
        b = encode(d)
        assert len(b) == expected_length(len(d.mem))
        assert decode(b) == d


@pytest.mark.parametrize("m,length", [(0, 210), (1, 218), (3, 234), (256, 2258)])
def test_expected_length(m: int, length: int) -> None:
    assert expected_length(m) == length


def test_any_altered_byte_is_rejected() -> None:
    b = encode(random_dump(random.Random(7)))
    for i in range(len(b)):
        bad = bytearray(b)
        bad[i] ^= 0x01
        with pytest.raises(DumpError):
            decode(bytes(bad))


def test_truncated_is_rejected() -> None:
    b = encode(random_dump(random.Random(8)))
    with pytest.raises(DumpError):
        decode(b[:-1])


def test_latch_info_layout() -> None:
    assert LatchInfo(rd=5, reg_write=True, halt=True).pack() == 0x8400_0005
    assert LatchInfo(rs1=31).pack() == 31 << 5
    assert LatchInfo(alu_op=0xF, funct3=7).pack() == (0xF << 18) | (7 << 15)
    rng = random.Random(9)
    for _ in range(200):
        w = rng.getrandbits(32)
        assert LatchInfo.unpack(w).pack() == w


def test_status_bits() -> None:
    d = decode(encode(Dump(True, False, True, 1, 0, 0, (0,) * 32, (0,) * 16, ())))
    assert (d.halted, d.timeout, d.aborted, d.version) == (True, False, True, 1)
    assert encode(Dump(True, False, True, 1, 0, 0, (0,) * 32, (0,) * 16, ()))[1:5] == bytes([0x05, 0x01, 0, 0])
