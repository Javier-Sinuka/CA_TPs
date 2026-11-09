#include "iss.hpp"

#include <cinttypes>
#include <cstdio>
#include <fstream>

static uint32_t op_sra(uint32_t a, uint32_t sh) { return (uint32_t)((int32_t)a >> (sh & 31)); } // MUT:sra

void iss_reset(IssState& s) {
    for (int i = 0; i < 32; i++) s.x[i] = 0;
    s.pc = 0;
    for (int i = 0; i < IMEM_WORDS; i++) s.imem[i] = HALT_WORD;
    for (int i = 0; i < DMEM_WORDS; i++) {
        s.dmem[i] = 0;
        s.written[i] = false;
    }
    s.instret = 0;
}

static bool is_hex_digit(char c) {
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}

bool iss_load_hex(IssState& s, const std::string& path, std::string& err) {
    std::ifstream f(path);
    if (!f) {
        err = "no se pudo abrir " + path;
        return false;
    }
    for (int i = 0; i < IMEM_WORDS; i++) s.imem[i] = HALT_WORD;
    std::string line;
    int lineno = 0;
    int count = 0;
    while (std::getline(f, line)) {
        lineno++;
        size_t b = line.find_first_not_of(" \t\r\n");
        if (b == std::string::npos) continue;
        size_t e = line.find_last_not_of(" \t\r\n");
        std::string t = line.substr(b, e - b + 1);
        if (t.compare(0, 2, "//") == 0) continue;
        bool ok = t.size() >= 1 && t.size() <= 8;
        uint32_t v = 0;
        for (size_t i = 0; ok && i < t.size(); i++) {
            if (!is_hex_digit(t[i])) {
                ok = false;
                break;
            }
            char c = t[i];
            uint32_t d = (c <= '9') ? (uint32_t)(c - '0') : (uint32_t)((c | 0x20) - 'a' + 10);
            v = (v << 4) | d;
        }
        if (!ok) {
            err = "línea " + std::to_string(lineno) + " inválida";
            return false;
        }
        if (count >= IMEM_WORDS) {
            err = "más de 256 palabras";
            return false;
        }
        s.imem[count++] = v;
    }
    return true;
}

static uint32_t fetch(const IssState& s) { return s.imem[(s.pc >> 2) & 255]; }

static int32_t imm_i(uint32_t ins) { return (int32_t)ins >> 20; }
static int32_t imm_s(uint32_t ins) {
    return (int32_t)(((uint32_t)((int32_t)(ins & 0xfe000000u) >> 20)) | ((ins >> 7) & 0x1fu));
}
static int32_t imm_b(uint32_t ins) {
    return (int32_t)(((uint32_t)((int32_t)(ins & 0x80000000u) >> 19)) | ((ins & 0x80u) << 4) |
                     ((ins >> 20) & 0x7e0u) | ((ins >> 7) & 0x1eu));
}
static int32_t imm_j(uint32_t ins) {
    return (int32_t)(((uint32_t)((int32_t)(ins & 0x80000000u) >> 11)) | (ins & 0xff000u) |
                     ((ins >> 9) & 0x800u) | ((ins >> 20) & 0x7feu));
}

static void illegal(IssState& s, uint32_t ins) {
    std::fprintf(stderr, "iss: instrucción ilegal 0x%08x en pc 0x%08x\n", ins, s.pc);
    s.pc += 4;
}

