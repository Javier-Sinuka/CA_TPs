// Tests unitarios del golden model (B-21). Sin dependencias: main propio y macro CHECK.
#include "iss.hpp"

#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <initializer_list>
#include <string>
#include <vector>

static int g_checks = 0;
static int g_fails = 0;

#define CHECK(cond)                                                              \
    do {                                                                         \
        g_checks++;                                                              \
        if (!(cond)) {                                                           \
            g_fails++;                                                           \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);          \
        }                                                                        \
    } while (0)

static uint32_t R(uint32_t f7,uint32_t rs2,uint32_t rs1,uint32_t f3,uint32_t rd,uint32_t op){return f7<<25|rs2<<20|rs1<<15|f3<<12|rd<<7|op;}
static uint32_t I(int32_t imm,uint32_t rs1,uint32_t f3,uint32_t rd,uint32_t op){return ((uint32_t)imm&0xFFF)<<20|rs1<<15|f3<<12|rd<<7|op;}
static uint32_t S(int32_t imm,uint32_t rs2,uint32_t rs1,uint32_t f3){uint32_t u=(uint32_t)imm;return ((u>>5)&0x7F)<<25|rs2<<20|rs1<<15|f3<<12|(u&0x1F)<<7|0x23;}
static uint32_t B(int32_t imm,uint32_t rs2,uint32_t rs1,uint32_t f3){uint32_t u=(uint32_t)imm;return ((u>>12)&1)<<31|((u>>5)&0x3F)<<25|rs2<<20|rs1<<15|f3<<12|((u>>1)&0xF)<<8|((u>>11)&1)<<7|0x63;}
static uint32_t U(uint32_t imm20,uint32_t rd){return imm20<<12|rd<<7|0x37;}
static uint32_t J(int32_t imm,uint32_t rd){uint32_t u=(uint32_t)imm;return ((u>>20)&1)<<31|((u>>1)&0x3FF)<<21|((u>>11)&1)<<20|((u>>12)&0xFF)<<12|rd<<7|0x6F;}

// Atajos de uso frecuente.
static uint32_t ADDI(uint32_t rd, uint32_t rs1, int32_t imm) { return I(imm, rs1, 0, rd, 0x13); }
static uint32_t ALU(uint32_t f7, uint32_t f3, uint32_t rd, uint32_t rs1, uint32_t rs2) { return R(f7, rs2, rs1, f3, rd, 0x33); }
static uint32_t LOAD(uint32_t f3, uint32_t rd, int32_t imm, uint32_t rs1) { return I(imm, rs1, f3, rd, 0x03); }
static uint32_t JALR(uint32_t rd, uint32_t rs1, int32_t imm) { return I(imm, rs1, 0, rd, 0x67); }

enum { F3_ADD = 0, F3_SLL = 1, F3_SLT = 2, F3_SLTU = 3, F3_XOR = 4, F3_SR = 5, F3_OR = 6, F3_AND = 7 };
enum { F3_B = 0, F3_H = 1, F3_W = 2, F3_BU = 4, F3_HU = 5 };

static IssState g;

// Arma imem con el programa (más un HALT al final), reinicia y corre.
static Stop run(const std::vector<uint32_t>& prog, uint64_t max = 1000) {
    iss_reset(g);
    size_t i = 0;
    for (uint32_t w : prog) g.imem[i++] = w;
    g.imem[i] = HALT_WORD;
    return iss_run(g, max);
}

static bool contains(const std::string& hay, const std::string& needle) {
    return hay.find(needle) != std::string::npos;
}

static int written_count() {
    int n = 0;
    for (int i = 0; i < DMEM_WORDS; i++) n += g.written[i] ? 1 : 0;
    return n;
}

static std::vector<uint32_t> suma_prog() {
    return {
        ADDI(1, 0, 0),
        ADDI(2, 0, 1),
        ADDI(3, 0, 11),
        ALU(0, F3_ADD, 1, 1, 2),
        ADDI(2, 2, 1),
        B(-8, 3, 2, 1),          // bne x2,x3,loop
        S(0, 1, 0, F3_W),        // sw x1,0(x0)
        HALT_WORD,
    };
}

static std::string tmp_path(const char* name) {
    const char* d = std::getenv("TEMP");
    if (!d) d = std::getenv("TMP");
    if (!d) d = ".";
    return std::string(d) + "/" + name;
}

static void write_file(const std::string& path, const std::string& content) {
    std::ofstream f(path, std::ios::binary);
    f << content;
}

