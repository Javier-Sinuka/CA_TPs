// Interfaz de la ALU para FPGA.
// Los registros guardan los valores cargados desde los switches; la ALU
// instanciada debajo permanece puramente combinacional.
module ALU_top #(
    parameter DATA_LEN = 8,
    parameter OP_LEN = 6
) (
    input wire button_1,
    input wire button_2,
    input wire button_3,
    input wire clock,
    input wire reset,
    input wire [DATA_LEN - 1 : 0] bus,

    output wire [DATA_LEN - 1 : 0] led,
    output wire test_led
);

    reg [DATA_LEN - 1 : 0] reg_data_A;
    reg [DATA_LEN - 1 : 0] reg_data_B;
    reg [OP_LEN - 1 : 0] reg_op;

    ALU #(
    .NB_OP(OP_LEN),
    .NB_DATA(DATA_LEN)
    )
    alu(
        .i_data_a(reg_data_A),
        .i_data_b(reg_data_B),
        .i_op(reg_op),
        .o_data(led)
    );

    always @(posedge clock)
    begin
        if(reset)
            begin
                reg_data_A <= {(DATA_LEN) {1'b0}};
                reg_data_B <= {(DATA_LEN) {1'b0}};
                reg_op <= {(OP_LEN) {1'b0}};
            end
        else if(button_1)
            reg_data_A <= bus[DATA_LEN-1:0];
        else if(button_2)
            reg_data_B <= bus[DATA_LEN-1:0];
        else if(button_3)
            reg_op <= bus[OP_LEN-1:0];

    end
    assign test_led = reset; 

endmodule