bool iss_step(IssState& s) {
    const uint32_t ins = fetch(s);
    if (ins == HALT_WORD) return false;

    const uint32_t opc = ins & 0x7f;
    const uint32_t rd = (ins >> 7) & 31;
    const uint32_t f3 = (ins >> 12) & 7;
    const uint32_t rs1 = (ins >> 15) & 31;
    const uint32_t rs2 = (ins >> 20) & 31;
    const uint32_t f7 = ins >> 25;
    const uint32_t a = s.x[rs1];
    const uint32_t b = s.x[rs2];

    switch (opc) {
    case 0x33: { // R
        uint32_t r = 0;
        bool ok = true;
        if (f7 == 0x00) {
            switch (f3) {
            case 0: r = a + b; break;
            case 1: r = a << (b & 31); break;
            case 2: r = ((int32_t)a < (int32_t)b) ? 1u : 0u; break;
            case 3: r = (a < b) ? 1u : 0u; break;
            case 4: r = a ^ b; break;
            case 5: r = a >> (b & 31); break;
            case 6: r = a | b; break;
            default: r = a & b; break;
            }
        } else if (f7 == 0x20 && f3 == 0) {
            r = a - b;
        } else if (f7 == 0x20 && f3 == 5) {
            r = op_sra(a, b);
        } else {
            ok = false;
        }
        if (!ok) { illegal(s, ins); break; }
        s.x[rd] = r;
        s.pc += 4;
        break;
    }
    case 0x13: { // I aritmético y shifts
        const uint32_t imm = (uint32_t)imm_i(ins);
        uint32_t r = 0;
        bool ok = true;
        switch (f3) {
        case 0: r = a + imm; break;
        case 2: r = ((int32_t)a < (int32_t)imm) ? 1u : 0u; break;
        case 3: r = (a < imm) ? 1u : 0u; break;
        case 4: r = a ^ imm; break;
        case 6: r = a | imm; break;
        case 7: r = a & imm; break;
        case 1:
            if (f7 == 0x00) r = a << (rs2 & 31); else ok = false;
            break;
        default: // 5
            if (f7 == 0x00) r = a >> (rs2 & 31);
            else if (f7 == 0x20) r = op_sra(a, rs2);
            else ok = false;
            break;
        }
        if (!ok) { illegal(s, ins); break; }
        s.x[rd] = r;
        s.pc += 4;
        break;
    }
    case 0x03: { // loads
        const uint32_t ea = a + (uint32_t)imm_i(ins);
        const uint32_t word = s.dmem[(ea >> 2) & 255];
        const uint32_t byte = (word >> (8 * (ea & 3))) & 0xffu;
        const uint32_t half = (word >> (16 * ((ea >> 1) & 1))) & 0xffffu;
        uint32_t r = 0;
        switch (f3) {
        case 0: r = (uint32_t)(int32_t)(int8_t)byte; break;
        case 1: r = (uint32_t)(int32_t)(int16_t)half; break;
        case 2: r = word; break;
        case 4: r = byte; break;
        case 5: r = half; break;
        default: illegal(s, ins); s.instret++; return true;
        }
        s.x[rd] = r;
        s.pc += 4;
        break;
    }
    case 0x23: { // stores
        const uint32_t ea = a + (uint32_t)imm_s(ins);
        const uint32_t w = (ea >> 2) & 255;
        uint32_t mask = 0;
        uint32_t sh = 0;
        switch (f3) {
        case 0: sh = 8 * (ea & 3); mask = 0xffu << sh; break;
        case 1: sh = 16 * ((ea >> 1) & 1); mask = 0xffffu << sh; break;
        case 2: sh = 0; mask = 0xffffffffu; break;
        default: illegal(s, ins); s.instret++; return true;
        }
        s.dmem[w] = (s.dmem[w] & ~mask) | ((b << sh) & mask);
        s.written[w] = true;
        s.pc += 4;
        break;
    }
    case 0x63: { // branches
        if (f3 != 0 && f3 != 1) { illegal(s, ins); break; }
        const bool eq = (a == b);
        const bool taken = (f3 == 0) ? eq : !eq;
        s.pc += taken ? (uint32_t)imm_b(ins) : 4u;
        break;
    }
    case 0x6f: { // jal
        s.x[rd] = s.pc + 4;
        s.pc += (uint32_t)imm_j(ins);
        break;
    }
    case 0x67: { // jalr
        if (f3 != 0) { illegal(s, ins); break; }
        const uint32_t t = (a + (uint32_t)imm_i(ins)) & ~1u;
        s.x[rd] = s.pc + 4;
        s.pc = t;
        break;
    }
    case 0x37: // lui
        s.x[rd] = ins & 0xfffff000u;
        s.pc += 4;
        break;
    default:
        illegal(s, ins);
        break;
    }
    s.instret++;
    s.x[0] = 0;
    return true;
}

Stop iss_run(IssState& s, uint64_t max_instr) {
    for (;;) {
        if (fetch(s) == HALT_WORD) return Stop::Halt;
        if (s.instret == max_instr) return Stop::Limit;
        iss_step(s);
    }
}

static void append_hex(std::string& out, uint32_t v) {
    char buf[16];
    std::snprintf(buf, sizeof buf, "\"0x%08x\"", v);
    out += buf;
}

std::string iss_to_json(const IssState& s, Stop stop, bool full) {
    std::string out = "{\n";
    out += stop == Stop::Halt ? "  \"stop\": \"halt\",\n" : "  \"stop\": \"limit\",\n";
    out += "  \"pc\": ";
    if (stop == Stop::Halt) append_hex(out, s.pc); else out += "null";
    out += ",\n  \"x\": [";
    for (int i = 0; i < 32; i++) {
        if (i) out += ", ";
        append_hex(out, s.x[i]);
    }
    out += "],\n  \"mem\": [";
    bool first = true;
    for (int w = 0; w < DMEM_WORDS; w++) {
        if (!s.written[w]) continue;
        if (!first) out += ", ";
        first = false;
        out += "[";
        append_hex(out, (uint32_t)w * 4u);
        out += ", ";
        append_hex(out, s.dmem[w]);
        out += "]";
    }
    out += "]";
    if (full) {
        char buf[64];
        std::snprintf(buf, sizeof buf, ",\n  \"instret\": %" PRIu64, s.instret);
        out += buf;
        out += ",\n  \"next_pc\": ";
        append_hex(out, s.pc);
    }
    out += "\n}\n";
    return out;
}
