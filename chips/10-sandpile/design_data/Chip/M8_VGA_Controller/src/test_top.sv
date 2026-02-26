module test_top#(
    parameter MAX_SIZE = 32,
    parameter GRID_SIZE = MAX_SIZE*MAX_SIZE
)(
    input logic clk,
    input logic rst_n,
    input logic new_frame_i,
    output logic frame_done,
    output logic [3:0] vga_r,
    output logic [3:0] vga_g,
    output logic [3:0] vga_b,
    output logic vga_hs,
    output logic vga_vs
);

    logic [2:0] stack_a [0:GRID_SIZE-1];
    logic [7:0]grid_size = 32;
    logic [$clog2(MAX_SIZE)-1:0] stack_addr_x;
    logic [$clog2(MAX_SIZE)-1:0] stack_addr_y;
    logic [2:0] stack_data;

    macro_sand_array #(
        .ROWS(MAX_SIZE),
        .COLS(MAX_SIZE),
        .ROWS_SMALL(MAX_SIZE),
        .COLS_SMALL(MAX_SIZE)
    ) array_unit (
        .clk(clk),
        .rst_n(rst_n),
        .new_frame_i(new_frame_i),
        .drop_i(1'b0),        // Im Timing-Test droppen wir erst mal nichts
        .drop_x(9'd0),
        .drop_y(9'd0),
        .resolution(9'd32),   // Fest auf 32 für den Test
        .stack_addr_x(stack_addr_x),
        .stack_addr_y(stack_addr_y),
        .stack_data(stack_data)
    );
    top_vga_sandpile #(.MAX_SIZE(MAX_SIZE)) uut (
        .clk(clk),
        .rst_n(rst_n),
        .grid_data(stack_data),
        .grid_addr_x(stack_addr_x),
        .grid_addr_y(stack_addr_y),
        .resolution(grid_size), 
        .vga_r(vga_r),
        .vga_g(vga_g),
        .vga_b(vga_b),
        .vga_hs(vga_hs),
        .vga_vs(vga_vs)
    );

endmodule