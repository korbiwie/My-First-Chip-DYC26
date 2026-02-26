module macro_sand_array #(
    parameter int unsigned ROWS = 32,        // needs to be a multiple of ROWS_SMALL
    parameter int unsigned COLS = 32,        // needs to be a multiple of COLS_SMALL
    parameter int unsigned ROWS_SMALL = 4,   // needs to be >1
    parameter int unsigned COLS_SMALL = 4,   // needs to be >1

    parameter int unsigned RAM_WORD_SIZE = 16
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

    output logic [2:0] stack_data,
    output logic new_data
);

    localparam int unsigned GRID_SIZE = ROWS * COLS;
    localparam int unsigned GRID_SIZE_BORDER = (ROWS+2) * (COLS+2);
    localparam int unsigned GRID_SIZE_SMALL = ROWS_SMALL * COLS_SMALL;
    localparam int unsigned GRID_SIZE_BORDER_SMALL = (ROWS_SMALL+2) * (COLS_SMALL+2);

    parameter int unsigned TILES_TOTAL = (GRID_SIZE + RAM_WORD_SIZE - 1) / RAM_WORD_SIZE;

    // localparam int unsigned RAM_SIZE = ((GRID_SIZE + GRID_SIZE_SMALL - 1) / GRID_SIZE_SMALL) * GRID_SIZE_SMALL;

    logic [0:GRID_SIZE_BORDER-1] collapse;    //add border to array for easier access
    logic [0:GRID_SIZE_BORDER-1] collapseNew;

    wire [2:0] stack_small_i [0:GRID_SIZE_SMALL-1];
    wire [2:0] stack_small_o [0:GRID_SIZE_SMALL-1];
    logic [0:GRID_SIZE_BORDER_SMALL-1] collapse_small;
    wire [0:GRID_SIZE_SMALL-1] collapseNew_small;

    logic [8:0] drop_row, drop_col;

    logic [($clog2(ROWS+1)-1):0] index_row;
    logic [($clog2(COLS+1)-1):0] index_col;
    logic [$clog2(TILES_TOTAL)-1:0] tile_addr;
    logic [$clog2(GRID_SIZE_BORDER):0] index_border;

    logic [($clog2(ROWS_SMALL+1)-1):0] active_rows;
    logic [($clog2(COLS_SMALL+1)-1):0] active_cols;
    logic drop_small, toppled, toppledNew, pending_frame;

    logic read_RAM, write_RAM, reset_tile, read_ram_a;

    typedef enum logic [2:0] {Init, Reset_RAM, Complete_Reset, New_Frame, Prepare, Run, Update, Complete} state_type;
    state_type state, next_state;

    always_comb begin
        index_border = index_row*(COLS+2) + index_col;     //index if border is needed
    end

    logic new_adress;

    always_comb begin : state_logic
        next_state = state;
        case (state)
            Init: next_state = Reset_RAM;
            Reset_RAM: if (tile_addr >= (TILES_TOTAL-1)) next_state = Complete_Reset;
            Complete_Reset: next_state = New_Frame;
            New_Frame: if (pending_frame || new_frame_i) next_state = Prepare;
            Prepare: next_state = Run;
            Run: next_state = Update;
            Update: begin
                if (index_row >= (resolution-ROWS_SMALL) && index_col >= (resolution-COLS_SMALL))
                    next_state = Complete;
                else next_state = Prepare;
            end
            Complete: next_state = New_Frame;
            default: next_state = Init;
        endcase
    end

    always_ff @(posedge clk) begin
        new_data <= 1'b0;
        reset_tile <= 0;
        read_RAM <= 0;
        write_RAM <= 0;

        if (new_frame_i) pending_frame <= 1'b1;
        
        if (!rst_n) begin
            state <= Init;
            toppled <= 0;
            toppledNew <= 0;
            drop_small <= 0;
            tile_addr <= 0;
            read_ram_a <= 0;
            new_adress <= 0;
            for (int unsigned i = 0; i < GRID_SIZE_BORDER; i++) begin
                collapse[i] <= 1'b0;
                collapseNew[i] <= 1'b0;
            end
        end else begin        
            state <= next_state;
            case (state)
                Init: begin
                    tile_addr <= 0;
                    read_ram_a <= 0;
                    new_adress <= 0;
                    drop_small <= 0;
                    pending_frame <= 1'b0;
                end

                Reset_RAM: begin
                    if (new_adress)
                        tile_addr <= tile_addr + 1;
                    else
                        reset_tile <= 1;
                    new_adress <= ~new_adress;
                end

                Complete_Reset: begin
                    read_ram_a <= ~read_ram_a;
                    pending_frame <= 1'b0;
                end

                New_Frame: begin
                    pending_frame <= 1'b0;
                    tile_addr <= 0;
                    read_RAM <= 1;
                    index_col <= 0;
                    index_row <= 0;
                    toppledNew <= 0;
                    drop_col <= drop_x;
                    drop_row <= drop_y;
                end

                Prepare: begin 
                    // read smaller arrays from memory
                    for (int unsigned r = 0; r < ROWS_SMALL+2; r++) begin        //add collapse of neighboring cells
                        for (int c = 0; c < COLS_SMALL+2; c++) begin
                            collapse_small[r*(COLS_SMALL+2)+c] <= collapse[(index_border+r*(COLS+2))+c];
                        end
                    end

                    read_RAM <= 1;

                    drop_small <= drop_col >= 0 && drop_col < COLS_SMALL
                            && drop_row >= 0 && drop_row < ROWS_SMALL
                            && drop_i && !toppled;  //&& (state == Run)

                    active_rows <= (resolution - index_row >= ROWS_SMALL) ? ROWS_SMALL : (resolution - index_row);
                    active_cols <= (resolution - index_col >= COLS_SMALL) ? COLS_SMALL : (resolution - index_col);
                end 

                Run: begin
                    // sand_cell updates
                    write_RAM <= 1;
                    read_RAM <= 1;
                end

                Update: begin
                    // copy output cell_array in grid
                    for (int unsigned r = 0; r < ROWS_SMALL; r++) begin
                        for (int unsigned c = 0; c < COLS_SMALL; c++) begin
                            collapseNew[index_border+((r+1)*(COLS+2))+c+1] <= collapseNew_small[r*COLS_SMALL + c];
                            if (collapseNew_small[r*COLS_SMALL + c]) begin
                                toppledNew <= 1;
                            end
                        end
                    end

                    // for next RUN state
                    read_RAM <= 1;

                    // calc new tile_addr
                    tile_addr <= tile_addr + 1;
                    if (index_col >= (resolution-COLS_SMALL)) begin
                        index_col <= 0;
                        index_row <= index_row + ROWS_SMALL;
                        drop_row <= drop_row - ROWS_SMALL;  
                        drop_col <= drop_x;  
                    end else begin 
                        index_col <= index_col + COLS_SMALL;
                        drop_col <= drop_col - COLS_SMALL;
                    end              
                end

                Complete: begin
                    // Full grid calculated
                    new_data <= 1'b1;
                    toppled <= toppledNew;
                    read_ram_a <= ~read_ram_a;
                    read_RAM <= 0;
                    for (int unsigned i = 0; i < GRID_SIZE_BORDER; i++)
                        collapse[i] <= collapseNew[i];
                    end
                default: ;
            endcase
        end
    end
   
    logic [2:0] debug_stack0;
    assign debug_stack0 = stack_small_i[0];

    sand_array_for_macro #(
        .ROWS(ROWS_SMALL),
        .COLS(COLS_SMALL)
    ) u_sand_array (
        .clk        (clk),
        .rst_n      (rst_n),
        .activated_i(1'b1),
        .collapse_i (collapse_small),
        .drop_i     (drop_small),
        .drop_x     (drop_col),
        .drop_y     (drop_row),
        .stack_i    (stack_small_i),
        .activeCols_i (active_cols),
        .activeRows_i (active_rows),

        .collapse_o (collapseNew_small),
        .stack_o    (stack_small_o)
    );

    sand_grid_RAM #(
        .ROWS(ROWS),
        .COLS(COLS),
        .ROWS_TILE(ROWS_SMALL),
        .COLS_TILE(COLS_SMALL)
    ) u_sand_grid_RAM (
        .clk(clk),
        .rst_n(rst_n),
        .resolution(resolution),
        .tile_addr(tile_addr),
        .write_tile(write_RAM),
        .read_tile(read_RAM),
        .reset_tile(reset_tile),
        .read_ram_a(read_ram_a),
        .cell_addr_x(stack_addr_x),
        .cell_addr_y(stack_addr_y),
        .tile_data_i(stack_small_o),

        .tile_data_o(stack_small_i),
        .cell_data(stack_data)
    );


endmodule