"""Tablas de codificación RV32I (subconjunto de 32 instrucciones) y codificadores de formato (B-19)."""
from __future__ import annotations

OP_R = 0b0110011
OP_I = 0b0010011
OP_LOAD = 0b0000011
OP_JALR = 0b1100111
OP_STORE = 0b0100011
OP_BRANCH = 0b1100011
OP_JAL = 0b1101111
OP_LUI = 0b0110111

HALT_WORD = 0x00000073

# nombre -> (funct3, funct7)
R_TYPE: dict[str, tuple[int, int]] = {
    "add": (0b000, 0b0000000),
    "sub": (0b000, 0b0100000),
    "sll": (0b001, 0b0000000),
    "slt": (0b010, 0b0000000),
    "sltu": (0b011, 0b0000000),
    "xor": (0b100, 0b0000000),
    "srl": (0b101, 0b0000000),
    "sra": (0b101, 0b0100000),
    "or": (0b110, 0b0000000),
    "and": (0b111, 0b0000000),
}

# nombre -> funct3
I_ARITH: dict[str, int] = {
    "addi": 0b000,
    "slti": 0b010,
    "sltiu": 0b011,
    "xori": 0b100,
    "ori": 0b110,
    "andi": 0b111,
}

# nombre -> (funct3, funct7)
I_SHIFT: dict[str, tuple[int, int]] = {
    "slli": (0b001, 0b0000000),
    "srli": (0b101, 0b0000000),
    "srai": (0b101, 0b0100000),
}

LOADS: dict[str, int] = {"lb": 0b000, "lh": 0b001, "lw": 0b010, "lbu": 0b100, "lhu": 0b101}
STORES: dict[str, int] = {"sb": 0b000, "sh": 0b001, "sw": 0b010}
BRANCHES: dict[str, int] = {"beq": 0b000, "bne": 0b001}

_ABI = ["zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0", "s1", "a0", "a1", "a2", "a3", "a4",
        "a5", "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11", "t3", "t4",
        "t5", "t6"]
REGS: dict[str, int] = {f"x{i}": i for i in range(32)}
REGS.update({name: i for i, name in enumerate(_ABI)})
REGS["fp"] = 8


def enc_r(opcode: int, funct3: int, funct7: int, rd: int, rs1: int, rs2: int) -> int:
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def enc_i(opcode: int, funct3: int, rd: int, rs1: int, imm: int) -> int:
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def enc_s(opcode: int, funct3: int, rs1: int, rs2: int, imm: int) -> int:
    imm &= 0xFFF
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | ((imm & 0x1F) << 7) | opcode


def enc_b(opcode: int, funct3: int, rs1: int, rs2: int, imm: int) -> int:
    imm &= 0x1FFF
    return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) \
        | (funct3 << 12) | (((imm >> 1) & 0xF) << 8) | (((imm >> 11) & 1) << 7) | opcode


def enc_u(opcode: int, rd: int, imm: int) -> int:
    return ((imm & 0xFFFFF) << 12) | (rd << 7) | opcode


def enc_j(opcode: int, rd: int, imm: int) -> int:
    imm &= 0x1FFFFF
    return (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3FF) << 21) | (((imm >> 11) & 1) << 20) \
        | (((imm >> 12) & 0xFF) << 12) | (rd << 7) | opcode
