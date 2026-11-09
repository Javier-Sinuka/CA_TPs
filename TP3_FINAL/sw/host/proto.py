"""Constantes del protocolo UART v1 (doc/documentation/protocolo.md).

No editar sin cambiar antes el contrato.
"""

BAUD_RATE = 115_200

# Comandos (protocolo.md §3)
CMD_VERSION = 0x56  # 'V'
CMD_RESET = 0x58    # 'X'
CMD_LOAD = 0x4C     # 'L'
CMD_STEP = 0x53     # 'S'
CMD_RUN = 0x52      # 'R'
CMD_ABORT = 0x41    # 'A'
CMD_DUMP = 0x44     # 'D'

# Respuestas
RESP_OK = 0x4B          # 'K'
RESP_ERR = 0x45         # 'E'
DUMP_HEADER = 0xA5
VERSION_HEADER = 0x56

# Códigos de error (protocolo.md §3)
ERR_UNKNOWN_CMD = 0x01
ERR_N_RANGE = 0x02
ERR_BYTE_TIMEOUT = 0x03

PROTO_VERSION = 0x01
IMEM_WORDS = 256
DMEM_WORDS = 256
HALT_WORD = 0x0000_0073

VERSION_RESPONSE = bytes([
    VERSION_HEADER, PROTO_VERSION,
    IMEM_WORDS & 0xFF, IMEM_WORDS >> 8,
    DMEM_WORDS & 0xFF, DMEM_WORDS >> 8,
])

# Timeouts del host en segundos (protocolo.md §6)
TIMEOUT_SHORT_S = 0.2
TIMEOUT_DUMP_S = 0.5
TIMEOUT_RUN_S = 4.0


def timeout_load_final_s(n_words: int) -> float:
    """Timeout para el 'K' final de L con n_words palabras."""
    return 0.2 + 4 * n_words * 87e-6
