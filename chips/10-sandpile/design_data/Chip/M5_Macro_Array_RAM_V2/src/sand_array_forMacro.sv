module sand_array_for_macro #(
    parameter int unsigned ROWS = 5,
    parameter int unsigned COLS = 5,

    parameter int unsigned GRID_SIZE = ROWS * COLS,
    parameter int unsigned GRID_SIZE_BORDER = (ROWS+2) * (COLS+2)
)(
    input clk,
    input rst_n,
    input activated_i,
    input drop_i,
    input [8:0] drop_x,       //clog2 = min necessary bits to display ROWS
    input [8:0] drop_y,
    input [0:GRID_SIZE_BORDER-1] collapse_i,
    input [2:0] stack_i [0:GRID_SIZE-1],
    input [($clog2(ROWS+1)-1):0] activeRows_i,
    input [($clog2(COLS+1)-1):0] activeCols_i,

    output logic [2:0] stack_o [0:GRID_SIZE-1],
    output logic [0:GRID_SIZE-1] collapse_o
);

    localparam int unsigned COLS_BORDER = COLS+2;

    genvar r, c;
    generate
        for (r = 0; r < ROWS; r++) begin : GEN_ROW
            for (c = 0; c < COLS; c++) begin : GEN_COL
                
                localparam [($clog2(GRID_SIZE_BORDER)-1):0] index_border = ((r+1)*COLS_BORDER+c+1);

                sand_cell u_cell (
                    .clk        (clk),
                    .rst_n      (rst_n),
                    .activated_i((r < activeRows_i && c < activeCols_i) ? activated_i : 1'b0),
                    .drop_i     ((r == drop_y && c == drop_x) ? drop_i : 1'b0),
                    .left_i     (collapse_i[index_border-1]),
                    .right_i    (collapse_i[index_border+1]),
                    .up_i       (collapse_i[index_border-COLS_BORDER]),
                    .down_i     (collapse_i[index_border+COLS_BORDER]),
                    .stack_i    (stack_i[r*COLS+c][1:0]),
                    
                    .collapse_o (collapse_o[(r*COLS+c)]),
                    .stack_o (stack_o[r*COLS + c])
                );
            end
        end
    endgenerate

endmodule