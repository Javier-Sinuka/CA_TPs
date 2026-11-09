from host import canonical
from host.dump import Dump


def make(halted: bool = True, timeout: bool = False, x5: int = 5) -> Dump:
    x = tuple(x5 if i == 5 else 0 for i in range(32))
    latches = tuple(0x40 if k == 11 else 0 for k in range(16))
    return Dump(halted, timeout, False, 1, 10, 0x44, x, latches, ((0, 55),))


def test_from_dump_halt() -> None:
    c = canonical.from_dump(make())
    assert c["stop"] == "halt" and c["pc"] == "0x00000040"
    assert c["x"][5] == "0x00000005" and c["mem"] == [["0x00000000", "0x00000037"]]


def test_from_dump_limit_has_null_pc() -> None:
    c = canonical.from_dump(make(halted=False, timeout=True))
    assert c["stop"] == "limit" and c["pc"] is None


def test_diff() -> None:
    a = canonical.from_dump(make())
    b = canonical.from_dump(make(x5=6))
    assert canonical.diff(a, a) == []
    assert canonical.diff(a, b, "iss", "rtl") == ["x5: iss=0x00000005 rtl=0x00000006"]


def test_diff_limit_only_compares_stop() -> None:
    a = canonical.from_dump(make(halted=False, timeout=True))
    b = canonical.from_dump(make(halted=False, timeout=True, x5=9))
    assert canonical.diff(a, b) == []