static void test_alu() {
    // sra negativo
    CHECK(run({ADDI(1, 0, -16), ADDI(2, 0, 2), ALU(0x20, F3_SR, 3, 1, 2)}) == Stop::Halt);
    CHECK(g.x[3] == 0xfffffffcu);
    // srai 31
    run({ADDI(1, 0, -1), I(0x400 | 31, 1, F3_SR, 3, 0x13)});
    CHECK(g.x[3] == 0xffffffffu);
    // srl negativo
    run({ADDI(1, 0, -16), ADDI(2, 0, 2), ALU(0x00, F3_SR, 3, 1, 2)});
    CHECK(g.x[3] == 0x3ffffffcu);
    // slt vs sltu
    run({U(0x80000, 1), ADDI(2, 0, 1), ALU(0, F3_SLT, 3, 1, 2), ALU(0, F3_SLTU, 4, 1, 2)});
    CHECK(g.x[1] == 0x80000000u);
    CHECK(g.x[3] == 1u);
    CHECK(g.x[4] == 0u);
    // sltiu con -1
    run({ADDI(1, 0, 5), I(-1, 1, F3_SLTU, 3, 0x13)});
    CHECK(g.x[3] == 1u);
    // escribir x0
    run({ADDI(0, 0, 5), ALU(0, F3_ADD, 3, 0, 0)});
    CHECK(g.x[0] == 0u);
    CHECK(g.x[3] == 0u);
    // resto de las operaciones
    run({ADDI(1, 0, 12), ADDI(2, 0, 10),
         ALU(0x20, F3_ADD, 3, 1, 2),    // sub
         ALU(0, F3_XOR, 4, 1, 2),
         ALU(0, F3_OR, 5, 1, 2),
         ALU(0, F3_AND, 6, 1, 2),
         ALU(0, F3_SLL, 7, 1, 2),
         I(2, 1, F3_SR, 8, 0x13),       // srli x8,x1,2
         I(4, 1, F3_SLL, 9, 0x13),      // slli x9,x1,4
         I(4, 1, F3_AND, 10, 0x13),     // andi
         I(3, 1, F3_OR, 11, 0x13),      // ori
         I(-1, 1, F3_XOR, 12, 0x13),    // xori
         I(13, 1, F3_SLT, 13, 0x13)});  // slti
    CHECK(g.x[3] == 2u);
    CHECK(g.x[4] == 6u);
    CHECK(g.x[5] == 14u);
    CHECK(g.x[6] == 8u);
    CHECK(g.x[7] == 0x3000u);
    CHECK(g.x[8] == 3u);
    CHECK(g.x[9] == 0xc0u);
    CHECK(g.x[10] == 4u);
    CHECK(g.x[11] == 15u);
    CHECK(g.x[12] == 0xfffffff3u);
    CHECK(g.x[13] == 1u);
    // lui + addi con redondeo
    run({U(0x12346, 1), ADDI(1, 1, -1)});
    CHECK(g.x[1] == 0x12345fffu);
}

static void test_memory() {
    // lb/lbu en los 4 offsets
    {
        std::vector<uint32_t> p = {ADDI(1, 0, 0x80)};
        for (int k = 0; k < 4; k++) {
            p.push_back(S(k, 1, 0, F3_B));
            p.push_back(LOAD(F3_B, 10 + k, k, 0));
            p.push_back(LOAD(F3_BU, 20 + k, k, 0));
        }
        run(p);
        for (int k = 0; k < 4; k++) {
            CHECK(g.x[10 + k] == 0xffffff80u);
            CHECK(g.x[20 + k] == 0x00000080u);
        }
        CHECK(g.dmem[0] == 0x80808080u);
    }
    // lh/lhu
    run({U(8, 1), ADDI(1, 1, 1), S(2, 1, 0, F3_H), LOAD(F3_H, 3, 2, 0), LOAD(F3_HU, 4, 2, 0)});
    CHECK(g.x[3] == 0xffff8001u);
    CHECK(g.x[4] == 0x00008001u);
    CHECK(g.dmem[0] == 0x80010000u);
    // lw desalineado
    run({ADDI(1, 0, 0x55), S(4, 1, 0, F3_W), LOAD(F3_W, 3, 6, 0)});
    CHECK(g.x[3] == 0x55u);
    CHECK(g.dmem[1] == 0x55u);
    // sh desalineado
    run({U(1, 1), ADDI(1, 1, 0x234), S(1, 1, 0, F3_H), LOAD(F3_W, 3, 0, 0)});
    CHECK(g.x[3] == 0x00001234u);
    // la dirección da la vuelta
    run({ADDI(1, 0, 0x55), S(1024, 1, 0, F3_W), LOAD(F3_W, 3, 0, 0)});
    CHECK(g.x[3] == 0x55u);
    CHECK(g.written[0]);
    CHECK(written_count() == 1);
    // un store parcial combina sobre 0 y marca la palabra
    run({ADDI(1, 0, 0x7f), S(9, 1, 0, F3_B)});
    CHECK(g.dmem[2] == 0x00007f00u);
    CHECK(g.written[2]);
    CHECK(written_count() == 1);
}

