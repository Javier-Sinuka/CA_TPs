"""Tests de host/guion_debug.py contra el log de B-16 (sin placa)."""
from pathlib import Path

import pytest

from host import guion_debug, proto
from host.dump import encode
from host.guion_debug import GuionError, main, run, run_once
from host.link import Link
from host.replay import ReplayPort
from host.stub_model import stub_dump

HALT_AT = 20

LOG = Path(__file__).parent / "data" / "tb_system_debug.bytes.log"


def _in_bytes() -> list[int]:
    out: list[int] = []
    for line in LOG.read_text().splitlines():
        if line.startswith("< "):
            out += [int(t, 16) for t in line[2:].split()]
    return out


def _index_after(step: str) -> int:
    """Índice (entre los bytes '<') del primer byte de respuesta del paso `step`."""
    n = 0
    for line in LOG.read_text().splitlines():
        if line == f"# {step}":
            return n
        if line.startswith("< "):
            n += len(line[2:].split())
    raise AssertionError(f"paso {step!r} no está en el log")


def _opener(port):
    return lambda name, baud: Link(port)


def _log_con_dump(tmp_path, step, dump):
    """Copia del log donde la respuesta del paso `step` es el dump (válido) `dump`."""
    out, in_step = [], False
    for line in LOG.read_text().splitlines():
        if line.startswith("# "):
            if in_step:
                out.append("< " + " ".join(f"{b:02x}" for b in encode(dump)))
            in_step = line == f"# {step}"
        if not (in_step and line.startswith("< ")):
            out.append(line)
    if in_step:
        out.append("< " + " ".join(f"{b:02x}" for b in encode(dump)))
    path = tmp_path / "cambiado.log"
    path.write_text("\n".join(out) + "\n")
    return path


@pytest.fixture
def rapido(monkeypatch):
    """Timeouts cortos: el caso de silencio no espera los 0,2 s reales."""
    monkeypatch.setattr(proto, "TIMEOUT_SHORT_S", 0.02)


def test_una_repeticion_pasa():
    port = ReplayPort(LOG)
    run_once(Link(port))
    assert port.done


def test_dos_repeticiones_seguidas(tmp_path, capsys):
    two = tmp_path / "dos.log"
    two.write_text(LOG.read_text() + LOG.read_text())
    port = ReplayPort(two)
    rc = main(["--port", "COMX", "--repeat", "2"], opener=_opener(port))
    out = capsys.readouterr().out.splitlines()
    assert out == ["rep 1: OK", "rep 2: OK", "PASS guion_debug: 2/2"]
    assert rc == 0
    assert port.done


def test_checksum_malo_falla_en_el_paso(capsys):
    i = _index_after("S 1") + 10
    port = ReplayPort(LOG, corrupt={i: _in_bytes()[i] ^ 0xFF})
    lines: list[str] = []
    assert run(Link(port), 1, out=lines.append) == 0
    assert len(lines) == 1 and lines[0].startswith("rep 1: FAIL S 1: ")


def test_dump_distinto_dice_el_campo(monkeypatch):
    # Con HALT_AT = 19 el dump esperado de R (ciclo 19) no coincide con el de la placa (ciclo 20).
    monkeypatch.setattr(guion_debug, "HALT_AT", 19)
    with pytest.raises(GuionError) as e:
        run_once(Link(ReplayPort(LOG)))
    assert e.value.step == "R"
    assert "cycles recibido 20, esperado 19" in e.value.detail


def test_codigo_de_error_inesperado():
    i = _index_after("invalido") + 1
    port = ReplayPort(LOG, corrupt={i: 0x02})
    with pytest.raises(GuionError) as e:
        run_once(Link(port))
    assert e.value.step == "invalido"
    assert "código de error 2, esperado 1" in e.value.detail


def test_silencio_falla_en_V_con_codigo_1(rapido, capsys):
    port = ReplayPort(LOG, truncate_at=0)
    port.timeout = 0.005
    rc = main(["--port", "COMX", "--repeat", "1"], opener=_opener(port))
    out = capsys.readouterr().out.splitlines()
    assert out[0].startswith("rep 1: FAIL V: ")
    assert out[-1] == "FAIL guion_debug: 0/1"
    assert rc == 1


def test_una_falla_entre_varias_da_codigo_1(tmp_path, capsys):
    two = tmp_path / "dos.log"
    two.write_text(LOG.read_text() + LOG.read_text())
    i = len(_in_bytes()) + _index_after("S 1") + 10   # dump de S 1 de la repetición 2
    port = ReplayPort(two, corrupt={i: _in_bytes()[_index_after("S 1") + 10] ^ 0xFF})
    rc = main(["--port", "COMX", "--repeat", "2"], opener=_opener(port))
    out = capsys.readouterr().out.splitlines()
    assert out[0] == "rep 1: OK"
    assert out[1].startswith("rep 2: FAIL S 1: ")
    assert out[-1] == "FAIL guion_debug: 1/2"
    assert rc == 1


def test_puerto_que_no_abre_da_2(capsys):
    def opener(name, baud):
        raise OSError("acceso denegado")

    assert main(["--port", "COMX"], opener=opener) == 2
    cap = capsys.readouterr()
    assert cap.out == ""
    assert cap.err.startswith("error: no se pudo abrir COMX: ")


def test_repeat_invalido_da_2():
    with pytest.raises(SystemExit) as e:
        main(["--port", "COMX", "--repeat", "0"])
    assert e.value.code == 2


@pytest.mark.parametrize("step", ["S 3", "R", "D", "R B", "D final"])
def test_dump_valido_pero_distinto_falla_en_su_paso(tmp_path, step):
    path = _log_con_dump(tmp_path, step, stub_dump(19, HALT_AT))
    with pytest.raises(GuionError) as e:
        run_once(Link(ReplayPort(path)))
    assert e.value.step == step
    assert "cycles recibido 19" in e.value.detail


def test_version_distinta_falla_en_V():
    port = ReplayPort(LOG, corrupt={3: 0x02})        # imem_words = 0x200
    with pytest.raises(GuionError) as e:
        run_once(Link(port))
    assert e.value.step == "V"
    assert "versión" in e.value.detail
