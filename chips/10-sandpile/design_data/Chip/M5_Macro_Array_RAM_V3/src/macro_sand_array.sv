module macro_sand_array #(
    parameter int unsigned ROWS = 64,           // needs to be a multiple of ROWS_SMALL
    parameter int unsigned COLS = 64,           // needs to be a multiple of COLS_SMALL
    parameter int unsigned ROWS_SMALL = 1,      // needs to be 1
    parameter int unsigned COLS_SMALL = COLS/4  // should not be adjusted
)(
    input clk,
    input rst_n,
    input new_frame_i,
    input drop_i,
    input [8:0] drop_x,
    input [8:0] drop_y,
    input [8:0] resolution,
    input [7:0] stack_addr_x,   //clog2 = min necessary bits to display COLS
    input [7:0] stack_addr_y,

    output logic [2:0] stack_data,
    output logic new_data
);

    localparam int unsigned GRID_SIZE = ROWS * COLS;
    localparam int unsigned GRID_SIZE_BORDER = (ROWS+2) * (COLS+2);
    localparam int unsigned GRID_SIZE_SMALL = ROWS_SMALL * COLS_SMALL;
    localparam int unsigned GRID_SIZE_BORDER_SMALL = (ROWS_SMALL+2) * (COLS_SMALL+2);

    parameter int unsigned TILES_TOTAL = (GRID_SIZE + GRID_SIZE_SMALL - 1) / GRID_SIZE_SMALL;

    wire [1:0] stack_small_i [0:GRID_SIZE_SMALL-1];
    wire [1:0] stack_small_o [0:GRID_SIZE_SMALL-1];
    logic [0:GRID_SIZE_BORDER_SMALL-1] collapse_small;
    wire [0:GRID_SIZE_SMALL-1] collapseNew_small;

    logic [8:0] drop_row, drop_col;

    logic [($clog2(ROWS+1)-1):0] index_row;
    logic [($clog2(COLS+1)-1):0] index_col;
    logic [7:0] tile_addr;
    logic [$clog2(GRID_SIZE_BORDER):0] index_border;

    logic drop_small, toppled, toppledNew, pending_frame;

    logic read_RAM, write_RAM, reset_tile, read_ram_a;
    logic new_adress;
    logic load_first_tile, load_next_tile;

    typedef enum logic [3:0] {Init, Reset_RAM, Complete_Reset, New_Frame, Prepare, Load_RAM, Run, Update, Complete} state_type;
    state_type state, next_state;

    always_comb begin
        index_border = index_row*(COLS+2) + index_col;     //index if border is needed
    end

    always_comb begin : state_logic
        next_state = state;
        case (state)
            Init: next_state = Reset_RAM;
            Reset_RAM: if (tile_addr >= (TILES_TOTAL-1)) next_state = Complete_Reset;
            Complete_Reset: next_state = New_Frame;
            New_Frame: if (pending_frame || new_frame_i) next_state = Prepare;
            Prepare: next_state = Load_RAM;
            Load_RAM: next_state = Run;
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
        load_next_tile <= 0;
        load_first_tile <= 0;

        if (new_frame_i) pending_frame <= 1'b1;
        
        if (!rst_n) begin
            state <= Init;
            toppled <= 0;
            toppledNew <= 0;
            drop_small <= 0;
            tile_addr <= 0;
            read_ram_a <= 0;
            new_adress <= 0;
        end else begin        
            state <= next_state;
            case (state)
                Init: begin
                    tile_addr <= 0;
                    load_first_tile <= 1;
                    read_ram_a <= 0;
                    new_adress <= 0;
                    drop_small <= 0;
                    pending_frame <= 1'b0;
                end

                Reset_RAM: begin
                    if (new_adress) begin
                        tile_addr <= tile_addr + 1;
                        load_next_tile <= 1;
                    end else
                        reset_tile <= 1;
                    new_adress <= ~new_adress;
                end

                Complete_Reset: begin
                    read_ram_a <= ~read_ram_a;
                    pending_frame <= 1'b0;
                    load_first_tile <= 1;
                    read_RAM <= 1;
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
                    read_RAM <= 1;

                    drop_small <= drop_col >= 0 && drop_col < COLS_SMALL
                            && drop_row >= 0 && drop_row < ROWS_SMALL
                            && drop_i && !toppled;
                end 

                Load_RAM: begin
                    //wait until RAM-data is loaded
                    read_RAM <= 1;
                end

                Run: begin
                    // sand_cell updates
                    write_RAM <= 1;
                    read_RAM <= 1;
                end

                Update: begin
                    if (collapseNew_small != 0)
                        toppledNew <= 1;

                    // for next RUN state
                    read_RAM <= 1;

                    // calc new tile_addr
                    tile_addr <= tile_addr + 1;
                    load_next_tile <= 1;
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
                    load_first_tile <= 1;
                    read_RAM <= 1;
                end

                default: ;
            endcase
        end
    end
   
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
        .cell_data(stack_data[1:0])
    );

    ram_collapse # (
        .ROWS(ROWS),
        .COLS(COLS),
        .COLS_TILE(COLS_SMALL)
    ) u_ram_collapse (
        .clk(clk),
        .rst_n(rst_n),
        .load_first_tile(load_first_tile),
        .load_next_tile(load_next_tile),
        .write_tile(write_RAM),
        .read_tile(read_RAM),
        .reset_tile(reset_tile),
        .read_ram_a(read_ram_a),
        .collapse_i(collapseNew_small),

        .cell_addr_x(stack_addr_x),
        .cell_addr_y(stack_addr_y),
        .resolution(resolution),
        
        .collapse_o(collapse_small),
        .cell_data(stack_data[2])
    );

endmodule