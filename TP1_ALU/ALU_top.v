// Interfaz de la ALU para FPGA.
// Los registros guardan los valores cargados desde los switches; la ALU
// instanciada debajo permanece puramente combinacional.
module ALU_top #(
    parameter DATA_WIDTH   = 8,
    parameter SWITCH_WIDTH = (DATA_WIDTH < 6) ? 6 : DATA_WIDTH
) (
    input  wire                    clk,
    input  wire                    reset,
    input  wire [SWITCH_WIDTH-1:0] SW,
    input  wire                    load_A,
    input  wire                    load_B,
    input  wire                    load_Op,
    output wire [DATA_WIDTH-1:0]   LED
);

    reg [DATA_WIDTH-1:0] A_reg;
    reg [DATA_WIDTH-1:0] B_reg;
    reg [5:0]            Op_reg;

    // Cada señal load_* debe durar un solo ciclo de clk. Mas adelante se
    // conectara a un pulso limpio generado al presionar los botones 1, 2 y 3.
    always @(posedge clk) begin
        if (reset) begin
            A_reg  <= {DATA_WIDTH{1'b0}};
            B_reg  <= {DATA_WIDTH{1'b0}};
            Op_reg <= 6'b000000;
        end else begin
            if (load_A)
                A_reg <= SW[DATA_WIDTH-1:0];

            if (load_B)
                B_reg <= SW[DATA_WIDTH-1:0];

            if (load_Op)
                Op_reg <= SW[5:0];
        end
    end

    ALU #(
        .DATA_WIDTH(DATA_WIDTH)
    ) alu_i (
        .A      (A_reg),
        .B      (B_reg),
        .Op     (Op_reg),
        .Result (LED)
    );

endmodule
