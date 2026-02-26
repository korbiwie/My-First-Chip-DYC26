module macro_sand_array #(
    parameter int unsigned ROWS = 32,        // needs to be a multiple of ROWS_SMALL
    parameter int unsigned COLS = 32,        // needs to be a multiple of COLS_SMALL
    parameter int unsigned ROWS_SMALL = 4,   // needs to be >1
    parameter int unsigned COLS_SMALL = 4   // needs to be >1
)(
    input clk,
    input rst_n,
    input new_frame_i,
    input drop_i,
    input [8:0] drop_x,
    input [8:0] drop_y,
    input [8:0] resolution,
    input [$clog2(COLS)-1:0] stack_addr_x,   //clog2 = min necessary bits to display COLS
    input [$clog2(ROWS)-1:0] stack_addr_y,

    output logic [2:0] stack_data
);

    localparam int unsigned GRID_SIZE = ROWS * COLS;
    localparam int unsigned GRID_SIZE_BORDER = (ROWS+2) * (COLS+2);
    localparam int unsigned GRID_SIZE_SMALL = ROWS_SMALL * COLS_SMALL;
    localparam int unsigned GRID_SIZE_BORDER_SMALL = (ROWS_SMALL+2) * (COLS_SMALL+2);

    localparam int unsigned RAM_SIZE = ((GRID_SIZE + GRID_SIZE_SMALL - 1) / GRID_SIZE_SMALL) * GRID_SIZE_SMALL;

    logic [2:0] stack_a [0:RAM_SIZE-1];
    logic [2:0] stack_b [0:RAM_SIZE-1];
    logic read_stack_a;

    logic [$clog2(RAM_SIZE):0] vga_ram_addr;
    
    always_comb begin
        vga_ram_addr = ((stack_addr_y/ROWS_SMALL) * (resolution/COLS_SMALL) + (stack_addr_x/COLS_SMALL)) * GRID_SIZE_SMALL 
                       + (stack_addr_x % COLS_SMALL) + (stack_addr_y % ROWS_SMALL) * COLS_SMALL;
    end

    logic [0:GRID_SIZE_BORDER-1] collapse, collapseNew;
    logic [2:0] stack_small_i [0:GRID_SIZE_SMALL-1];
    wire [2:0] stack_small_o [0:GRID_SIZE_SMALL-1];
    logic [0:GRID_SIZE_BORDER_SMALL-1] collapse_small;
    wire [0:GRID_SIZE_SMALL-1] collapseNew_small;

    logic [8:0] drop_row, drop_col;

    logic [($clog2(ROWS+1)-1):0] index_row;
    logic [($clog2(COLS+1)-1):0] index_col;
    logic [$clog2(GRID_SIZE):0] index;
    logic [$clog2(GRID_SIZE_BORDER):0] index_border;

    logic [($clog2(ROWS_SMALL+1)-1):0] active_rows, active_cols;
    logic drop_small, toppled, toppledNew, pending_frame;

    typedef enum logic [2:0] {Init, Prepare, Run, Update, Complete} state_type;
    state_type state, next_state;

    assign index_border = index_row*(COLS+2) + index_col;

    always_comb begin : state_logic
        next_state = state;
        case (state)
            Init:     if (pending_frame || new_frame_i) next_state = Prepare;
            Prepare:  next_state = Run;
            Run:      next_state = Update;
            Update:   if (index_row >= (resolution-ROWS_SMALL) && index_col >= (resolution-COLS_SMALL))
                         next_state = Complete;
                      else next_state = Prepare;
            Complete: next_state = Init;
            default:  next_state = Init;
        endcase
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= Init;
            read_stack_a <= 1;
            stack_data <= 3'b0;
        end else begin
            state <= next_state;
            if (new_frame_i) pending_frame <= 1'b1;

            if (vga_ram_addr < RAM_SIZE) begin
                stack_data <= read_stack_a ? stack_a[vga_ram_addr] : stack_b[vga_ram_addr];
            end

            case (state)
                Init: begin
                    index <= 0; index_col <= 0; index_row <= 0;
                    toppledNew <= 0; drop_col <= drop_x; drop_row <= drop_y;
                    pending_frame <= 1'b0;
                end
                Prepare: begin
                    for (int unsigned r = 0; r < ROWS_SMALL+2; r++)
                        for (int unsigned c = 0; c < COLS_SMALL+2; c++)
                            collapse_small[r*(COLS_SMALL+2)+c] <= collapse[(index_border+r*(COLS+2))+c];

                    for (int unsigned i = 0; i < GRID_SIZE_SMALL; i++)
                        stack_small_i[i] <= read_stack_a ? stack_a[index+i] : stack_b[index+i];

                    drop_small <= (drop_col < COLS_SMALL && drop_row < ROWS_SMALL && drop_i && !toppled);
                    active_rows <= (resolution - index_row >= ROWS_SMALL) ? ROWS_SMALL : (resolution - index_row);
                    active_cols <= (resolution - index_col >= COLS_SMALL) ? COLS_SMALL : (resolution - index_col);
                end
                Update: begin
                    for (int unsigned r = 0; r < ROWS_SMALL; r++) begin
                        for (int unsigned c = 0; c < COLS_SMALL; c++) begin
                            collapseNew[index_border+((r+1)*(COLS+2))+c+1] <= collapseNew_small[r*COLS_SMALL + c];
                            if (collapseNew_small[r*COLS_SMALL + c]) toppledNew <= 1;
                        end
                    end
                    for (int unsigned i = 0; i < GRID_SIZE_SMALL; i++) begin
                        if (read_stack_a) stack_b[index+i] <= stack_small_o[i];
                        else              stack_a[index+i] <= stack_small_o[i];
                    end
                    index <= index + GRID_SIZE_SMALL;
                    if (index_col >= (resolution-COLS_SMALL)) begin
                        index_col <= 0; index_row <= index_row + ROWS_SMALL;
                        drop_row <= drop_row - ROWS_SMALL; drop_col <= drop_x;
                    end else begin
                        index_col <= index_col + COLS_SMALL; drop_col <= drop_col - COLS_SMALL;
                    end
                end
                Complete: begin
                    toppled <= toppledNew;
                    read_stack_a <= ~read_stack_a;
                    for (int unsigned i = 0; i < GRID_SIZE_BORDER; i++) collapse[i] <= collapseNew[i];
                end
            endcase
        end
    end

    sand_array_for_macro #(
        .ROWS(ROWS_SMALL), 
        .COLS(COLS_SMALL)) u_sand_array (
        .clk(clk), 
        .rst_n(rst_n), 
        .activated_i(1'b1), 
        .collapse_i(collapse_small),
        .drop_i(drop_small), 
        .drop_x(drop_col), 
        .drop_y(drop_row[4:0]),
        .stack_i(stack_small_i), 
        .activeCols_i(active_cols), 
        .activeRows_i(active_rows),
        .collapse_o(collapseNew_small), 
        .stack_o(stack_small_o)
    );

endmodule