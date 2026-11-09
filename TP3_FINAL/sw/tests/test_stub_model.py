import pytest

from host.dump import decode, encode
from host.stub_model import stub_dump, stub_state_words


def test_cycle_zero() -> None:
    d = stub_dump(0, 20)
    assert d.pc == 0 and d.x[1] == 1 and d.x[31] == 31 and d.mem == () and not d.halted
    assert len(encode(d)) == 210


def test_cycle_one_has_three_pairs_ascending() -> None:
    d = stub_dump(1, 20)
    assert d.mem == ((16, 0xD000_0004), (64, 0xD000_0010), (252, 0xD000_003F))
    assert d.x[5] == 0x105 and d.latches[15] == 0x1A0F_0001
    assert len(encode(d)) == 234


def test_halt() -> None:
    assert stub_dump(20, 20).halted and not stub_dump(19, 20).halted
    assert not stub_dump(1000, 0).halted
    with pytest.raises(ValueError):
        stub_dump(21, 20)


def test_round_trip_and_state_length() -> None:
    assert decode(encode(stub_dump(7, 20, aborted=True))) == stub_dump(7, 20, aborted=True)
    assert len(stub_state_words(7, 20)) == 563
