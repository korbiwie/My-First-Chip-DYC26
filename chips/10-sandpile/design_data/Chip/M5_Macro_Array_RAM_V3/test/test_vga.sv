module test_vga #(
    parameter MAX_SIZE = 64,
    parameter GRID_SIZE = MAX_SIZE*MAX_SIZE,
    parameter ROWS_SMALL = 1,
    parameter COLS_SMALL = 16
)(
    input clk,
    input rst_n,
    input new_frame_i,
    input drop_i,
    input [8:0] drop_x,
    input [8:0] drop_y,
    input [8:0] resolution,
    // input [9:0] pixel_x,
    // input [9:0] pixel_y, 

    output logic new_data,
    output [2:0] pixel_data,
    output logic [3:0] vga_r,
    output logic [3:0] vga_g,
    output logic [3:0] vga_b,
    output logic vga_hs,
    output logic vga_vs
);

    logic [7:0] stack_addr_x;
    logic [7:0] stack_addr_y;
    logic [2:0] stack_data;

    assign pixel_data = stack_data;

    macro_sand_array #(
        .ROWS(MAX_SIZE),
        .COLS(MAX_SIZE),
        .ROWS_SMALL(ROWS_SMALL),
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

    top_vga_sandpile #(.MAX_SIZE(MAX_SIZE)) uut (
        .clk(clk),
        .rst_n(rst_n),
        .grid_data(stack_data),
        .grid_addr_x(stack_addr_x),
        .grid_addr_y(stack_addr_y),
        .resolution(resolution), 
        .vga_r(vga_r),
        .vga_g(vga_g),
        .vga_b(vga_b),
        .vga_hs(vga_hs),
        .vga_vs(vga_vs)
    );

endmodule