"""B-26 §A: diagrama espacio-tiempo con dumps armados a mano."""
import pytest

from asm.rvasm import assemble
from host.dump import Dump
from host.spacetime import Row, build, row_label, stage_pcs


def mk(pc_if, id=None, ex=None, mem=None, wb=None, stall=0, take=0, stop=0, halted=0):
    """Dump con esos pc (None = etapa inválida) y esos bits de riesgo."""
    lat = [0] * 16
    flags = 0
    for bit, (idx, pc) in enumerate(((0, id), (2, ex), (7, mem), (11, wb))):
        if pc is not None:
            lat[idx] = pc
            flags |= 1 << bit
    flags |= (stall << 5) | (take << 6) | (stop << 7) | (halted << 4)
    lat[15] = flags
    return Dump(halted=bool(halted), timeout=False, aborted=False, version=1, cycles=0,
                pc=pc_if, x=(0,) * 32, latches=tuple(lat), mem=())


def table(rows):
    """Filas -> lista de (pc, [celda por columna]) con '' en las vacías."""
    ncols = max(c for r in rows for c in r.cells) + 1
    return [(r.pc, [r.cells.get(c, "") for c in range(ncols)]) for r in rows]


LOAD_USE = [
    mk(0),
    mk(4, id=0),
    mk(8, id=4, ex=0, stall=1),
    mk(8, id=4, mem=0),
    mk(12, id=8, ex=4, wb=0),
    mk(16, id=12, ex=8, mem=4, stop=1),
    mk(16, ex=12, mem=8, wb=4, stop=1),
    mk(16, mem=12, wb=8, stop=1),
    mk(16, wb=12, stop=1, halted=1),
]

BRANCH = [
    mk(0),
    mk(4, id=0),
    mk(8, id=4, ex=0),
    mk(12, id=8, ex=4, mem=0, take=1),
    mk(16, mem=4, wb=0),
    mk(20, id=16, wb=4, stop=1),
    mk(20, ex=16, stop=1),
    mk(20, mem=16, stop=1),
    mk(20, wb=16, stop=1, halted=1),
]


def test_load_use_da_la_tabla_del_issue():
    assert table(build(LOAD_USE)) == [
        (0x0, ["IF", "ID", "EX", "MEM", "WB", "", "", "", ""]),
        (0x4, ["", "IF", "ID", "ID*", "EX", "MEM", "WB", "", ""]),
        (0x8, ["", "", "IF", "IF*", "ID", "EX", "MEM", "WB", ""]),
        (0xC, ["", "", "", "", "IF", "ID", "EX", "MEM", "WB"]),
    ]


def test_salto_tomado_da_la_tabla_del_issue():
    assert table(build(BRANCH)) == [
        (0x0, ["IF", "ID", "EX", "MEM", "WB", "", "", "", ""]),
        (0x4, ["", "IF", "ID", "EX", "MEM", "WB", "", "", ""]),
        (0x8, ["", "", "IF", "ID×", "", "", "", "", ""]),
        (0xC, ["", "", "", "IF×", "", "", "", "", ""]),
        (0x10, ["", "", "", "", "IF", "ID", "EX", "MEM", "WB"]),
    ]


def test_sin_dumps_no_hay_filas():
    assert build([]) == []


def test_un_solo_dump_crea_una_fila_por_etapa_valida_en_orden_wb_a_if():
    rows = build([mk(16, id=12, ex=8, mem=4, wb=0)])
    assert [(r.pc, r.cells) for r in rows] == [
        (0, {0: "WB"}), (4, {0: "MEM"}), (8, {0: "EX"}), (12, {0: "ID"}), (16, {0: "IF"})]


def test_stop_fetch_y_halted_apagan_la_etapa_if():
    assert stage_pcs(mk(16, stop=1)) == {}
    assert stage_pcs(mk(16, halted=1)) == {}
    assert stage_pcs(mk(16)) == {"IF": 16}


