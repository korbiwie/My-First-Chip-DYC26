module test_top#(
    parameter MAX_SIZE = 32,
    parameter GRID_SIZE = MAX_SIZE*MAX_SIZE,
    parameter COLS_SMALL = 4
)(
    input clk,
    input rst_n,
    input new_frame_i,
    input drop_i,
    input [8:0] drop_x,
    input [8:0] drop_y,
    input [8:0] resolution,
    input [9:0] pixel_x,
    input [9:0] pixel_y, 

    output logic new_data,
    output [2:0] pixel_data
);

    logic [2:0] stack_a [0:GRID_SIZE-1];
    logic [7:0]grid_size = 32;
    logic [$clog2(MAX_SIZE)-1:0] stack_addr_x;
    logic [$clog2(MAX_SIZE)-1:0] stack_addr_y;
    logic [2:0] stack_data;

    assign pixel_data = stack_data;

    macro_sand_array #(
        .ROWS(MAX_SIZE),
        .COLS(MAX_SIZE),
        .ROWS_SMALL(COLS_SMALL),
        .COLS_SMALL(COLS_SMALL)
    ) array_unit (
        .clk(clk),
        .rst_n(rst_n),
        .new_frame_i(new_frame_i),
        .drop_i(drop_i),        // Im Timing-Test droppen wir erst mal nichts
        .drop_x(drop_x),
        .drop_y(drop_y),
        .resolution(resolution),   // Fest auf 32 für den Test
        .stack_addr_x(stack_addr_x),
        .stack_addr_y(stack_addr_y),
        .stack_data(stack_data),
        .new_data(new_data)
    );

    sandpile_renderer #(
        .MAX_SIZE(MAX_SIZE)
    ) renderer_unit (
        .clk(clk),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .grid_size(resolution),
        .grid_data(stack_data),
        .grid_addr_x(stack_addr_x),
        .grid_addr_y(stack_addr_y),
        .color(color)
    );

endmodule