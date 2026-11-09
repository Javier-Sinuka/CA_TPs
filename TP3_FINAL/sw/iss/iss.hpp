#pragma once
#include <cstdint>
#include <string>

constexpr uint32_t HALT_WORD  = 0x00000073u;
constexpr int      IMEM_WORDS = 256;
constexpr int      DMEM_WORDS = 256;

struct IssState {
    uint32_t x[32];
    uint32_t pc;
    uint32_t imem[IMEM_WORDS];
    uint32_t dmem[DMEM_WORDS];
    bool     written[DMEM_WORDS];   // palabra escrita al menos una vez
    uint64_t instret;               // instrucciones ejecutadas (HALT no cuenta)
};

enum class Stop { Halt, Limit };

void iss_reset(IssState& s);                                   // x=0, pc=0, dmem=0, written=false, instret=0, imem toda en HALT
bool iss_load_hex(IssState& s, const std::string& path, std::string& err);
bool iss_step(IssState& s);                                    // false si la instrucción en pc es HALT (no la ejecuta)
Stop iss_run(IssState& s, uint64_t max_instr);
std::string iss_to_json(const IssState& s, Stop stop, bool full);
