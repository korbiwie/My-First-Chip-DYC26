module sand_grid_RAM #(
    parameter int unsigned ROWS = 128,        // <= 128 needs to be a multiple of ROWS_TILE
    parameter int unsigned COLS = 128,        // <= 128 needs to be a multiple of COLS_TILE
    parameter int unsigned ROWS_TILE = 4,   // <= 4
    parameter int unsigned COLS_TILE = 4,   // <= 4
    parameter [1:0] CELL_WIDTH = 3,
    
    // Size of RAM
    parameter int unsigned RAM_WORD_SIZE = 16,
    // parameter int unsigned RAM_WORDS = 1024,

    parameter int unsigned TILE_SIZE = ROWS_TILE * COLS_TILE,
    parameter int unsigned GRID_SIZE = ROWS * COLS,
    parameter int unsigned TILES_TOTAL = (GRID_SIZE + RAM_WORD_SIZE - 1) / RAM_WORD_SIZE
)(
    input clk,
    input rst_n,
    input [9:0] tile_addr,
    input [CELL_WIDTH-1:0] tile_data_i [0:TILE_SIZE-1],
    input write_tile,
    input read_tile,
    input reset_tile,
    input read_ram_a,

    input [9:0] cell_addr_x,   //clog2 = min necessary bits to display COLS
    input [9:0] cell_addr_y,
    input [8:0] resolution,

    output logic [CELL_WIDTH-1:0] tile_data_o [0:TILE_SIZE-1],
    output logic [CELL_WIDTH-1:0] cell_data
);

    wire [15:0] sram_a_rdata [0:CELL_WIDTH-1];
    wire [15:0] sram_b_rdata [0:CELL_WIDTH-1];
    logic [15:0] sram_a_wdata [0:CELL_WIDTH-1];
    logic [15:0] sram_b_wdata [0:CELL_WIDTH-1];

    logic [15:0] tile_words [0:CELL_WIDTH-1]; // read/write buffer
    
    // Write / Read to RAM
    always_comb begin
        // Default assignments to avoid latches
        for (int i = 0; i < CELL_WIDTH; i++) begin
            sram_a_wdata[i] = '0;
            sram_b_wdata[i] = '0;
        end
        for (int i = 0; i < TILE_SIZE; i++)
            tile_data_o[i] = '0;

        if (reset_tile) begin
            if (read_ram_a) begin
                for (int unsigned sand_cell = 0; sand_cell < CELL_WIDTH; sand_cell++) begin 
                    sram_b_wdata[sand_cell] = 0;
                end
            end else begin
                for (int unsigned sand_cell = 0; sand_cell < CELL_WIDTH; sand_cell++) begin 
                    sram_a_wdata[sand_cell] = 0;
                end
            end
        end else if (write_tile) begin
            if (read_ram_a) begin
                for (int unsigned bit_nr = 0; bit_nr < CELL_WIDTH; bit_nr++) begin
                    for (int unsigned sand_cell = 0; sand_cell < TILE_SIZE; sand_cell++) begin 
                        sram_b_wdata[bit_nr][sand_cell] = tile_data_i[sand_cell][bit_nr];
                    end
                end
            end else begin
                for (int unsigned bit_nr = 0; bit_nr < CELL_WIDTH; bit_nr++) begin
                    for (int unsigned sand_cell = 0; sand_cell < TILE_SIZE; sand_cell++) begin 
                        sram_a_wdata[bit_nr][sand_cell] = tile_data_i[sand_cell][bit_nr];
                    end
                end
            end
        end 
        if (read_tile) begin
            if (read_ram_a) begin
                for (int unsigned sand_cell = 0; sand_cell < TILE_SIZE; sand_cell++) begin
                    for (int unsigned bit_nr = 0; bit_nr < CELL_WIDTH; bit_nr++) begin
                        tile_data_o[sand_cell][bit_nr] = sram_a_rdata[bit_nr][sand_cell];
                    end
                end
            end else begin
                for (int unsigned sand_cell = 0; sand_cell < TILE_SIZE; sand_cell++) begin
                    for (int unsigned bit_nr = 0; bit_nr < CELL_WIDTH; bit_nr++) begin
                        tile_data_o[sand_cell][bit_nr] = sram_b_rdata[bit_nr][sand_cell];
                    end
                end
            end
        end
    end

    //Read access single sand cell
    logic [9:0] tile_addr_cell;
    logic [3:0] cell_addr_in_tile;
    logic [3:0] cell_addr_in_tile_new;
    logic [15:0] sram_a_cell_rdata [0:CELL_WIDTH-1];
    logic [15:0] sram_b_cell_rdata [0:CELL_WIDTH-1];

    always_comb begin
        tile_addr_cell = ((cell_addr_y/ROWS_TILE) * (resolution/COLS_TILE) + cell_addr_x/COLS_TILE);
        cell_addr_in_tile_new = (cell_addr_x % COLS_TILE) + (cell_addr_y % ROWS_TILE)*COLS_TILE;
    end

    always_ff @(negedge clk) begin
        //delay new cell adress, as it takes one cycle before the RAM gets the new tile
        cell_addr_in_tile <= cell_addr_in_tile_new;

       if (tile_addr_cell < TILES_TOTAL) begin
            if (read_ram_a) begin
                for (int unsigned bit_nr = 0; bit_nr < CELL_WIDTH; bit_nr++) begin
                    cell_data[bit_nr] <= sram_a_cell_rdata[bit_nr][cell_addr_in_tile];
                end
            end else begin
                for (int unsigned bit_nr = 0; bit_nr < CELL_WIDTH; bit_nr++) begin
                    cell_data[bit_nr] <= sram_b_cell_rdata[bit_nr][cell_addr_in_tile];
                end
            end
        end     
    end

    // RAM Bank
    generate
        for (genvar b = 0; b < CELL_WIDTH; b++) begin : generate_sram

            `ifdef RAM_ASIC
                RM_IHPSG13_2P_1024x16_c2_bm_bist u_sram_a (
            `else
                RAM_FPGA_2P u_sram_a (
            `endif
                .A_CLK(clk),
                .A_ADDR(tile_addr),
                .A_DIN(sram_a_wdata[b]),
                .A_BM(16'hFFFF),    // Bit mask, what bits to write
                .A_WEN((write_tile || reset_tile) && ~read_ram_a),
                .A_MEN(1'b1),  //memory enable
                .A_REN(read_tile && read_ram_a),
                .A_DOUT(sram_a_rdata[b]),
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
                .B_ADDR(tile_addr_cell),
                .B_DIN(16'b0),
                .B_BM(16'b0),    // Bit mask, what bits to write
                .B_WEN(1'b0),
                .B_MEN(1'b1),  //memory enable
                .B_REN(1'b1),
                .B_DOUT(sram_a_cell_rdata[b]),
                .B_DLY(1'b1)
            );

            `ifdef RAM_ASIC
                RM_IHPSG13_2P_1024x16_c2_bm_bist u_sram_b (
            `else
                RAM_FPGA_2P u_sram_b (
            `endif
                .A_CLK(clk),
                .A_ADDR(tile_addr),
                .A_DIN(sram_b_wdata[b]),
                .A_BM(16'hFFFF),    // Bit mask, what bits to write
                .A_WEN((write_tile || reset_tile) && read_ram_a),
                .A_MEN(1'b1),  //memory enable
                .A_REN(read_tile && ~read_ram_a),
                .A_DOUT(sram_b_rdata[b]),
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
                .B_ADDR(tile_addr_cell),
                .B_DIN(16'b0),
                .B_BM(16'b0),    // Bit mask, what bits to write
                .B_WEN(1'b0),
                .B_MEN(1'b1),  //memory enable
                .B_REN(1'b1),
                .B_DOUT(sram_b_cell_rdata[b]),
                .B_DLY(1'b1)
            );
        end
    endgenerate

endmodule