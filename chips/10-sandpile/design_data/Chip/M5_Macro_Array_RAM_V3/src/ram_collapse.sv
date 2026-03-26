module ram_collapse #(
    parameter int unsigned ROWS = 64,        // <= 64
    parameter int unsigned COLS = 64,     // should not be adjusted
    
    // size tile / macro array
    // parameter int unsigned ROWS_TILE = 1, //should not be adjusted
    parameter int unsigned COLS_TILE = COLS/4,   //should not be adjusted, needs to be COLS/4 and <= 16

    // Size of RAM
    parameter int unsigned RAM_WORD_SIZE = 32,  //constant
    // parameter int unsigned RAM_WORDS = 1024, //constant

    // parameter int unsigned TILE_SIZE = ROWS_TILE * COLS_TILE,
    parameter int unsigned TILE_SIZE_BORDER = 3 * (COLS_TILE+2)
)(
    input clk,
    input rst_n,
    
    input load_first_tile,   // read/write data for first tile (checked every falling edge), read first tile takes double amount of cycles
    input load_next_tile,    // read/write data for next tile (checked every falling edge)
    input read_ram_a,   // read from RAM bank A

    input read_tile,        // shouldnt be active during write/reset
    input write_tile,
    input reset_tile,
    input [0:COLS_TILE-1] collapse_i, // collapse array is saved as one row

    input [7:0] cell_addr_x,   //clog2 = min necessary bits to display COLS
    input [7:0] cell_addr_y,
    input [8:0] resolution,     // only multiples of COLS_TILE are working
    
    output logic [0:TILE_SIZE_BORDER-1] collapse_o,  // collapse array is saved as [c*rows + r]
    output logic cell_data
);

    wire [31:0] sram_a_rdata;
    wire [31:0] sram_b_rdata;
    logic [31:0] sram_wdata;
    logic [15:0] sram_wdata_buffer;

    logic [63:0] row_up, row_middle, row_below;

    logic [7:0] word_addr_to_load, word_addr_to_write;
    logic word_addr_updated;
    logic load_left_tile;    // left tile in RAM word
    logic load_left_word;    // left word in row
    logic load_first_row;    
    logic load_last_row;

    //use buffer depending on read_ram_a
    wire [31:0] sram_rdata;
    assign sram_rdata = read_ram_a ? sram_a_rdata : sram_b_rdata;

    // get last tile depending on resolution
    wire last_word_left, last_tile_in_row;
    wire [7:0] max_word_addr;
    wire [9:0] max_col;
    wire [1:0] max_index_tile_row;
    assign max_col = resolution - 1;
    assign max_index_tile_row = (max_col / COLS_TILE);
    assign last_word_left = !max_col[$clog2(COLS_TILE)+1];   // max resolution is 4*COLS_TILE, last word right if (resolution-1)/(2*COLS_TILE) == 1
    assign max_word_addr = 2*resolution - (last_word_left ? 2 : 1);
    assign last_tile_in_row = (~{load_left_word, load_left_tile}) == max_index_tile_row;


    // Perform slices outside always_comb as simulation cant handle this
    wire [(COLS_TILE-1):0] row_up_63, row_up_47, row_up_31, row_up_15;
    wire [(COLS_TILE-1):0] row_below_63, row_below_47, row_below_31, row_below_15;
    wire [(COLS_TILE-1):0] row_middle_63, row_middle_15;
    wire [(COLS_TILE-1):0] row_middle_47, row_middle_31;
    wire row_middle_47_left, row_middle_31_left, row_middle_15_left, row_middle_63_right, row_middle_47_right, row_middle_31_right;
    assign row_up_63 = row_up[63 -: COLS_TILE];
    assign row_up_47 = row_up[47 -: COLS_TILE];
    assign row_up_31 = row_up[31 -: COLS_TILE];
    assign row_up_15 = row_up[15 -: COLS_TILE];
    assign row_below_63 = row_below[63 -: COLS_TILE];
    assign row_below_47 = row_below[47 -: COLS_TILE];
    assign row_below_31 = row_below[31 -: COLS_TILE];
    assign row_below_15 = row_below[15 -: COLS_TILE];
    assign row_middle_63 = row_middle[63 -: COLS_TILE];
    assign row_middle_47 = row_middle[47 -: COLS_TILE];
    assign row_middle_31 = row_middle[31 -: COLS_TILE];
    assign row_middle_15 = row_middle[15 -: COLS_TILE];
    assign row_middle_47_left = row_middle[64-COLS_TILE];
    assign row_middle_31_left = row_middle[48-COLS_TILE];
    assign row_middle_15_left = row_middle[32-COLS_TILE];
    assign row_middle_63_right = row_middle[47];
    assign row_middle_47_right = row_middle[31];
    assign row_middle_31_right = row_middle[15];


    // Write / Read to RAM
    always_comb begin
    // Default assignments
    collapse_o = 0;
    sram_wdata = 0;
    if (reset_tile) begin
            sram_wdata = 0;
        end else if (write_tile) begin
            if (load_left_tile) begin
                sram_wdata[31 -: COLS_TILE] = collapse_i;
            end else begin
                sram_wdata[31 -: COLS_TILE] = sram_wdata_buffer;
                sram_wdata[15 -: COLS_TILE] = collapse_i;
            end
        end else if (read_tile) begin
            //corners are irrelevant (only collapse of direct neighbours count)
            collapse_o[0] = 0;
            collapse_o[COLS_TILE+1] = 0;
            collapse_o[2*COLS_TILE+4] = 0;
            collapse_o[TILE_SIZE_BORDER-1] = 0;
            if (load_left_word && load_left_tile) begin
                collapse_o[1 +: COLS_TILE] = row_up_63;
                collapse_o[COLS_TILE+2] = 0;    //left element of left word is always 0
                collapse_o[(COLS_TILE+3) +: COLS_TILE] = row_middle_63;
                collapse_o[(2*COLS_TILE+3)] = row_middle_63_right; //right element middle row
                collapse_o[(2*COLS_TILE+5) +: COLS_TILE] = row_below_63;
            end else if (load_left_word && !load_left_tile) begin
                collapse_o[1 +: COLS_TILE] = row_up_47;
                collapse_o[COLS_TILE+2] = row_middle_47_left; //left element middle row
                collapse_o[(COLS_TILE+3) +: COLS_TILE] = row_middle_47;
                collapse_o[(2*COLS_TILE+3)] = row_middle_47_right;       //right element middle row
                collapse_o[(2*COLS_TILE+5) +: COLS_TILE] = row_below_47;
            end else if (!load_left_word && load_left_tile) begin
                collapse_o[1 +: COLS_TILE] = row_up_31;
                collapse_o[COLS_TILE+2] = row_middle_31_left; //left element middle row
                collapse_o[(COLS_TILE+3) +: COLS_TILE] = row_middle_31;
                collapse_o[(2*COLS_TILE+3)] = row_middle_31_right;       //right element middle row
                collapse_o[(2*COLS_TILE+5) +: COLS_TILE] = row_below_31;
            end else begin
                collapse_o[1 +: COLS_TILE] = row_up_15;
                collapse_o[COLS_TILE+2] = row_middle_15_left; //left element middle row
                collapse_o[(COLS_TILE+3) +: COLS_TILE] = row_middle_15;
                collapse_o[(2*COLS_TILE+3)] = 0;    //right element of right word is always 0
                collapse_o[(2*COLS_TILE+5) +: COLS_TILE] = row_below_15;
            end
        end
    end

    //RAM-Handling is done on negedge as RAM works on posedge
    always_ff @(negedge clk) begin
        // read data from RAM
        if (read_tile && word_addr_updated) begin
            if (load_left_tile) begin
                if (load_left_word) begin
                    row_up <= row_middle;
                    row_middle <= row_below;
                    if (load_last_row)
                        row_below <= 0;
                    else
                        row_below[63:32] <= sram_rdata;
                end else if (!load_last_row) begin
                    row_below[31:0] <= sram_rdata;
                end
            end
        end

        if (write_tile) begin
            sram_wdata_buffer <= sram_wdata[31 -: COLS_TILE];
        end

        //Calculate new RAM adress to load
        if (load_first_tile) begin
            word_addr_to_load <= 0;
            word_addr_to_write <= 0;
            load_first_row <= 1;
            load_left_tile <= 1;
            load_left_word <= 1;
            load_last_row <= 0;
            row_below <= 0; //gets written to row_up during load_first_row
        end
        if (load_next_tile || load_first_row) begin
            if (!load_left_tile || load_first_row || last_tile_in_row) begin
                if (word_addr_to_load == max_word_addr)
                    load_last_row <= 1;
                if (word_addr_to_load[0] || last_word_left)
                    load_first_row <= 0;    //first row was loaded when last word of row (normally word 2) is loaded
                if (last_word_left) begin
                    word_addr_to_load <= word_addr_to_load + 2; // load word to the bottom of next tile
                end else begin
                    word_addr_to_load <= word_addr_to_load + 1; // load word to the bottom of next tile
                    load_left_word <= !load_left_word;
                end
            end
            if (last_tile_in_row || load_first_row) begin
                load_left_tile <= 1;
            end else begin
                load_left_tile <= !load_left_tile;
            end
        end

        if (load_next_tile && (last_tile_in_row || !load_left_tile)) begin
            //update write adress, when next tile in new word
            word_addr_to_write <= word_addr_to_write + (last_word_left ? 2 : 1);   
        end

        word_addr_updated <= load_first_tile || load_next_tile || load_first_row;
    end


    //Read access single sand cell
    logic [7:0] word_addr_cell;
    logic [4:0] cell_addr_in_word;
    wire [31:0] sram_a_cell_rdata;
    wire [31:0] sram_b_cell_rdata;

    always_comb begin
        word_addr_cell = cell_addr_y * 2 + cell_addr_x / (COLS_TILE*2);
        cell_addr_in_word = 31 - (cell_addr_x / COLS_TILE * 16) - cell_addr_x % COLS_TILE;     //every tile has 16 bytes reserved in RAM
    end

    always_ff @(negedge clk) begin
        if (read_ram_a) begin
            cell_data <= sram_a_cell_rdata[cell_addr_in_word];
        end else begin
            cell_data <= sram_b_cell_rdata[cell_addr_in_word];
        end 
    end



    // RAM Bank
    `ifdef RAM_ASIC
        RM_IHPSG13_2P_256x32_c2_bm_bist u_sram_a (
    `else
        RAM_FPGA_2P #(
            .DATA_WIDTH(32),
            .ADDR_WIDTH(256)
        ) u_sram_a (
    `endif
        .A_CLK(clk),
        .A_ADDR(read_ram_a ? word_addr_to_load : word_addr_to_write),
        .A_DIN(sram_wdata),
        .A_WEN((write_tile || reset_tile) && ~read_ram_a),
        .A_MEN(1'b1),  //memory enable
        .A_REN(read_tile && read_ram_a),
        .A_DOUT(sram_a_rdata),
        .A_BM(32'hFFFFFFFF),    // Bit mask, what bits to write
        .A_DLY(1'b1),
        
        // BIST (self-test) is not used
        `ifdef RAM_ASIC
            .A_BIST_EN(0),
            .A_BIST_DIN(0),
            .A_BIST_BM(0),
            .A_BIST_ADDR(0),
            .A_BIST_WEN(0),
            .A_BIST_MEN(0), 
            .A_BIST_REN(0), 
            .A_BIST_CLK(0),
            .B_BIST_EN(0),
            .B_BIST_DIN(0),
            .B_BIST_BM(0),
            .B_BIST_ADDR(0),
            .B_BIST_WEN(0),
            .B_BIST_MEN(0), 
            .B_BIST_REN(0), 
            .B_BIST_CLK(0),
        `endif

        //B is used for external read only access
        .B_CLK(clk),
        .B_ADDR(word_addr_cell),
        .B_DIN(32'b0),
        .B_WEN(1'b0),
        .B_MEN(1'b1),  //memory enable
        .B_REN(1'b1),
        .B_DOUT(sram_a_cell_rdata),
        .B_BM(32'b0),           // Bit mask, what bits to write
        .B_DLY(1'b1)
    );

    `ifdef RAM_ASIC
        RM_IHPSG13_2P_256x32_c2_bm_bist u_sram_b (
    `else
        RAM_FPGA_2P #(
            .DATA_WIDTH(32),
            .ADDR_WIDTH(256)
        ) u_sram_b (
    `endif
        .A_CLK(clk),
        .A_ADDR(read_ram_a ? word_addr_to_write : word_addr_to_load),
        .A_DIN(sram_wdata),
        .A_WEN((write_tile || reset_tile) && read_ram_a),
        .A_MEN(1'b1),  //memory enable
        .A_REN(read_tile && ~read_ram_a),
        .A_DOUT(sram_b_rdata),
        .A_BM(32'hFFFFFFFF),    // Bit mask, what bits to write
        .A_DLY(1'b1),

        // BIST (self-test) is not used
        `ifdef RAM_ASIC
            .A_BIST_EN(0),
            .A_BIST_DIN(0),
            .A_BIST_BM(0),
            .A_BIST_ADDR(0),
            .A_BIST_WEN(0),
            .A_BIST_MEN(0), 
            .A_BIST_REN(0), 
            .A_BIST_CLK(0),
            .B_BIST_EN(0),
            .B_BIST_DIN(0),
            .B_BIST_BM(0),
            .B_BIST_ADDR(0),
            .B_BIST_WEN(0),
            .B_BIST_MEN(0), 
            .B_BIST_REN(0), 
            .B_BIST_CLK(0),
        `endif

        //B is used for external read only access
        .B_CLK(clk),
        .B_ADDR(word_addr_cell),
        .B_DIN(32'b0),
        .B_WEN(1'b0),
        .B_MEN(1'b1),  //memory enable
        .B_REN(1'b1),
        .B_DOUT(sram_b_cell_rdata),
        .B_BM(32'b0),       // Bit mask, what bits to write
        .B_DLY(1'b1)
    );

endmodule