def test_stop_fetch_anula_la_instruccion_de_id_que_no_avanza():
    # la instrucción en ID (pc 8) no aparece en el dump siguiente: ID× en la columna previa
    rows = build([mk(12, id=8, stop=1), mk(12, stop=1)])
    assert [(r.pc, r.cells) for r in rows] == [(0x8, {0: "ID×"})]


def test_stop_fetch_no_anula_la_que_avanza():
    rows = build([mk(12, id=8, stop=1), mk(12, ex=8, stop=1)])
    assert table(rows) == [(0x8, ["ID", "EX"])]


def test_take_ex_no_anula_si_la_instruccion_sigue_presente():
    # con take_ex en p, una IF/ID que aparece en t no se marca anulada
    rows = build([mk(8, id=4, take=1), mk(8, ex=4)])
    assert rows[0].cells == {0: "ID", 1: "EX"}


def test_take_ex_anula_if_e_id_que_desaparecen():
    rows = build([mk(8, id=4, take=1), mk(16)])
    assert [(r.pc, r.cells) for r in rows] == [
        (0x4, {0: "ID×"}), (0x8, {0: "IF×"}), (0x10, {1: "IF"})]


def test_sin_take_ex_las_que_desaparecen_no_se_marcan():
    rows = build([mk(8, id=4), mk(16)])
    assert [(r.pc, r.cells) for r in rows] == [
        (0x4, {0: "ID"}), (0x8, {0: "IF"}), (0x10, {1: "IF"})]


def test_stall_solo_cuenta_con_el_bit_del_dump_previo():
    # mismo pc en ID dos dumps seguidos pero sin load_use_stall: es una instancia nueva (bucle)
    rows = build([mk(8, id=4), mk(8, id=4)])
    assert [(r.pc, r.cells) for r in rows] == [
        (4, {0: "ID"}), (8, {0: "IF"}), (4, {1: "ID"}), (8, {1: "IF"})]


def test_stall_solo_aplica_a_if_e_id():
    rows = build([mk(8, ex=4, stall=1), mk(8, ex=4)])
    assert [(r.pc, r.cells) for r in rows] == [
        (4, {0: "EX"}), (8, {0: "IF", 1: "IF*"}), (4, {1: "EX"})]


def test_una_instancia_no_se_asigna_a_dos_etapas_a_la_vez():
    rows = build([mk(8, id=4, stall=1), mk(8, id=4, ex=4)])
    assert [(r.pc, r.cells) for r in rows] == [
        (4, {0: "ID", 1: "EX"}), (8, {0: "IF", 1: "IF*"}), (4, {1: "ID"})]


def test_stall_con_pc_distinto_no_reutiliza_la_fila():
    rows = build([mk(8, id=4, stall=1), mk(8, id=12)])
    assert [(r.pc, r.cells) for r in rows] == [
        (4, {0: "ID"}), (8, {0: "IF", 1: "IF*"}), (12, {1: "ID"})]


def test_misma_pc_en_bucle_crea_instancias_distintas():
    # pc 4 vuelve a entrar a IF tras un salto: no se confunde con la instancia anterior en WB
    rows = build([mk(4, wb=4), mk(8, id=4)])
    assert [(r.pc, r.cells) for r in rows] == [
        (4, {0: "WB"}), (4, {0: "IF", 1: "ID"}), (8, {1: "IF"})]


def test_etiqueta_de_fila():
    words = assemble("lw x1, 0(x0)\nadd x2, x1, x1\n")
    assert row_label(Row(pc=4), words) == "0x00000004 add x2, x1, x1"
    assert row_label(Row(pc=0x400), words) == "0x00000400 ???"


@pytest.mark.parametrize("dumps", [LOAD_USE, BRANCH])
def test_cada_celda_pertenece_a_una_sola_fila_por_columna(dumps):
    rows = build(dumps)
    for t in range(len(dumps)):
        stages = [r.cells[t].rstrip("*×") for r in rows if t in r.cells]
        assert len(stages) == len(set(stages))
