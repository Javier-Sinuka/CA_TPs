    input  wire        i_clock,
    input  wire        i_reset,          // síncrono, activo en alto; prioridad sobre i_en
    input  wire        i_en,             // clock enable desde la Debug Unit
    output wire        o_halted,         // HALT válido en WB (combinacional)
    output wire [31:0] o_imem_addr,      // = pc_if (dirección en bytes)
    input  wire [31:0] i_imem_data,      // imem[o_imem_addr[9:2]], combinacional
    input  wire [4:0]  i_dbg_reg_addr,
    output wire [31:0] o_dbg_reg_data,   // x[i_dbg_reg_addr]; x0 = 0
    input  wire [3:0]  i_dbg_latch_sel,
    output wire [31:0] o_dbg_latch_word, // dump.md §3
    input  wire [7:0]  i_dbg_mem_addr,   // índice de palabra de dmem
    output wire [31:0] o_dbg_mem_data,   // 0 si la palabra no está sucia
    output wire        o_dbg_mem_dirty,
    output wire [31:0] o_dbg_pc          // = pc_if
