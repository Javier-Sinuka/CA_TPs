#include "iss.hpp"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <memory>
#include <string>

static int usage() {
    std::fprintf(stderr, "uso: iss.exe <prog.hex> [-o <out.json>] [--max-instr N] [--full]\n");
    return 2;
}

int main(int argc, char** argv) {
    std::string hex;
    std::string out_path;
    uint64_t max_instr = 1000000;
    bool full = false;

    for (int i = 1; i < argc; i++) {
        const std::string a = argv[i];
        if (a == "-o") {
            if (++i >= argc) return usage();
            out_path = argv[i];
        } else if (a == "--max-instr") {
            if (++i >= argc) return usage();
            char* end = nullptr;
            const unsigned long long v = std::strtoull(argv[i], &end, 10);
            if (end == argv[i] || *end != '\0') return usage();
            max_instr = (uint64_t)v;
        } else if (a == "--full") {
            full = true;
        } else if (!a.empty() && a[0] == '-') {
            return usage();
        } else if (hex.empty()) {
            hex = a;
        } else {
            return usage();
        }
    }
    if (hex.empty()) return usage();

    // IssState es grande (~3 KB): en el heap para no depender del stack.
    std::unique_ptr<IssState> s(new IssState);
    iss_reset(*s);
    std::string err;
    if (!iss_load_hex(*s, hex, err)) {
        std::fprintf(stderr, "iss: %s: %s\n", hex.c_str(), err.c_str());
        return 2;
    }
    const Stop stop = iss_run(*s, max_instr);
    const std::string json = iss_to_json(*s, stop, full);

    if (out_path.empty()) {
        std::fwrite(json.data(), 1, json.size(), stdout);
    } else {
        std::ofstream f(out_path, std::ios::binary);
        if (!f) {
            std::fprintf(stderr, "iss: no se pudo escribir %s\n", out_path.c_str());
            return 2;
        }
        f << json;
    }
    return 0;
}