static void test_control() {
    // jalr: el bit 0 del destino se limpia
    CHECK(run({ADDI(1, 0, 9), JALR(5, 1, 0), HALT_WORD}) == Stop::Halt);
    CHECK(g.pc == 8u);
    CHECK(g.x[5] == 8u);
    // jalr con rd == rs1
    run({ADDI(1, 0, 12), JALR(1, 1, 0), ADDI(2, 0, 99), ADDI(3, 0, 7)});
    CHECK(g.x[1] == 8u);
    CHECK(g.x[2] == 0u);
    CHECK(g.x[3] == 7u);
    // jal
    run({J(8, 1), ADDI(2, 0, 1), HALT_WORD});
    CHECK(g.x[1] == 4u);
    CHECK(g.pc == 8u);
    CHECK(g.x[2] == 0u);
    // beq tomado
    run({ADDI(1, 0, 1), ADDI(2, 0, 1), B(8, 2, 1, 0), ADDI(3, 0, 9), ADDI(4, 0, 5)});
    CHECK(g.x[3] == 0u);
    CHECK(g.x[4] == 5u);
    CHECK(g.pc == 20u);
    // beq no tomado
    run({ADDI(1, 0, 1), ADDI(2, 0, 2), B(8, 2, 1, 0), ADDI(3, 0, 9), ADDI(4, 0, 5)});
    CHECK(g.x[3] == 9u);
    CHECK(g.x[4] == 5u);
    // bne tomado y no tomado
    run({ADDI(1, 0, 1), ADDI(2, 0, 2), B(8, 2, 1, 1), ADDI(3, 0, 9), ADDI(4, 0, 5)});
    CHECK(g.x[3] == 0u);
    CHECK(g.x[4] == 5u);
    run({ADDI(1, 0, 2), ADDI(2, 0, 2), B(8, 2, 1, 1), ADDI(3, 0, 9), ADDI(4, 0, 5)});
    CHECK(g.x[3] == 9u);
    // límite
    CHECK(run({J(0, 0)}, 10) == Stop::Limit);
    CHECK(g.instret == 10u);
    // HALT inicial: imem vacía
    iss_reset(g);
    CHECK(iss_run(g, 1000) == Stop::Halt);
    CHECK(g.pc == 0u);
    CHECK(g.instret == 0u);
    CHECK(!iss_step(g));
    // un HALT justo después de la k-ésima instrucción se informa como Halt
    CHECK(run({ADDI(1, 0, 1), ADDI(2, 0, 2)}, 2) == Stop::Halt);
    // instrucción ilegal: nop con aviso en stderr
    iss_reset(g);
    g.imem[0] = 0xffffffffu;
    CHECK(iss_run(g, 1000) == Stop::Halt);
    CHECK(g.pc == 4u);
    CHECK(g.instret == 1u);
}

static void test_json() {
    CHECK(run(suma_prog()) == Stop::Halt);
    CHECK(g.instret == 34u);
    const std::string j = iss_to_json(g, Stop::Halt, false);
    CHECK(contains(j, "\"pc\": \"0x0000001c\""));
    CHECK(contains(j, "[\"0x00000000\", \"0x00000037\"]"));
    const std::string head = "{\n  \"stop\": \"halt\",\n  \"pc\": \"0x0000001c\",\n  \"x\": [\"0x00000000\", \"0x00000037\", ";
    CHECK(j.rfind(head, 0) == 0);
    CHECK(contains(j, "\"mem\": [[\"0x00000000\", \"0x00000037\"]]\n}\n"));
    CHECK(!contains(j, "instret"));

    CHECK(run(suma_prog(), 3) == Stop::Limit);
    const std::string l = iss_to_json(g, Stop::Limit, true);
    CHECK(contains(l, "\"stop\": \"limit\""));
    CHECK(contains(l, "\"pc\": null"));
    CHECK(contains(l, "\"instret\": 3"));
    CHECK(contains(l, "\"next_pc\": \"0x0000000c\""));
    CHECK(contains(l, "\"mem\": []"));
}

static void test_loader() {
    const std::string p = tmp_path("test_iss_tmp.hex");
    std::string err;

    write_file(p, "// comentario\n\n00100093\r\n  00000073  \n");
    iss_reset(g);
    CHECK(iss_load_hex(g, p, err));
    CHECK(g.imem[0] == 0x00100093u);
    CHECK(g.imem[1] == HALT_WORD);
    CHECK(g.imem[255] == HALT_WORD);

    write_file(p, "00000013\n\nxyz\n");
    iss_reset(g);
    CHECK(!iss_load_hex(g, p, err));
    CHECK(err == "línea 3 inválida");

    write_file(p, "123456789\n");
    CHECK(!iss_load_hex(g, p, err));
    CHECK(err == "línea 1 inválida");

    std::string big;
    for (int i = 0; i < 256; i++) big += "00000013\n";
    write_file(p, big);
    CHECK(iss_load_hex(g, p, err));
    CHECK(g.imem[255] == 0x13u);
    write_file(p, big + "00000013\n");
    CHECK(!iss_load_hex(g, p, err));
    CHECK(err == "más de 256 palabras");

    CHECK(!iss_load_hex(g, tmp_path("no_existe_test_iss.hex"), err));
    std::remove(p.c_str());
}

int main() {
    test_alu();
    test_memory();
    test_control();
    test_json();
    test_loader();
    if (g_fails) {
        std::printf("FAIL test_iss: %d de %d chequeos\n", g_fails, g_checks);
        return 1;
    }
    std::printf("PASS test_iss: %d chequeos\n", g_checks);
    return 0;
}
